import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'device_profile.dart';
import 'model_catalogue.dart';
import 'model_recommender.dart';
import '../models/remote_catalogue_service.dart';
import '../models/custom_models_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Device profile provider
// ─────────────────────────────────────────────────────────────────────────────

/// Reads hardware specs from the native platform layer once at app launch.
/// Cached for the lifetime of the app — hardware doesn't change at runtime.
final deviceProfileProvider = FutureProvider<DeviceProfile>((ref) async {
  return DeviceProfileService().load();
});

// ─────────────────────────────────────────────────────────────────────────────
// Remote catalogue provider
// ─────────────────────────────────────────────────────────────────────────────

final _remoteCatalogueSvcProvider = Provider<RemoteCatalogueService>(
  (_) => RemoteCatalogueService(),
);

/// Merged catalogue (bundled + remote). Updates in the background when
/// the remote JSON is fresher than 12 hours old.
final catalogueProvider = FutureProvider<List<ModelVariant>>((ref) async {
  return ref.read(_remoteCatalogueSvcProvider).loadMerged();
});

/// Triggers a forced network refresh of the catalogue. Used by the
/// pull-to-refresh gesture in the model picker.
final catalogueRefreshProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(_remoteCatalogueSvcProvider).forceRefresh();
    ref.invalidate(catalogueProvider); // rebuilds rankedModelsProvider too
  };
});

// ─────────────────────────────────────────────────────────────────────────────
// Recommendation provider
// ─────────────────────────────────────────────────────────────────────────────

/// Derives the best model recommendation from the device profile.
/// Automatically re-derives if the device profile changes (e.g. RAM freed).
final modelRecommendationProvider =
    FutureProvider<ModelRecommendation>((ref) async {
  final device = await ref.watch(deviceProfileProvider.future);
  final catalogue = await ref.watch(catalogueProvider.future);
  return ModelRecommender().recommendFromCatalogue(device, catalogue);
});

// ─────────────────────────────────────────────────────────────────────────────
// All models provider (ranked)
// ─────────────────────────────────────────────────────────────────────────────

/// Provides all models, sorted with the recommended one first,
/// then best-fit to worst-fit, then models that don't fit at the bottom.
/// This is what the model picker list renders.
final rankedModelsProvider = FutureProvider<List<PickerModel>>((ref) async {
  final rec = await ref.watch(modelRecommendationProvider.future);
  final catalogue = await ref.watch(catalogueProvider.future);
  // User-imported (Hugging Face) models appear alongside the built-in ones.
  final custom = ref.watch(customModelsProvider);

  // Build a map of scores for models that passed the gates
  final scored = {for (final r in rec.allRanked) r.model.id: r};

  final result = <PickerModel>[];

  // Imported models first (the user explicitly chose them).
  for (final model in custom) {
    result.add(PickerModel(
      model: model,
      isRecommended: false,
      estimatedTokensPerSec: 0,
      fitsDevice: true,
      eliminationReason: null,
    ));
  }

  for (final model in catalogue) {
    if (scored.containsKey(model.id)) {
      final r = scored[model.id]!;
      result.add(PickerModel(
        model: model,
        isRecommended: model.id == rec.recommended.id,
        estimatedTokensPerSec: r.estimatedTokensPerSec,
        fitsDevice: true,
        eliminationReason: null,
      ));
    } else {
      final ruled =
          rec.ruledOut.where((r) => r.model.id == model.id).firstOrNull;
      result.add(PickerModel(
        model: model,
        isRecommended: false,
        estimatedTokensPerSec: 0,
        fitsDevice: false,
        eliminationReason: ruled?.reason,
      ));
    }
  }

  // Sort: recommended first, then by score desc, then incompatible last
  result.sort((a, b) {
    if (a.isRecommended) return -1;
    if (b.isRecommended) return 1;
    if (a.fitsDevice && !b.fitsDevice) return -1;
    if (!a.fitsDevice && b.fitsDevice) return 1;
    return b.estimatedTokensPerSec.compareTo(a.estimatedTokensPerSec);
  });

  return result;
});

// ─────────────────────────────────────────────────────────────────────────────
// Picker model — UI view model
// ─────────────────────────────────────────────────────────────────────────────

/// Flat view model for each row in the model picker.
/// Contains everything the UI needs — no business logic in the widget.
class PickerModel {
  const PickerModel({
    required this.model,
    required this.isRecommended,
    required this.estimatedTokensPerSec,
    required this.fitsDevice,
    required this.eliminationReason,
  });

  final ModelVariant model;
  final bool isRecommended;
  final double estimatedTokensPerSec;
  final bool fitsDevice;
  final EliminationReason? eliminationReason;

  String get speedLabel {
    if (!fitsDevice) return eliminationReason?.label ?? 'Not compatible';
    return '~${estimatedTokensPerSec.round()} t/s';
  }
}

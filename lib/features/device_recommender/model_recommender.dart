import 'device_profile.dart';
import 'model_catalogue.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Recommendation result
// ─────────────────────────────────────────────────────────────────────────────

/// The output of the recommendation engine.
///
/// Contains the single best model, why it was chosen, and what was ruled out
/// so the UI can show an honest, non-marketing explanation to the user.
class ModelRecommendation {
  const ModelRecommendation({
    required this.recommended,
    required this.estimatedTokensPerSec,
    required this.reasonSummary,
    required this.reasonDetail,
    required this.ruledOut,
    required this.allRanked,
    required this.deviceProfile,
  });

  /// The model we recommend loading first.
  final ModelVariant recommended;

  /// Projected generation speed on this device (t/s). Shown in the UI.
  final double estimatedTokensPerSec;

  /// One-line reason shown prominently in the picker.
  /// Written from the user's side — describes the outcome, not the logic.
  final String reasonSummary;

  /// Paragraph-length explanation for users who tap "why this model?".
  final String reasonDetail;

  /// Models that were considered but eliminated, with reasons.
  final List<RuledOutModel> ruledOut;

  /// All models ranked by fit score (best first).
  /// Used to render the full picker list with scores.
  final List<RankedModel> allRanked;

  /// The device profile used to generate this recommendation.
  final DeviceProfile deviceProfile;
}

class RuledOutModel {
  const RuledOutModel({required this.model, required this.reason});
  final ModelVariant model;
  final EliminationReason reason;
}

class RankedModel {
  const RankedModel({
    required this.model,
    required this.score,
    required this.estimatedTokensPerSec,
    required this.fitsInRam,
    required this.meetsSpeedFloor,
  });
  final ModelVariant model;
  final double score; // 0.0 – 1.0
  final double estimatedTokensPerSec;
  final bool fitsInRam;
  final bool meetsSpeedFloor;
}

enum EliminationReason {
  tooMuchRam,
  tooSlow,
  notEnoughStorage,
  chipTooSlow;

  String get label => switch (this) {
        EliminationReason.tooMuchRam => 'Needs more RAM than available',
        EliminationReason.tooSlow => 'Would be too slow on this device',
        EliminationReason.notEnoughStorage => 'Not enough storage to download',
        EliminationReason.chipTooSlow => 'Chip too slow for this model size',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// ModelRecommender
// ─────────────────────────────────────────────────────────────────────────────

/// Pure Dart recommendation engine. No Flutter, no IO — fully unit-testable.
///
/// Algorithm:
///   For each model in the catalogue (smallest to largest):
///     1. Check it fits in safe RAM budget → eliminate if not
///     2. Estimate token/s on this chip/GPU combo → eliminate if < floor
///     3. Check storage → eliminate if not enough space to download
///     4. Score it by a weighted combination of quality + speed
///   Pick the highest-scoring model that passed all gates.
///
/// The scoring deliberately weights quality (model size × context) over raw
/// speed — a 10 t/s experience on a good model beats 25 t/s on a weak one.
/// But we never recommend something that generates slower than [kMinTokensPerSec].
class ModelRecommender {
  const ModelRecommender({
    this.catalogue = kModelCatalogue,
    this.minTokensPerSec = kMinTokensPerSec,
  });

  final List<ModelVariant> catalogue;
  final double minTokensPerSec;

  /// The minimum acceptable generation speed.
  /// Below this, the streaming text feels broken and users disengage.
  static const double kMinTokensPerSec = 5.0;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Convenience: recommend using an externally-provided catalogue (e.g. from
  /// the remote catalogue service) rather than the bundled default.
  ModelRecommendation recommendFromCatalogue(
    DeviceProfile device,
    List<ModelVariant> externalCatalogue,
  ) {
    return ModelRecommender(catalogue: externalCatalogue).recommend(device);
  }

  ModelRecommendation recommend(DeviceProfile device) {
    if (device.chipTier == ChipTier.tooSlow) {
      return _tooSlowResult(device);
    }

    final baseline = device.chipTier.baseline3bTokensPerSec;
    final ranked = <RankedModel>[];
    final ruledOut = <RuledOutModel>[];

    for (final model in catalogue) {
      final tps = model.estimateTokensPerSec(
        baseline,
        hasGpu: device.hasGpuAcceleration,
      );

      // Gate 1: RAM
      if (model.ramRequiredBytes > device.safeModelRamBytes) {
        ruledOut.add(RuledOutModel(
          model: model,
          reason: EliminationReason.tooMuchRam,
        ));
        continue;
      }

      // Gate 2: Speed floor
      if (tps < minTokensPerSec) {
        ruledOut.add(RuledOutModel(
          model: model,
          reason: EliminationReason.tooSlow,
        ));
        continue;
      }

      // Gate 3: Storage (only gate if we'd need to download it)
      if (model.fileSizeBytes > device.freeStorageBytes) {
        ruledOut.add(RuledOutModel(
          model: model,
          reason: EliminationReason.notEnoughStorage,
        ));
        continue;
      }

      ranked.add(RankedModel(
        model: model,
        score: _score(model, tps, device),
        estimatedTokensPerSec: tps,
        fitsInRam: true,
        meetsSpeedFloor: true,
      ));
    }

    // Sort best first
    ranked.sort((a, b) => b.score.compareTo(a.score));

    if (ranked.isEmpty) {
      // Even the smallest model didn't fit — show the smallest as a fallback
      // with a clear warning. Better than crashing or showing nothing.
      return _fallbackResult(device, ruledOut);
    }

    final best = ranked.first;

    return ModelRecommendation(
      recommended: best.model,
      estimatedTokensPerSec: best.estimatedTokensPerSec,
      reasonSummary: _summaryFor(best, device),
      reasonDetail: _detailFor(best, device, ruledOut),
      ruledOut: ruledOut,
      allRanked: ranked,
      deviceProfile: device,
    );
  }

  // ── Scoring ────────────────────────────────────────────────────────────────

  /// Score a model variant for this device profile.
  ///
  /// Three components, weighted to produce a value in [0, 1]:
  ///
  ///   qualityScore  — proxy for model capability: param count × context length
  ///                   normalised against the largest model in the catalogue.
  ///                   Weight: 0.55 (quality matters most)
  ///
  ///   speedScore    — how far above the speed floor we are, capped at 30 t/s.
  ///                   We don't reward speed beyond 30 t/s much — users don't
  ///                   notice the difference above that.
  ///                   Weight: 0.25
  ///
  ///   ramMarginScore — how much headroom is left after loading the model.
  ///                    More headroom = more stable long conversations.
  ///                    Weight: 0.20
  double _score(ModelVariant model, double tps, DeviceProfile device) {
    // Quality proxy: params × log2(context) — context has diminishing returns
    const maxParams = 8.0;
    const maxContext = 131072.0;
    final qualityRaw = (model.parametersBillions / maxParams) *
        (model.contextLength.toDouble().log2() / maxContext.log2());
    final qualityScore = qualityRaw.clamp(0.0, 1.0);

    // Speed: normalise 0–30 t/s range
    final speedScore = (tps / 30.0).clamp(0.0, 1.0);

    // RAM margin: leftover headroom after model load
    final remaining = device.safeModelRamBytes - model.ramRequiredBytes;
    final ramMarginScore =
        (remaining / device.safeModelRamBytes).clamp(0.0, 1.0);

    return (qualityScore * 0.55) +
        (speedScore * 0.25) +
        (ramMarginScore * 0.20);
  }

  // ── Human-readable explanations ────────────────────────────────────────────

  String _summaryFor(RankedModel best, DeviceProfile device) {
    final tps = best.estimatedTokensPerSec.round();
    final name = best.model.displayName;
    final tier = device.chipTier.label;
    return '$name is the best fit for your $tier device — '
        'estimated $tps tokens/sec.';
  }

  String _detailFor(
    RankedModel best,
    DeviceProfile device,
    List<RuledOutModel> ruledOut,
  ) {
    final model = best.model;
    final tps = best.estimatedTokensPerSec.toStringAsFixed(1);
    final ramGb = (model.ramRequiredBytes / 1e9).toStringAsFixed(1);
    final freeGb = device.freeRamGb;

    final buffer = StringBuffer();
    buffer.writeln(
      '${model.displayName} (${model.quant.label}) needs ${ramGb}GB of RAM. '
      'Your device currently has ${freeGb}GB free, which gives a comfortable '
      'margin for long conversations.',
    );
    buffer.writeln();
    buffer.writeln(
      'On your ${device.chipTier.label} chip'
      '${device.hasGpuAcceleration ? " with GPU acceleration" : " (CPU only)"}, '
      'you can expect around $tps tokens per second — '
      'fast enough that responses feel instant.',
    );

    final tooLarge = ruledOut
        .where((r) => r.reason == EliminationReason.tooMuchRam)
        .map((r) => r.model.displayName)
        .toList();

    if (tooLarge.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(
        'Larger models (${tooLarge.join(", ")}) were ruled out because they '
        'would exceed the safe RAM budget and risk the OS terminating the app '
        'mid-conversation.',
      );
    }

    return buffer.toString().trim();
  }

  // ── Edge case results ──────────────────────────────────────────────────────

  ModelRecommendation _tooSlowResult(DeviceProfile device) {
    final smallest = catalogue.first;
    return ModelRecommendation(
      recommended: smallest,
      estimatedTokensPerSec:
          smallest.estimateTokensPerSec(device.chipTier.baseline3bTokensPerSec),
      reasonSummary:
          'Your device is older, so we recommend the smallest available model.',
      reasonDetail:
          'Your chip (${device.chipTier.label}) is below the performance '
          'threshold for a good experience with most models. '
          '${smallest.displayName} is the lightest option and will give '
          'the most usable response speed.',
      ruledOut: catalogue
          .skip(1)
          .map((m) =>
              RuledOutModel(model: m, reason: EliminationReason.chipTooSlow))
          .toList(),
      allRanked: [
        RankedModel(
          model: smallest,
          score: 0.1,
          estimatedTokensPerSec: smallest.estimateTokensPerSec(
            device.chipTier.baseline3bTokensPerSec,
          ),
          fitsInRam: true,
          meetsSpeedFloor: false,
        ),
      ],
      deviceProfile: device,
    );
  }

  ModelRecommendation _fallbackResult(
    DeviceProfile device,
    List<RuledOutModel> ruledOut,
  ) {
    final smallest = catalogue.first;
    final tps = smallest.estimateTokensPerSec(
      device.chipTier.baseline3bTokensPerSec,
      hasGpu: device.hasGpuAcceleration,
    );

    return ModelRecommendation(
      recommended: smallest,
      estimatedTokensPerSec: tps,
      reasonSummary:
          'Limited RAM detected. We recommend the smallest model to avoid crashes.',
      reasonDetail:
          'Your device has ${device.freeRamGb}GB of RAM available. All larger '
          'models were ruled out to avoid the OS terminating the app. '
          '${smallest.displayName} is the lightest option in the catalogue.',
      ruledOut: ruledOut,
      allRanked: [
        RankedModel(
          model: smallest,
          score: 0.0,
          estimatedTokensPerSec: tps,
          fitsInRam: true,
          meetsSpeedFloor: tps >= minTokensPerSec,
        ),
      ],
      deviceProfile: device,
    );
  }
}

// ─── Helper extension ─────────────────────────────────────────────────────────

extension on double {
  double log2() => this <= 0 ? 0 : (this * 0.693147).ceil().toDouble();
}

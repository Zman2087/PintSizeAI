import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'image_gen_service.dart';
import 'sd_model_manager.dart';

export 'sd_model_manager.dart';

/// The active image gen service: real (Core ML) if a model is loaded, mock otherwise.
final imageGenProvider = Provider<LocalImageGen>((ref) {
  final real = ref.watch(activeImageGenProvider);
  if (real != null) return real;

  // Fall back to mock when no Core ML model is loaded
  final mock = LocalImageGenMock();
  ref.onDispose(mock.dispose);
  return mock;
});

final imageGenStatusProvider =
    StateProvider<ImageGenStatus>((ref) => ImageGenStatus.idle);

final imageGenProgressProvider = StateProvider<double>((ref) => 0.0);

/// True when a real Core ML model is loaded and ready.
final imageGenIsRealProvider = Provider<bool>((ref) {
  return ref.watch(activeImageGenProvider) != null;
});

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'image_gen_service.dart';

/// Real on-device implementation using Apple's ml-stable-diffusion
/// via the 'pintsize/image_gen' Swift method channel.
class LocalImageGenReal implements LocalImageGen {
  static const _method = MethodChannel('pintsize/image_gen');
  static const _events = EventChannel('pintsize/image_gen_progress');

  final _progressCtrl = StreamController<double>.broadcast();
  StreamSubscription<dynamic>? _eventSub;

  @override
  ImageGenStatus status = ImageGenStatus.idle;

  @override
  Stream<double> get progressStream => _progressCtrl.stream;

  LocalImageGenReal() {
    // Core ML only exists on iOS — don't touch the channel on other platforms.
    if (!Platform.isIOS) return;
    _eventSub = _events.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final p = (event['progress'] as num?)?.toDouble() ?? 0.0;
        _progressCtrl.add(p);
      }
    });
  }

  /// Load the Core ML model from [modelDirPath].
  /// Throws on failure — catch and fall back to mock if needed.
  Future<void> loadModel(String modelDirPath) async {
    final ok = await _method.invokeMethod<bool>('loadModel', {
      'modelPath': modelDirPath,
    });
    if (ok != true) throw Exception('loadModel returned false');
  }

  Future<bool> get isModelReady async {
    return await _method.invokeMethod<bool>('isModelReady') ?? false;
  }

  @override
  Future<ImageGenResult> generate(
    String prompt, {
    int width = 512,
    int height = 512,
    int steps = 20,
    String negativePrompt = 'low quality, blurry, distorted, ugly',
    double guidanceScale = 7.5,
    int? seed,
    int frameCount = 1,
  }) async {
    status = ImageGenStatus.generating;
    _progressCtrl.add(0.0);
    final start = DateTime.now();

    try {
      final args = <String, dynamic>{
        'prompt': prompt,
        'negativePrompt': negativePrompt,
        'steps': steps,
        'guidanceScale': guidanceScale,
        'frameCount': frameCount,
        if (seed != null) 'seed': seed,
      };

      final raw = await _method.invokeMethod<Uint8List>('generate', args);
      if (raw == null) throw Exception('No data returned from native');

      status = ImageGenStatus.done;
      _progressCtrl.add(1.0);

      return ImageGenResult(
        imageBytes: raw,
        prompt: prompt,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        width: width,
        height: height,
      );
    } catch (e) {
      status = ImageGenStatus.error;
      rethrow;
    }
  }

  @override
  Future<Uint8List?> editImage({
    required Uint8List imageBytes,
    required String prompt,
    double strength = 0.7,
    int steps = 20,
  }) async {
    status = ImageGenStatus.generating;
    _progressCtrl.add(0.0);
    try {
      final raw = await _method.invokeMethod<Uint8List>('editImage', {
        'prompt': prompt,
        'imageBytes': imageBytes,
        'strength': strength,
        'steps': steps,
        'negativePrompt': 'low quality, blurry, distorted',
      });
      status = ImageGenStatus.done;
      _progressCtrl.add(1.0);
      return raw;
    } catch (e) {
      status = ImageGenStatus.error;
      return null;
    }
  }

  @override
  void cancel() {
    _method.invokeMethod('cancel');
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _progressCtrl.close();
  }
}

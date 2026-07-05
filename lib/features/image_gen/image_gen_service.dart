import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

enum ImageGenStatus { idle, generating, done, error }

class ImageGenResult {
  const ImageGenResult({
    required this.imageBytes,
    required this.prompt,
    required this.durationMs,
    this.width = 512,
    this.height = 512,
  });

  final Uint8List imageBytes;
  final String prompt;
  final int durationMs;
  final int width;
  final int height;
}

abstract class LocalImageGen {
  ImageGenStatus get status;
  Stream<double> get progressStream;

  Future<ImageGenResult> generate(
    String prompt, {
    int width = 512,
    int height = 512,
    int steps = 20,
  });

  /// img2img: edit an existing image given a text instruction.
  /// [strength] 0–1 controls how much the source image is preserved
  /// (0 = no change, 1 = ignore source entirely).
  Future<Uint8List?> editImage({
    required Uint8List imageBytes,
    required String prompt,
    double strength = 0.7,
    int steps = 20,
  });

  void cancel();
  void dispose();
}

/// Mock implementation — generates a gradient PNG in pure Dart (no GPU needed).
/// Replace with Core ML Stable Diffusion integration for real generation.
class LocalImageGenMock implements LocalImageGen {
  final _progressCtrl = StreamController<double>.broadcast();
  bool _cancelled = false;

  @override
  ImageGenStatus status = ImageGenStatus.idle;

  @override
  Stream<double> get progressStream => _progressCtrl.stream;

  @override
  Future<ImageGenResult> generate(
    String prompt, {
    int width = 512,
    int height = 512,
    int steps = 20,
  }) async {
    _cancelled = false;
    status = ImageGenStatus.generating;
    final start = DateTime.now();

    for (var i = 0; i <= steps; i++) {
      if (_cancelled) {
        status = ImageGenStatus.idle;
        throw StateError('Generation cancelled');
      }
      _progressCtrl.add(i / steps);
      await Future.delayed(const Duration(milliseconds: 120));
    }

    final bytes = _renderPng(prompt, width, height);
    status = ImageGenStatus.done;

    return ImageGenResult(
      imageBytes: bytes,
      prompt: prompt,
      durationMs: DateTime.now().difference(start).inMilliseconds,
      width: width,
      height: height,
    );
  }

  // Pure-Dart PNG rendering — no Metal/Canvas/GPU required.
  static Uint8List _renderPng(String prompt, int w, int h) {
    final rng = Random(prompt.hashCode.abs());

    // Deterministic palette from prompt hash
    final r1 = 25 + rng.nextInt(70);
    final g1 = 20 + rng.nextInt(90);
    final b1 = 60 + rng.nextInt(110);
    final r2 = 40 + rng.nextInt(100);
    final g2 = 30 + rng.nextInt(80);
    final b2 = 80 + rng.nextInt(100);

    final image = img.Image(width: w, height: h);

    // Gradient background
    for (int y = 0; y < h; y++) {
      final t = y / h;
      final r = (r1 + (r2 - r1) * t).round().clamp(0, 255);
      final g = (g1 + (g2 - g1) * t).round().clamp(0, 255);
      final b = (b1 + (b2 - b1) * t).round().clamp(0, 255);
      for (int x = 0; x < w; x++) {
        final hBlend = x / w;
        image.setPixelRgb(
          x,
          y,
          (r + hBlend * 30).round().clamp(0, 255),
          (g - hBlend * 10).round().clamp(0, 255),
          (b + hBlend * 20).round().clamp(0, 255),
        );
      }
    }

    // Soft circles (noise pattern)
    for (var i = 0; i < 10; i++) {
      final cx = rng.nextInt(w);
      final cy = rng.nextInt(h);
      final radius = 20 + rng.nextInt(80);
      _drawSoftCircle(image, cx, cy, radius, w, h);
    }

    // Horizontal scan lines for texture
    for (var i = 0; i < 20; i++) {
      final y = rng.nextInt(h);
      for (int x = 0; x < w; x++) {
        final px = image.getPixel(x, y);
        image.setPixelRgb(
          x,
          y,
          (px.r + 8).clamp(0, 255).toInt(),
          (px.g + 8).clamp(0, 255).toInt(),
          (px.b + 8).clamp(0, 255).toInt(),
        );
      }
    }

    // Label text (simple pixel text — prompt truncated)
    _drawLabel(image, '"${_clip(prompt, 38)}"', w, h);

    return Uint8List.fromList(img.encodePng(image));
  }

  static void _drawSoftCircle(
      img.Image im, int cx, int cy, int r, int w, int h) {
    final x0 = (cx - r).clamp(0, w - 1);
    final x1 = (cx + r).clamp(0, w - 1);
    final y0 = (cy - r).clamp(0, h - 1);
    final y1 = (cy + r).clamp(0, h - 1);
    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        final dist = sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy).toDouble());
        if (dist < r) {
          final alpha = ((1 - dist / r) * 0.12).clamp(0.0, 1.0);
          final px = im.getPixel(x, y);
          im.setPixelRgb(
            x,
            y,
            (px.r + 255 * alpha).clamp(0, 255).toInt(),
            (px.g + 255 * alpha).clamp(0, 255).toInt(),
            (px.b + 255 * alpha).clamp(0, 255).toInt(),
          );
        }
      }
    }
  }

  static void _drawLabel(img.Image im, String text, int w, int h) {
    img.drawString(
      im,
      text,
      font: img.arial14,
      x: 14,
      y: h ~/ 2 - 10,
      color: img.ColorRgba8(255, 255, 255, 120),
    );
    img.drawString(
      im,
      '✦ Preview',
      font: img.arial14,
      x: 14,
      y: h ~/ 2 + 14,
      color: img.ColorRgba8(255, 255, 255, 70),
    );
  }

  static String _clip(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

  @override
  @override
  Future<Uint8List?> editImage({
    required Uint8List imageBytes,
    required String prompt,
    double strength = 0.7,
    int steps = 20,
  }) async {
    // Mock: apply a simple color-shift to simulate an edit
    final source = img.decodeImage(imageBytes);
    if (source == null) return null;
    final rng = Random(prompt.hashCode.abs());
    final tintR = rng.nextInt(80) - 40;
    final tintG = rng.nextInt(80) - 40;
    final tintB = rng.nextInt(80) - 40;
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final px = source.getPixel(x, y);
        source.setPixelRgba(
          x,
          y,
          (px.r.toInt() + (tintR * strength).round()).clamp(0, 255),
          (px.g.toInt() + (tintG * strength).round()).clamp(0, 255),
          (px.b.toInt() + (tintB * strength).round()).clamp(0, 255),
          px.a.toInt(),
        );
      }
    }
    return Uint8List.fromList(img.encodePng(source));
  }

  @override
  void cancel() => _cancelled = true;

  @override
  void dispose() {
    _cancelled = true;
    _progressCtrl.close();
  }
}

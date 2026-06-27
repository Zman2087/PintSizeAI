/// Generates a 1024×1024 PintSizeAI app icon and writes all Xcode icon sizes.
/// Run with: dart run scripts/generate_icon.dart
library;

import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart';

void main() async {
  const size = 1024;
  final img = Image(width: size, height: size);

  // Background gradient: deep navy → slightly lighter blue
  for (var y = 0; y < size; y++) {
    final t = y / size;
    final r = (0x0F + (0x1A - 0x0F) * t).round();
    final g = (0x1D + (0x2C - 0x1D) * t).round();
    final b = (0x38 + (0x55 - 0x38) * t).round();
    for (var x = 0; x < size; x++) {
      img.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // Draw rounded-rect clip (iOS uses its own rounding — just fill square)
  // Draw a stylised "P" circuit logo in the centre
  _drawCircuitP(img, size);

  // Save master 1024x1024
  final masterPath = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  await _saveSize(img, '$masterPath/Icon-App-1024x1024@1x.png', 1024);

  // All required Xcode icon sizes
  final sizes = {
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
  };

  for (final entry in sizes.entries) {
    await _saveSize(img, '$masterPath/${entry.key}', entry.value);
    print('  ✓ ${entry.key} (${entry.value}px)');
  }

  print('\nIcon generated! Rebuild the app to see the new icon.');
}

Future<void> _saveSize(Image src, String path, int px) async {
  final resized = copyResize(src, width: px, height: px,
      interpolation: Interpolation.cubic);
  await File(path).writeAsBytes(encodePng(resized));
}

void _drawCircuitP(Image img, int size) {
  final cx = size / 2;
  final cy = size / 2;

  // Glow circle behind the letter
  _fillCircle(img, cx.toInt(), cy.toInt(), (size * 0.38).toInt(),
      ColorRgba8(0x12, 0x47, 0x8A, 60));
  _fillCircle(img, cx.toInt(), cy.toInt(), (size * 0.30).toInt(),
      ColorRgba8(0x16, 0x5B, 0xA8, 40));

  // "P" — thick strokes using filled rectangles
  const strokeW = 72.0;
  const letterH = 480.0;
  const letterW = 320.0;
  final lx = cx - letterW / 2;
  final ty = cy - letterH / 2;

  // Vertical stem
  _fillRect(img, lx.round(), ty.round(),
      (lx + strokeW).round(), (ty + letterH).round(),
      ColorRgba8(0xFF, 0xFF, 0xFF, 255));

  // Top horizontal bar
  _fillRect(img, lx.round(), ty.round(),
      (lx + letterW).round(), (ty + strokeW).round(),
      ColorRgba8(0xFF, 0xFF, 0xFF, 255));

  // Middle horizontal bar
  final midY = ty + letterH * 0.45;
  _fillRect(img, lx.round(), midY.round(),
      (lx + letterW).round(), (midY + strokeW).round(),
      ColorRgba8(0xFF, 0xFF, 0xFF, 255));

  // Right vertical connecting top-to-mid
  _fillRect(img, (lx + letterW - strokeW).round(), ty.round(),
      (lx + letterW).round(), (midY + strokeW).round(),
      ColorRgba8(0xFF, 0xFF, 0xFF, 255));

  // Four circuit dots (accent green)
  final dotColor = ColorRgba8(0x34, 0xD3, 0x99, 255);
  final dotPositions = [
    [lx + strokeW / 2, ty + strokeW / 2],
    [lx + letterW - strokeW / 2, ty + strokeW / 2],
    [lx + letterW - strokeW / 2, midY + strokeW / 2],
    [lx + strokeW / 2, ty + letterH - strokeW / 2],
  ];
  for (final pos in dotPositions) {
    _fillCircle(img, pos[0].round(), pos[1].round(), 22, dotColor);
  }

  // Small accent line (circuit trace) below the P
  final traceY = (ty + letterH + 40).toInt();
  _fillRect(img, (cx - 80).toInt(), traceY,
      (cx + 80).toInt(), traceY + 8,
      ColorRgba8(0x34, 0xD3, 0x99, 160));
}

void _fillRect(Image img, int x0, int y0, int x1, int y1, Color color) {
  for (var y = math.max(0, y0); y < math.min(img.height, y1); y++) {
    for (var x = math.max(0, x0); x < math.min(img.width, x1); x++) {
      _blendPixel(img, x, y, color);
    }
  }
}

void _fillCircle(Image img, int cx, int cy, int r, Color color) {
  for (var y = cy - r; y <= cy + r; y++) {
    for (var x = cx - r; x <= cx + r; x++) {
      final dx = x - cx;
      final dy = y - cy;
      if (dx * dx + dy * dy <= r * r) {
        if (x >= 0 && x < img.width && y >= 0 && y < img.height) {
          _blendPixel(img, x, y, color);
        }
      }
    }
  }
}

void _blendPixel(Image img, int x, int y, Color src) {
  final dst = img.getPixel(x, y);
  final a = src.a / 255;
  final r = (src.r * a + dst.r * (1 - a)).round().clamp(0, 255);
  final g = (src.g * a + dst.g * (1 - a)).round().clamp(0, 255);
  final b = (src.b * a + dst.b * (1 - a)).round().clamp(0, 255);
  img.setPixelRgba(x, y, r, g, b, 255);
}

// ignore_for_file: avoid_print  (build-time script, not app code)
/// Generates a 1024×1024 PintSizeAI app icon featuring a small, friendly
/// stylized brain — a play on the name "PintSize AI" (a pint-size brain).
/// Design: dark navy radial gradient bg, soft glow halo, and a bold two-
/// hemisphere brain glowing cyan→green with curved gyri folds. No text, so
/// the brain reads clearly even at 40×40 px.
/// Run with: dart run scripts/generate_icon.dart
library;

import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart';

// Palette
const _cyanR = 0x7D, _cyanG = 0xD3, _cyanB = 0xFC; // #7DD3FC soft cyan/teal
const _greenR = 0x22, _greenG = 0xC5, _greenB = 0x5E; // #22C55E electric green

void main() async {
  const size = 1024;
  final img = Image(width: size, height: size);

  _drawBackground(img, size);
  _drawGlowHalo(img, size);
  _drawBrain(img, size);

  const masterPath = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  await _saveSize(img, '$masterPath/Icon-App-1024x1024@1x.png', 1024);
  print('  ✓ Icon-App-1024x1024@1x.png (1024px)');

  final sizes = <String, int>{
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

// ── Background ───────────────────────────────────────────────────────────────
// Radial gradient: #131C2E at centre → #060B14 at corners (dark vignette).

void _drawBackground(Image img, int size) {
  final cx = size / 2.0;
  final cy = size / 2.0;
  final maxDist = math.sqrt(cx * cx + cy * cy);

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final t = (math.sqrt(dx * dx + dy * dy) / maxDist).clamp(0.0, 1.0);

      // #131C2E → #060B14
      final r = (0x13 + (0x06 - 0x13) * t).round();
      final g = (0x1C + (0x0B - 0x1C) * t).round();
      final b = (0x2E + (0x14 - 0x2E) * t).round();
      img.setPixelRgba(x, y, r, g, b, 255);
    }
  }
}

// ── Glow halo ────────────────────────────────────────────────────────────────
// Soft low-opacity concentric discs behind the brain (cyan), giving an
// "AI brain" glow that fades outward.

void _drawGlowHalo(Image img, int size) {
  final cx = (size / 2).round();
  final cy = (size / 2).round();
  // Concentric discs from large/faint to small/brighter.
  final halos = <List<num>>[
    [size * 0.46, 4],
    [size * 0.40, 7],
    [size * 0.34, 11],
    [size * 0.28, 16],
    [size * 0.23, 22],
  ];
  for (final h in halos) {
    _fillCircle(img, cx, cy, h[0].round(),
        ColorRgba8(_cyanR, _cyanG, _cyanB, h[1].toInt()));
  }
}

// ── Brain ────────────────────────────────────────────────────────────────────
// A bold, friendly brain: two rounded hemispheres separated by a central
// fissure, with a few curved gyri grooves and a soft outer glow. The fill is a
// horizontal cyan→green gradient so it reads as an "AI brain".

void _drawBrain(Image img, int size) {
  final cx = size / 2.0;
  final cy = size / 2.0;

  // Brain occupies ~57% of canvas width.
  final brainW = size * 0.57;
  final brainH = size * 0.50;
  final hemiRx = brainW / 4.0; // each hemisphere half-width
  final hemiRy = brainH / 2.0; // hemisphere half-height
  final offset = hemiRx * 0.92; // horizontal offset of each hemisphere centre

  final leftCx = cx - offset;
  final rightCx = cx + offset;

  // Pixel test: inside the brain silhouette (union of two ellipses)?
  bool insideBrain(double x, double y) {
    return _inEllipse(x, y, leftCx, cy, hemiRx, hemiRy) ||
        _inEllipse(x, y, rightCx, cy, hemiRx, hemiRy);
  }

  // 1. Soft outer glow: dilated silhouette at low opacity, a couple of bands.
  _drawBrainGlow(img, size, insideBrain, leftCx, rightCx, cy, hemiRx, hemiRy);

  // 2. Solid brain body with cyan→green horizontal gradient + top highlight.
  final minX = (cx - brainW / 2 - 4).floor();
  final maxX = (cx + brainW / 2 + 4).ceil();
  final minY = (cy - hemiRy - 4).floor();
  final maxY = (cy + hemiRy + 4).ceil();

  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      if (x < 0 || x >= size || y < 0 || y >= size) continue;
      if (!insideBrain(x.toDouble(), y.toDouble())) continue;

      // Horizontal gradient: cyan on the left → green on the right.
      final gx = ((x - (cx - brainW / 2)) / brainW).clamp(0.0, 1.0);
      var r = (_cyanR + (_greenR - _cyanR) * gx).round();
      var g = (_cyanG + (_greenG - _cyanG) * gx).round();
      var b = (_cyanB + (_greenB - _cyanB) * gx).round();

      // Gentle top-light shading so the brain looks rounded.
      final vy = ((y - (cy - hemiRy)) / (2 * hemiRy)).clamp(0.0, 1.0);
      final shade = (1.0 - vy * 0.30);
      r = (r * shade).round().clamp(0, 255);
      g = (g * shade).round().clamp(0, 255);
      b = (b * shade).round().clamp(0, 255);

      img.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // 3. Central fissure dividing the two hemispheres (darker groove).
  _drawVerticalFissure(img, cx, cy, hemiRy);

  // 4. Curved gyri grooves on each hemisphere, drawn as darkened strokes.
  _drawGyri(img, leftCx, rightCx, cy, hemiRx, hemiRy, insideBrain);

  // 5. Bright cyan→green highlight ridges that sit just above some grooves to
  //    give the folds a glowing, lit edge.
  _drawGyriHighlights(img, leftCx, rightCx, cy, hemiRx, hemiRy, insideBrain);
}

/// Soft outer glow: stroke the brain outline outward with fading bands.
void _drawBrainGlow(
  Image img,
  int size,
  bool Function(double, double) insideBrain,
  double leftCx,
  double rightCx,
  double cy,
  double hemiRx,
  double hemiRy,
) {
  // Draw a few enlarged silhouettes with low alpha behind the body.
  final bands = <List<num>>[
    [26.0, 8],
    [16.0, 14],
    [8.0, 26],
  ];
  final minX = (math.min(leftCx, rightCx) - hemiRx - 40).floor();
  final maxX = (math.max(leftCx, rightCx) + hemiRx + 40).ceil();
  final minY = (cy - hemiRy - 40).floor();
  final maxY = (cy + hemiRy + 40).ceil();

  for (final band in bands) {
    final grow = band[0].toDouble();
    final alpha = band[1].toInt();
    final rx = hemiRx + grow;
    final ry = hemiRy + grow;
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        if (x < 0 || x >= size || y < 0 || y >= size) continue;
        final xf = x.toDouble(), yf = y.toDouble();
        final inGrown = _inEllipse(xf, yf, leftCx, cy, rx, ry) ||
            _inEllipse(xf, yf, rightCx, cy, rx, ry);
        if (inGrown && !insideBrain(xf, yf)) {
          // Glow tint: blend cyan/green by horizontal position.
          final mid = (leftCx + rightCx) / 2;
          final isRight = xf > mid;
          _blendPixel(
              img,
              x,
              y,
              ColorRgba8(isRight ? _greenR : _cyanR, isRight ? _greenG : _cyanG,
                  isRight ? _greenB : _cyanB, alpha));
        }
      }
    }
  }
}

/// Dark central fissure: a slightly wavy vertical groove down the middle.
void _drawVerticalFissure(Image img, double cx, double cy, double hemiRy) {
  final steps = (hemiRy * 2).round();
  for (var i = 0; i <= steps; i++) {
    final t = i / steps; // 0..1 top→bottom
    final y = cy - hemiRy + t * 2 * hemiRy;
    // Gentle S-curve so the fissure isn't a dead-straight line.
    final wob = math.sin(t * math.pi) * 6.0;
    final x = cx + wob;
    // Taper width at the very top/bottom so it blends into the silhouette.
    final taper = math.sin(t * math.pi).clamp(0.0, 1.0);
    final w = 5.0 + 4.0 * taper;
    _stampGroove(img, x, y, w);
  }
}

/// Curved gyri grooves: a handful of arcs per hemisphere, darkened.
void _drawGyri(
  Image img,
  double leftCx,
  double rightCx,
  double cy,
  double hemiRx,
  double hemiRy,
  bool Function(double, double) insideBrain,
) {
  // Each groove: vertical offset factor, amplitude factor, phase.
  final grooves = <List<double>>[
    [-0.46, 0.42, 0.0],
    [-0.14, 0.50, 1.0],
    [0.18, 0.46, 2.0],
    [0.48, 0.34, 0.5],
  ];

  for (final hemi in [leftCx, rightCx]) {
    final mirror = hemi == leftCx ? -1.0 : 1.0;
    for (final gdef in grooves) {
      final yBase = cy + gdef[0] * hemiRy;
      final amp = gdef[1] * hemiRy * 0.30;
      final phase = gdef[2];
      // Sweep the groove horizontally across most of the hemisphere width.
      final x0 = hemi - hemiRx * 0.78;
      final x1 = hemi + hemiRx * 0.78;
      final steps = ((x1 - x0)).round();
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = x0 + t * (x1 - x0);
        final y = yBase + math.sin(t * math.pi * 1.6 + phase) * amp * mirror;
        if (!insideBrain(x, y)) continue;
        _stampGroove(img, x, y, 5.0);
      }
    }
  }
}

/// Bright lit ridges along some folds (alternating cyan / green) to make the
/// brain feel like glowing AI circuitry.
void _drawGyriHighlights(
  Image img,
  double leftCx,
  double rightCx,
  double cy,
  double hemiRx,
  double hemiRy,
  bool Function(double, double) insideBrain,
) {
  final ridges = <List<double>>[
    [-0.30, 0.46, 0.5],
    [0.02, 0.50, 1.6],
    [0.34, 0.40, 2.4],
  ];

  var idx = 0;
  for (final hemi in [leftCx, rightCx]) {
    final mirror = hemi == leftCx ? -1.0 : 1.0;
    for (final rdef in ridges) {
      // Alternate the accent colour between cyan and green.
      final useGreen = (idx % 2) == 1;
      final cr = useGreen ? _greenR : _cyanR;
      final cg = useGreen ? _greenG : _cyanG;
      final cb = useGreen ? _greenB : _cyanB;
      idx++;

      final yBase = cy + rdef[0] * hemiRy;
      final amp = rdef[1] * hemiRy * 0.28;
      final phase = rdef[2];
      final x0 = hemi - hemiRx * 0.68;
      final x1 = hemi + hemiRx * 0.68;
      final steps = ((x1 - x0)).round();
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = x0 + t * (x1 - x0);
        final y = yBase + math.sin(t * math.pi * 1.5 + phase) * amp * mirror;
        if (!insideBrain(x, y)) continue;
        // Soft halo then bright core for a glowing line.
        _stampDot(img, x, y, 4.0, ColorRgba8(cr, cg, cb, 40));
        _stampDot(
            img,
            x,
            y,
            2.2,
            ColorRgba8((cr + 0x40).clamp(0, 255), (cg + 0x40).clamp(0, 255),
                (cb + 0x40).clamp(0, 255), 210));
      }
    }
  }
}

/// Darken a small soft disc to carve a groove into the brain body.
void _stampGroove(Image img, double cx, double cy, double radius) {
  final r = radius.ceil();
  final icx = cx.round();
  final icy = cy.round();
  for (var y = icy - r; y <= icy + r; y++) {
    for (var x = icx - r; x <= icx + r; x++) {
      if (x < 0 || x >= img.width || y < 0 || y >= img.height) continue;
      final dx = x - cx;
      final dy = y - cy;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d > radius) continue;
      // Soft falloff: darkest at centre.
      final f = (1.0 - d / radius);
      final alpha = (140 * f).round();
      if (alpha > 0) {
        // Dark navy groove tinted toward the bg.
        _blendPixel(img, x, y, ColorRgba8(0x0A, 0x16, 0x24, alpha));
      }
    }
  }
}

/// Soft additive-ish dot used for the lit ridges.
void _stampDot(
    Image img, double cx, double cy, double radius, ColorRgba8 color) {
  final r = radius.ceil();
  final icx = cx.round();
  final icy = cy.round();
  for (var y = icy - r; y <= icy + r; y++) {
    for (var x = icx - r; x <= icx + r; x++) {
      if (x < 0 || x >= img.width || y < 0 || y >= img.height) continue;
      final dx = x - cx;
      final dy = y - cy;
      if (dx * dx + dy * dy <= radius * radius) {
        _blendPixel(img, x, y, color);
      }
    }
  }
}

bool _inEllipse(
    double x, double y, double cx, double cy, double rx, double ry) {
  final nx = (x - cx) / rx;
  final ny = (y - cy) / ry;
  return nx * nx + ny * ny <= 1.0;
}

// ── Primitives ───────────────────────────────────────────────────────────────

Future<void> _saveSize(Image src, String path, int px) async {
  final resized = copyResize(src,
      width: px, height: px, interpolation: Interpolation.cubic);
  await File(path).writeAsBytes(encodePng(resized));
}

/// Fill a disc of radius r centred on (cx, cy).
void _fillCircle(Image img, int cx, int cy, int r, Color color) {
  for (var y = cy - r; y <= cy + r; y++) {
    for (var x = cx - r; x <= cx + r; x++) {
      if (x < 0 || x >= img.width || y < 0 || y >= img.height) continue;
      final dx = x - cx;
      final dy = y - cy;
      if (dx * dx + dy * dy <= r * r) {
        _blendPixel(img, x, y, color);
      }
    }
  }
}

/// Porter-Duff "src over dst" alpha blend (both fully opaque result).
void _blendPixel(Image img, int x, int y, Color src) {
  final dst = img.getPixel(x, y);
  final a = src.a / 255.0;
  final r = (src.r * a + dst.r * (1 - a)).round().clamp(0, 255);
  final g = (src.g * a + dst.g * (1 - a)).round().clamp(0, 255);
  final b = (src.b * a + dst.b * (1 - a)).round().clamp(0, 255);
  img.setPixelRgba(x, y, r, g, b, 255);
}

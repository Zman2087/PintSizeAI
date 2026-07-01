import 'package:flutter/material.dart';

/// PintSize AI colour tokens — adaptive light/dark.
///
/// Theme-able surface/border/text tokens resolve at runtime based on
/// [brightness], which is set once per build from the iOS system appearance
/// (see `main.dart`). Accent, model and absolute colours are the same in both
/// themes and stay `const` so their many `const` widget usages keep compiling.
///
/// Dark values mirror ChatGPT's dark theme; light values mirror its light theme.
abstract final class AppColors {
  /// Current appearance. Set from MediaQuery in the app root each build.
  static Brightness brightness = Brightness.dark;
  static bool get _d => brightness == Brightness.dark;

  // ── Surfaces ──
  static Color get surfaceBase =>
      _d ? const Color(0xFF212121) : const Color(0xFFFFFFFF);
  static Color get surfaceSidebar =>
      _d ? const Color(0xFF171717) : const Color(0xFFF9F9F9);
  static Color get surfaceOverlay =>
      _d ? const Color(0xFF2F2F2F) : const Color(0xFFF4F4F4);
  static Color get surfaceActive =>
      _d ? const Color(0xFF3A3A3A) : const Color(0xFFECECEC);

  // ── Borders ──
  static Color get borderDefault =>
      _d ? const Color(0xFF3A3A3A) : const Color(0xFFE3E3E3);
  static Color get borderSubtle =>
      _d ? const Color(0xFF2A2A2A) : const Color(0xFFEDEDED);

  // ── Text hierarchy ──
  static Color get textPrimary =>
      _d ? const Color(0xFFECECEC) : const Color(0xFF0D0D0D);
  static Color get textDefault => textPrimary;
  static Color get textMuted =>
      _d ? const Color(0xFF8E8EA0) : const Color(0xFF6B6B7B);
  static Color get textDim =>
      _d ? const Color(0xFF585858) : const Color(0xFF9B9BA6);

  // ── Accent (same in both themes; used sparingly) ──
  static const Color accentGreen = Color(0xFF19C37D);

  // ── Model icon colours (same in both themes) ──
  static const Color modelWhite = Color(0xFFFFFFFF);
  static const Color modelPurple = Color(0xFF7C3AED);
  static const Color modelBlue = Color(0xFF2563EB);
  static const Color modelGreen = Color(0xFF16A34A);
  static const Color modelSurface = Color(0xFF2F2F2F);

  // ── Absolute ──
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color transparent = Color(0x00000000);
}

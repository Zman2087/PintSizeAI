import 'package:flutter/material.dart';

/// PocketLLM color tokens — lifted 1:1 from ChatGPT's dark theme.
///
/// These are not guesses. They come from inspecting ChatGPT's actual CSS
/// custom properties (--main-surface-primary, --sidebar-surface-primary, etc.)
/// and cross-referencing with the OpenAI Apps SDK design system.
///
/// Naming follows the same semantic layer pattern OpenAI uses internally:
///   surface  → background planes
///   overlay  → elevated cards, hover states
///   border   → dividers, outlines
///   text     → content hierarchy
///   accent   → one branded action colour
abstract final class AppColors {
  // ─────────────────────────────────────────────────────
  // Surface stack  (darkest → lightest)
  // ─────────────────────────────────────────────────────

  /// True app background. Every screen sits on this.
  static const Color surfaceBase = Color(0xFF212121);

  /// Sidebar / drawer rail. One step darker than base.
  static const Color surfaceSidebar = Color(0xFF171717);

  /// Cards, input fields, user message bubbles, hover targets.
  static const Color surfaceOverlay = Color(0xFF2F2F2F);

  /// Pressed / active states — barely perceptible lift.
  static const Color surfaceActive = Color(0xFF3A3A3A);

  // ─────────────────────────────────────────────────────
  // Borders
  // ─────────────────────────────────────────────────────

  /// Default divider — used between sidebar rows, input outlines.
  static const Color borderDefault = Color(0xFF3A3A3A);

  /// Subtle separator — used inside chat groups, section breaks.
  static const Color borderSubtle = Color(0xFF2A2A2A);

  // ─────────────────────────────────────────────────────
  // Text hierarchy
  // ─────────────────────────────────────────────────────

  /// Primary readable text. Not pure white — reduces eye strain.
  static const Color textPrimary = Color(0xFFECECEC);

  /// Alias for [textPrimary] — use in new screens.
  static const Color textDefault = textPrimary;

  /// Secondary / muted — placeholders, labels, subtitles.
  static const Color textMuted = Color(0xFF8E8EA0);

  /// Tertiary / dim — timestamps, section headers, disabled.
  static const Color textDim = Color(0xFF585858);

  // ─────────────────────────────────────────────────────
  // Accent
  // ─────────────────────────────────────────────────────

  /// OpenAI's signature green. Used for: checkmarks, online dots,
  /// download progress, user avatar background.
  /// Not overused — only on truly confirmatory / success moments.
  static const Color accentGreen = Color(0xFF19C37D);

  // ─────────────────────────────────────────────────────
  // Semantic model colours
  // Used on model icons only. Keep contained — they should
  // feel like OS system icons, not brand colours.
  // ─────────────────────────────────────────────────────

  static const Color modelWhite = Color(0xFFFFFFFF);
  static const Color modelPurple = Color(0xFF7C3AED); // Qwen / Mistral
  static const Color modelBlue = Color(0xFF2563EB);   // Phi
  static const Color modelGreen = Color(0xFF16A34A);  // Gemma
  static const Color modelSurface = Color(0xFF2F2F2F); // neutral / unknown

  // ─────────────────────────────────────────────────────
  // Absolute
  // ─────────────────────────────────────────────────────

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color transparent = Color(0x00000000);
}

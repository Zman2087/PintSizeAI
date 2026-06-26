import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// PocketLLM typography system.
///
/// ChatGPT uses Söhne (a licensed Futura derivative) which isn't available
/// on Google Fonts. Inter is the closest publicly available match —
/// same geometric-humanist structure, similar x-height and optical weight.
///
/// The scale is derived from ChatGPT's actual rendered font sizes:
///   - Nav title:   15px / 600
///   - Body prose:  13px / 400, line-height 1.65
///   - Labels:      11px / 500, tracked 0.04em
///   - Caption/dim: 11px / 400
///   - Code:        SFMono / ui-monospace, 12px
///
/// Flutter TextStyle uses logical pixels which map 1:1 on most devices
/// at 1x scale. These match CSS px values at 1.0 device pixel ratio.
abstract final class AppTypography {
  // ─────────────────────────────────────────────────────
  // Base
  // ─────────────────────────────────────────────────────

  /// Nav bar title — model name, screen name.
  static TextStyle get navTitle => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  /// Section title inside modal sheets (e.g. "Choose model").
  static TextStyle get sheetTitle => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  // ─────────────────────────────────────────────────────
  // Body — main chat prose
  // ─────────────────────────────────────────────────────

  /// Assistant and user message body text.
  /// line-height: 1.65 mirrors ChatGPT's comfortable prose rhythm.
  static TextStyle get messageBody => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.65,
      );

  /// Sidebar history row — conversation title.
  static TextStyle get sidebarTitle => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.4,
      );

  /// Sidebar history row — model + timestamp subtitle.
  static TextStyle get sidebarSubtitle => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.textDim,
        height: 1.4,
      );

  // ─────────────────────────────────────────────────────
  // Model list
  // ─────────────────────────────────────────────────────

  /// Model name in picker row.
  static TextStyle get modelName => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.4,
      );

  /// Model description / size / speed in picker row.
  static TextStyle get modelDesc => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
        height: 1.4,
      );

  // ─────────────────────────────────────────────────────
  // Labels and metadata
  // ─────────────────────────────────────────────────────

  /// ALL-CAPS section headers (e.g. "ON DEVICE", "MORE MODELS").
  static TextStyle get sectionLabel => GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: AppColors.textDim,
        height: 1.3,
        letterSpacing: 0.6, // 0.06em at 10px
      );

  /// Chip and badge text.
  static TextStyle get badge => GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: AppColors.textMuted,
        height: 1.2,
      );

  /// Input placeholder.
  static TextStyle get placeholder => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textDim,
        height: 1.4,
      );

  /// Logo / app name wordmark in sidebar.
  static TextStyle get wordmark => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.2,
      );

  /// Username in sidebar footer.
  static TextStyle get username => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  /// "All local · no cloud" and other secondary footer text.
  static TextStyle get userMeta => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.textDim,
        height: 1.3,
      );

  // ─────────────────────────────────────────────────────
  // Code — inline in chat responses
  // ─────────────────────────────────────────────────────

  /// Inline code spans. Mirrors ChatGPT's SFMono fallback chain.
  static TextStyle get inlineCode => const TextStyle(
        fontFamily: 'SFMono-Regular',
        fontFamilyFallback: [
          'ui-monospace',
          'Menlo',
          'Monaco',
          'Cascadia Code',
          'monospace',
        ],
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: Color(0xFFC9D1D9), // GitHub-style code grey on dark
        height: 1.5,
      );
}

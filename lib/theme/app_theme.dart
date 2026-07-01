import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Builds the single ThemeData used by MaterialApp.
///
/// Design goal: every widget that ships with Flutter should look right
/// at home in ChatGPT's dark theme *without* any per-widget overrides
/// at the call site. Put the work here, keep the rest of the codebase clean.
///
/// Usage:
///   MaterialApp(
///     theme: AppTheme.dark,
///     ...
///   )
abstract final class AppTheme {
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    // Resolve AppColors tokens for this brightness while we build.
    final prev = AppColors.brightness;
    AppColors.brightness = brightness;
    final theme = _buildInner(brightness);
    AppColors.brightness = prev;
    return theme;
  }

  static ThemeData _buildInner(Brightness brightness) {
    // Base colour scheme — Flutter will derive many widget defaults from this.
    final colorScheme = ColorScheme(
      brightness: brightness,

      // Primary — the accent. Used on FABs, active states, progress.
      primary: AppColors.accentGreen,
      onPrimary: AppColors.white,
      primaryContainer: Color(0xFF0D3B28), // dark green tint for containers
      onPrimaryContainer: AppColors.accentGreen,

      // Secondary — surface overlay. Used on chips, toggles.
      secondary: AppColors.surfaceOverlay,
      onSecondary: AppColors.textPrimary,
      secondaryContainer: AppColors.surfaceActive,
      onSecondaryContainer: AppColors.textPrimary,

      // Tertiary — muted accent. Not used aggressively.
      tertiary: AppColors.textMuted,
      onTertiary: AppColors.surfaceBase,
      tertiaryContainer: AppColors.surfaceOverlay,
      onTertiaryContainer: AppColors.textMuted,

      // Surfaces
      surface: AppColors.surfaceBase,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceOverlay,
      surfaceContainerHigh: AppColors.surfaceActive,
      surfaceContainer: AppColors.surfaceOverlay,
      surfaceContainerLow: AppColors.surfaceSidebar,
      surfaceContainerLowest: AppColors.surfaceSidebar,

      // Error
      error: Color(0xFFEF4444),
      onError: AppColors.white,
      errorContainer: Color(0xFF3B0F0F),
      onErrorContainer: Color(0xFFFCA5A5),

      // Outline
      outline: AppColors.borderDefault,
      outlineVariant: AppColors.borderSubtle,

      // Inverse — used on SnackBar, tooltip, etc.
      inverseSurface: AppColors.textPrimary,
      onInverseSurface: AppColors.surfaceSidebar,
      inversePrimary: AppColors.accentGreen,

      // Shadow and scrim
      shadow: AppColors.black,
      scrim: Color(0xCC000000),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      scaffoldBackgroundColor: AppColors.surfaceBase,
      // ── Typography base ──────────────────────────────────────────────────
      // Set Inter as the default for all Material text roles.
      // Individual widgets that need specific sizing use AppTypography directly.
      textTheme: GoogleFonts.interTextTheme(
        (brightness == Brightness.dark
                ? ThemeData.dark()
                : ThemeData.light())
            .textTheme,
      ).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
    );

    return base.copyWith(
      // ── System chrome ────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceBase,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: AppColors.transparent,
        titleTextStyle: AppTypography.navTitle,
        iconTheme: IconThemeData(
          color: AppColors.textMuted,
          size: 20,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: AppColors.transparent,
          statusBarIconBrightness:
              brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: brightness,
        ),
      ),

      // ── Bottom navigation / drawer ────────────────────────────────────────
      // ChatGPT uses a slide-in drawer, not a BottomNavigationBar.
      // These tokens cover the drawer surface.
      drawerTheme: DrawerThemeData(
        backgroundColor: AppColors.surfaceSidebar,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),

      // ── Divider ──────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: AppColors.borderSubtle,
        thickness: 1,
        space: 0, // callers control vertical spacing explicitly
      ),

      // ── Text input ───────────────────────────────────────────────────────
      // Used for the chat input box and the model search field.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceOverlay,
        hintStyle: AppTypography.placeholder,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AppColors.borderDefault,
            width: 1,
          ),
        ),
      ),

      // ── Buttons ──────────────────────────────────────────────────────────
      // The send button is a custom widget. These cover any system buttons.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.surfaceSidebar,
          textStyle: AppTypography.modelName,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textMuted,
          textStyle: AppTypography.sidebarTitle,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textMuted,
          highlightColor: AppColors.surfaceOverlay,
          hoverColor: AppColors.surfaceOverlay,
          splashFactory: NoSplash.splashFactory, // no ripple — matches native feel
          minimumSize: const Size(32, 32),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // ── List tiles ───────────────────────────────────────────────────────
      // Used for sidebar history rows and model picker rows.
      listTileTheme: ListTileThemeData(
        tileColor: AppColors.transparent,
        selectedTileColor: AppColors.surfaceOverlay,
        iconColor: AppColors.textMuted,
        titleTextStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 11,
          color: AppColors.textDim,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        minLeadingWidth: 0,
        horizontalTitleGap: 10,
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),

      // ── Bottom sheet ─────────────────────────────────────────────────────
      // The model picker slides up as a sheet.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surfaceBase,
        surfaceTintColor: AppColors.transparent,
        modalBackgroundColor: AppColors.surfaceBase,
        dragHandleColor: AppColors.borderDefault,
        dragHandleSize: Size(32, 4),
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // ── Popup / context menu ─────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceOverlay,
        surfaceTintColor: AppColors.transparent,
        elevation: 4,
        shadowColor: Color(0x66000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        textStyle: TextStyle(
          fontSize: 13,
          color: AppColors.textPrimary,
        ),
      ),

      // ── Checkbox / Switch ────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.white;
          return AppColors.textDim;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.accentGreen;
          return AppColors.surfaceActive;
        }),
        trackOutlineColor: WidgetStateProperty.all(AppColors.transparent),
      ),

      // ── Circular progress ────────────────────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.accentGreen,
        linearTrackColor: AppColors.surfaceOverlay,
        circularTrackColor: AppColors.surfaceOverlay,
      ),

      // ── Tooltip ──────────────────────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceActive,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderDefault),
        ),
        textStyle: TextStyle(
          fontSize: 11,
          color: AppColors.textPrimary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      // ── Snack bar ────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceActive,
        contentTextStyle: AppTypography.messageBody,
        actionTextColor: AppColors.accentGreen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      // ── Scroll behaviour ─────────────────────────────────────────────────
      // Stretch overscroll matches iOS native feel.
      scrollbarTheme: const ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(Color(0xFF3A3A3A)),
        radius: Radius.circular(4),
        thickness: WidgetStatePropertyAll(4),
        interactive: true,
      ),
    );
  }
}

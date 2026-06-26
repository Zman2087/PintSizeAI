import 'package:flutter/material.dart';

/// PocketLLM spacing and geometry tokens.
///
/// Measured from ChatGPT's mobile app at 390pt viewport (iPhone 14 Pro).
/// All values are logical pixels — Flutter maps them correctly on both
/// iOS (pt) and Android (dp) at their respective device pixel ratios.
abstract final class AppSpacing {
  // ─────────────────────────────────────────────────────
  // Spacing scale
  // ─────────────────────────────────────────────────────

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;

  // ─────────────────────────────────────────────────────
  // Component-specific
  // ─────────────────────────────────────────────────────

  /// Horizontal padding inside the sidebar rail.
  static const double sidebarH = 12.0;

  /// Horizontal padding on main screens (nav, messages, input).
  static const double screenH = 14.0;

  /// Vertical padding for each chat message group.
  static const double messageGroupV = 10.0;

  /// Gap between assistant icon and message text.
  static const double assistantIconGap = 10.0;

  /// Vertical rhythm inside the input box.
  static const double inputV = 12.0;

  /// Bottom safe-area padding added below the input box.
  static const double inputBottomPad = 20.0;
}

/// PocketLLM border radius tokens.
abstract final class AppRadius {
  // ─────────────────────────────────────────────────────
  // Named radii
  // ─────────────────────────────────────────────────────

  /// Pill — used on chips, badges, on-device indicator.
  static const BorderRadius pill = BorderRadius.all(Radius.circular(20));

  /// Large card — sidebar rows (when highlighted), model cards.
  static const BorderRadius card = BorderRadius.all(Radius.circular(10));

  /// Medium — icon containers (model icon, assistant icon, logo mark).
  static const BorderRadius icon = BorderRadius.all(Radius.circular(8));

  /// Input box — matches ChatGPT's 16px rounded input.
  static const BorderRadius input = BorderRadius.all(Radius.circular(16));

  /// Send / stop button — small square with rounded corners.
  static const BorderRadius button = BorderRadius.all(Radius.circular(8));

  /// User message bubble — 18px with flattened bottom-right corner.
  /// This is the single detail that makes it feel native, not generic.
  static const BorderRadius userBubble = BorderRadius.only(
    topLeft: Radius.circular(18),
    topRight: Radius.circular(18),
    bottomLeft: Radius.circular(18),
    bottomRight: Radius.circular(4), // flattened tail
  );

  /// Assistant content area — no bubble, flows from the icon.
  /// No border radius applied — text runs edge to edge.
  static const BorderRadius none = BorderRadius.zero;
}

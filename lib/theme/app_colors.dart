import 'package:flutter/material.dart';

/// Core palette. Named after water/ocean vocabulary so choices stay
/// grounded in the product — a water delivery & refill platform —
/// rather than a generic Material blue.
class AppColors {
  AppColors._();

  // --- Brand ---
  static const Color primary = Color(0xFF0A5C8A); // deep marine
  static const Color primaryDark = Color(0xFF073B57); // abyss
  static const Color primaryLight = Color(0xFF3E85AC);
  static const Color accent = Color(0xFF2EC4C6); // aqua — the "water" pop

  /// Hero gradient — reserved for one deliberate moment per screen
  /// (rider home header, login background), never on every card.
  static const List<Color> heroGradient = [primaryDark, primary, accent];

  // --- Surfaces ---
  static const Color background = Color(0xFFEEF3F7); // mist
  static const Color surface = Color(0xFFF5F9FB); // frost — cards sit here
  static const Color surfaceRaised =
      Colors.white; // top-most surfaces (sheets, dialogs)

  // --- Text ---
  static const Color textPrimary = Color(0xFF14212B); // ink
  static const Color textSecondary = Color(0xFF5C7183);
  static const Color textOnPrimary = Colors.white;
  static const Color textDisabled = Color(0xFFA7B4BF);

  // --- Status / delivery states ---
  static const Color success = Color(0xFF1E9E6D); // delivered
  static const Color warning = Color(0xFFE8A33D); // pending / in transit
  static const Color error = Color(0xFFD64545); // failed / cancelled
  static const Color info = Color(0xFF2E86C1); // assigned

  // --- Structure ---
  static const Color border = Color(0xFFDCE6ED);
  static const Color divider = Color(0xFFE3EAF0);

  /// Tinted shadow — used instead of flat black/grey shadows so
  /// elevation reads as "lifted," not just "boxed."
  static Color shadow = primaryDark.withValues(alpha: 0.12);
}

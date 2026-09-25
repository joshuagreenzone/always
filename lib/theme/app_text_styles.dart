import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Single family (Plus Jakarta Sans, bundled as a local asset — see
/// pubspec.yaml) — weight and size carry the hierarchy instead of
/// mixing typefaces.
///
/// Every style here is `const` on purpose: this file is used all over
/// the app inside `const Text(...)` calls, and switching to a
/// dynamically-loaded font (e.g. the google_fonts package) breaks
/// every one of those call sites, since a non-const style can't be
/// used inside a const widget.
class AppTextStyles {
  AppTextStyles._();

  static const String _family = 'Plus Jakarta Sans';

  // --- Display / headline scale ---
  static const TextStyle displayLarge = TextStyle(
    fontFamily: _family,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: _family,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.25,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _family,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    height: 1.3,
  );

  // --- Body ---
  static const TextStyle body = TextStyle(
    fontFamily: _family,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.45,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontFamily: _family,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.45,
  );

  // --- Labels / UI chrome ---
  static const TextStyle label = TextStyle(
    fontFamily: _family,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.1,
  );

  static const TextStyle button = TextStyle(
    fontFamily: _family,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textOnPrimary,
  );

  static const TextStyle statusChip = TextStyle(
    fontFamily: _family,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textOnPrimary,
    letterSpacing: 0.2,
  );

  static const TextStyle amount = TextStyle(
    fontFamily: _family,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.1,
  );

  // --- Aliases kept for compatibility with existing screens ---
  static const TextStyle screenTitle = headline;
  static const TextStyle sectionTitle = title;
  static const TextStyle dashboardTitle = title;
  static const TextStyle dashboardDescription = bodySecondary;
}

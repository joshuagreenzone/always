import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_sizes.dart';
import 'app_text_styles.dart';

class AppTheme {
  AppTheme._();

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: 'Plus Jakarta Sans',
    scaffoldBackgroundColor: AppColors.background,

    // Built manually rather than ColorScheme.fromSeed: fromSeed derives
    // its own tonal palette from one seed and quietly overrides the
    // deliberate hex values above.
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.textOnPrimary,
      secondary: AppColors.accent,
      onSecondary: AppColors.textPrimary,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
      onError: AppColors.textOnPrimary,
      outline: AppColors.border,
    ),

    textTheme: TextTheme(
      displayLarge: AppTextStyles.displayLarge,
      headlineMedium: AppTextStyles.headline,
      titleLarge: AppTextStyles.title,
      titleMedium: AppTextStyles.subtitle,
      bodyLarge: AppTextStyles.body,
      bodyMedium: AppTextStyles.bodySecondary,
      labelLarge: AppTextStyles.button,
    ),

    appBarTheme: AppBarTheme(
      centerTitle:
          false, // left-aligned reads as more modern/functional than centered
      elevation: 0,
      backgroundColor: AppColors.primaryDark,
      foregroundColor: AppColors.textOnPrimary,
      titleTextStyle: AppTextStyles.title.copyWith(
        color: AppColors.textOnPrimary,
      ),
      iconTheme: const IconThemeData(color: AppColors.textOnPrimary),
    ),

    cardTheme: CardThemeData(
      elevation: 3,
      color: AppColors.surface,
      shadowColor: AppColors.shadow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      margin: EdgeInsets.zero,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: AppColors.info.withValues(alpha: 0.12),
      labelStyle: AppTextStyles.statusChip.copyWith(color: AppColors.info),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        side: BorderSide.none,
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceRaised,
      hintStyle: AppTextStyles.bodySecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.textFieldRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.textFieldRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.textFieldRadius),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, AppSizes.buttonHeight),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        textStyle: AppTextStyles.button,
        elevation: 2,
        shadowColor: AppColors.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, AppSizes.buttonHeight),
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 1.4),
        textStyle: AppTextStyles.button.copyWith(color: AppColors.primary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        ),
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
  );
}

/// Reserved for the single deliberate gradient moment per screen
/// (rider home header, login backdrop) — not applied globally.
class AppGradients {
  AppGradients._();

  static const BoxDecoration heroHeader = BoxDecoration(
    gradient: LinearGradient(
      colors: AppColors.heroGradient,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );
}

/// Status → color/label mapping for delivery states, used by rider
/// screens so every screen renders the same status the same way.
enum DeliveryStatus { assigned, pickedUp, inTransit, delivered, cancelled }

extension DeliveryStatusStyle on DeliveryStatus {
  Color get color {
    switch (this) {
      case DeliveryStatus.assigned:
        return AppColors.info;
      case DeliveryStatus.pickedUp:
      case DeliveryStatus.inTransit:
        return AppColors.warning;
      case DeliveryStatus.delivered:
        return AppColors.success;
      case DeliveryStatus.cancelled:
        return AppColors.error;
    }
  }

  String get label {
    switch (this) {
      case DeliveryStatus.assigned:
        return 'Assigned';
      case DeliveryStatus.pickedUp:
        return 'Picked up';
      case DeliveryStatus.inTransit:
        return 'In transit';
      case DeliveryStatus.delivered:
        return 'Delivered';
      case DeliveryStatus.cancelled:
        return 'Cancelled';
    }
  }
}

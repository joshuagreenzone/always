import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_text_styles.dart';

/// A colored pill for order/payment/delivery status. One shape, driven
/// by [color], so every screen renders status the same way.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const StatusChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizes.statusChipHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
      child: Text(
        label,
        style: AppTextStyles.statusChip.copyWith(color: color),
      ),
    );
  }
}

/// Maps a payment-status string from the API to a status color, so
/// PAID/PARTIALLY_PAID/UNPAID always render with the same meaning.
Color paymentStatusColor(String status) {
  switch (status.toUpperCase().replaceAll(' ', '_')) {
    case 'PAID':
      return AppColors.success;
    case 'PARTIALLY_PAID':
      return AppColors.warning;
    case 'UNPAID':
      return AppColors.error;
    default:
      return AppColors.textSecondary;
  }
}

/// Maps a rider transaction type (DELIVERY / PICKUP) to a color, kept
/// distinct from payment-status colors so the two chips never clash.
Color transactionTypeColor(String type) {
  switch (type.toUpperCase()) {
    case 'DELIVERY':
      return AppColors.info;
    case 'PICKUP':
      return AppColors.accent;
    default:
      return AppColors.textSecondary;
  }
}

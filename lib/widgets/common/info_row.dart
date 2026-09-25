import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final bool bold;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(label, style: AppTextStyles.bodySecondary),
          const Spacer(),
          Text(
            value,
            textAlign: TextAlign.end,
            style: bold
                ? AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)
                : AppTextStyles.body,
          ),
        ],
      ),
    );
  }
}

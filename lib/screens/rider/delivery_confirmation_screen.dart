import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../models/order_details.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

import '../../widgets/common/icon_badge.dart';
import '../../widgets/common/info_row.dart';

import 'payment_screen.dart';

import '../../services/rider_service.dart';

class DeliveryConfirmationScreen extends StatelessWidget {
  final Account account;
  final OrderDetails order;
  final List<String> scannedBottles;

  const DeliveryConfirmationScreen({
    super.key,
    required this.account,
    required this.order,
    required this.scannedBottles,
  });

  Future<void> _completeDelivery(BuildContext context) async {
    try {
      final riderService = RiderService();

      await riderService.completeDelivery(
        accId: account.accId,
        orderId: order.orderId,
        deliveryId: order.deliveryId,
      );

      if (!context.mounted) {
        return;
      }

      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      if (!context.mounted) {
        return;
      }

      String message = e.toString();

      if (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      }

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          ),
          title: const Text('Delivery Failed'),
          content: Text(message),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Delivery')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSizes.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSuccessHeader(),

              const SizedBox(height: AppSpacing.md),

              _buildCustomerCard(),

              const SizedBox(height: AppSpacing.md),

              _buildOrderCard(),

              const SizedBox(height: AppSpacing.md),

              _buildBottlesCard(),

              const SizedBox(height: AppSpacing.lg),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (order.paymentStatus == 'PAID') {
                      // Already fully paid.
                      // Do not open the payment screen.
                      await _completeDelivery(context);
                      return;
                    }

                    // UNPAID or PARTIALLY_PAID
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PaymentScreen(account: account, order: order),
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Confirm Delivery'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Column(
          children: [
            IconBadge(
              icon: Icons.check_circle,
              color: AppColors.success,
              size: AppSizes.largeIconSize,
            ),

            const SizedBox(height: AppSpacing.md),

            Text('Bottles Scanned', style: AppTextStyles.title),

            const SizedBox(height: AppSpacing.xs),

            Text(
              '${scannedBottles.length} of '
              '${order.quantity} bottles scanned successfully.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Customer', style: AppTextStyles.title),

            const SizedBox(height: AppSpacing.md),

            Row(
              children: [
                const IconBadge(
                  icon: Icons.person_outline,
                  color: AppColors.info,
                  size: 36,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(order.customerName, style: AppTextStyles.body),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order Information', style: AppTextStyles.title),

            const SizedBox(height: AppSpacing.sm),

            InfoRow(label: 'Order', value: '#${order.orderId}'),

            InfoRow(label: 'Bottle Type', value: order.bottleType),

            InfoRow(label: 'Quantity', value: '${order.quantity}'),

            InfoRow(
              label: 'Total',
              value: '₱${order.totalAmount.toStringAsFixed(2)}',
              bold: true,
            ),

            InfoRow(label: 'Payment', value: order.paymentStatus),
          ],
        ),
      ),
    );
  }

  Widget _buildBottlesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bottles to be Delivered', style: AppTextStyles.title),

            const SizedBox(height: AppSpacing.md),

            ...scannedBottles.map((bottleNumber) {
              return Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.06),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.water_drop, color: AppColors.success),

                    const SizedBox(width: AppSpacing.md),

                    Expanded(
                      child: Text(
                        bottleNumber,
                        style: AppTextStyles.dashboardTitle,
                      ),
                    ),

                    const Icon(Icons.check_circle, color: AppColors.success),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

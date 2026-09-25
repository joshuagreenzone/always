import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../models/order_details.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

import 'payment_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Delivery'), centerTitle: true),
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
            const Icon(Icons.check_circle, size: 64, color: AppColors.success),

            const SizedBox(height: AppSpacing.md),

            const Text('Bottles Scanned', style: AppTextStyles.sectionTitle),

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
            const Text('Customer', style: AppTextStyles.sectionTitle),

            const SizedBox(height: AppSpacing.md),

            Row(
              children: [
                const Icon(Icons.person_outline, size: 28),
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
            const Text('Order Information', style: AppTextStyles.sectionTitle),

            const SizedBox(height: AppSpacing.md),

            _InfoRow(label: 'Order', value: '#${order.orderId}'),

            _InfoRow(label: 'Bottle Type', value: order.bottleType),

            _InfoRow(label: 'Quantity', value: '${order.quantity}'),

            _InfoRow(
              label: 'Total',
              value: '₱${order.totalAmount.toStringAsFixed(2)}',
              bold: true,
            ),

            _InfoRow(label: 'Payment', value: order.paymentStatus),
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
            const Text(
              'Bottles to be Delivered',
              style: AppTextStyles.sectionTitle,
            ),

            const SizedBox(height: AppSpacing.md),

            ...scannedBottles.map((bottleNumber) {
              return Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _InfoRow({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Text(label, style: AppTextStyles.bodySecondary),

          const Spacer(),

          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

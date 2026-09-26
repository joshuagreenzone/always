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

  /*
   * Temporary bottles scanned by the rider.
   *
   * Each item contains:
   *
   * bottleNumber
   * latitude
   * longitude
   * accuracy
   *
   * These bottles have NOT been saved to the database yet.
   */
  final List<Map<String, dynamic>> scannedBottles;

  const DeliveryConfirmationScreen({
    super.key,
    required this.account,
    required this.order,
    required this.scannedBottles,
  });

  // ============================================================
  // COMPLETE DELIVERY
  // ============================================================
  //
  // This function sends ALL temporarily scanned bottles to the
  // server only after the rider confirms the delivery.
  //
  // The server will validate all bottles and save them inside
  // one database transaction.
  //
  // If one bottle fails validation, the server rolls everything
  // back, so no partial delivery is saved.
  //

  Future<void> _completeDelivery(BuildContext context) async {
    /*
     * IMPORTANT:
     *
     * Do not call completeDelivery() while scanning.
     *
     * The DeliveryScanScreen only keeps scanned bottles in
     * temporary memory.
     *
     * This is the point where the temporary bottle list is
     * finally sent to the server.
     */
    try {
      final riderService = RiderService();

      await riderService.completeDelivery(
        accId: account.accId,
        orderId: order.orderId,
        deliveryId: order.deliveryId,
        bottles: scannedBottles,
      );

      if (!context.mounted) {
        return;
      }

      /*
       * Delivery was successfully completed.
       *
       * Return to the first screen so the completed order is no
       * longer left in the rider's delivery flow.
       */
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

  // ============================================================
  // CONFIRM DELIVERY
  // ============================================================
  //
  // This is the single entry point when the rider presses
  // "Confirm Delivery".
  //
  // Before proceeding, make sure the rider scanned exactly the
  // number of bottles required by the order.
  //
  // This prevents the rider from reaching the payment screen or
  // completing a delivery with an incomplete bottle list.
  // ============================================================

  Future<void> _handleConfirmDelivery(BuildContext context) async {
    if (scannedBottles.length != order.quantity) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          ),
          title: const Text('Incomplete Bottle Scan'),
          content: Text(
            'This order requires ${order.quantity} bottle'
            '${order.quantity == 1 ? '' : 's'}, '
            'but only ${scannedBottles.length} '
            'bottle${scannedBottles.length == 1 ? '' : 's'} '
            'ha${scannedBottles.length == 1 ? 's' : 've'} been scanned.\n\n'
            'Please scan all required bottles before confirming '
            'the delivery.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      return;
    }

    /*
     * The order is already fully paid.
     *
     * We can complete the delivery immediately.
     *
     * The temporary bottles are sent to completeDelivery(),
     * which performs the final database transaction.
     */
    if (order.paymentStatus == 'PAID') {
      await _completeDelivery(context);
      return;
    }

    /*
     * UNPAID or PARTIALLY_PAID
     *
     * Open the payment screen.
     *
     * The temporary bottle list is passed to PaymentScreen so
     * the scan information is preserved while payment is being
     * recorded.
     */
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          account: account,
          order: order,
          scannedBottles: scannedBottles,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool allBottlesScanned = scannedBottles.length == order.quantity;

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
                  /*
                   * The button is only enabled when all required
                   * bottles have been scanned.
                   */
                  onPressed: allBottlesScanned
                      ? () => _handleConfirmDelivery(context)
                      : null,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Confirm Delivery'),
                ),
              ),

              if (!allBottlesScanned) ...[
                const SizedBox(height: AppSpacing.sm),

                Center(
                  child: Text(
                    'Scan all ${order.quantity} required bottles '
                    'before confirming the delivery.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SUCCESS HEADER
  // ============================================================

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

  // ============================================================
  // CUSTOMER CARD
  // ============================================================

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

  // ============================================================
  // ORDER CARD
  // ============================================================

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

  // ============================================================
  // BOTTLES CARD
  // ============================================================
  //
  // Displays the temporary bottles that will be submitted when
  // the delivery is finally confirmed.
  //
  // The bottles are still NOT saved to the database here.
  // ============================================================

  Widget _buildBottlesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bottles to be Delivered', style: AppTextStyles.title),

            const SizedBox(height: AppSpacing.md),

            ...scannedBottles.map((bottle) {
              final bottleNumber = bottle['bottleNumber']?.toString() ?? '';

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

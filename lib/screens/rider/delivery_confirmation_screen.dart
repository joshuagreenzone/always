import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../models/order_details.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

import '../../widgets/common/icon_badge.dart';
import '../../widgets/common/info_row.dart';

import '../../services/rider_service.dart';

import 'payment_screen.dart';

class DeliveryConfirmationScreen extends StatefulWidget {
  final Account account;
  final OrderDetails order;

  /*
   * Temporarily scanned bottles.
   *
   * Each item contains:
   * bottleNumber
   * latitude
   * longitude
   * accuracy
   *
   * These bottles have not yet been saved to the database.
   */
  final List<Map<String, dynamic>> scannedBottles;

  const DeliveryConfirmationScreen({
    super.key,
    required this.account,
    required this.order,
    required this.scannedBottles,
  });

  @override
  State<DeliveryConfirmationScreen> createState() =>
      _DeliveryConfirmationScreenState();
}

class _DeliveryConfirmationScreenState
    extends State<DeliveryConfirmationScreen> {
  final TextEditingController _incompleteReasonController =
      TextEditingController();

  bool _isSubmitting = false;

  bool get _isPartialDelivery =>
      widget.scannedBottles.length < widget.order.totalQuantity;

  @override
  void dispose() {
    _incompleteReasonController.dispose();
    super.dispose();
  }

  // ============================================================
  // DIALOG
  // ============================================================

  Future<void> _showMessage({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        ),
        title: Text(title),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CONFIRM DELIVERY
  // ============================================================

  Future<void> _handleConfirmDelivery() async {
    if (_isSubmitting) return;

    final int scannedCount = widget.scannedBottles.length;
    final int orderedCount = widget.order.totalQuantity;

    if (scannedCount < 1) {
      await _showMessage(
        title: 'No Bottles Scanned',
        message: 'Scan at least one bottle before confirming delivery.',
      );
      return;
    }

    if (scannedCount > orderedCount) {
      await _showMessage(
        title: 'Invalid Bottle Count',
        message: 'The scanned bottle count exceeds the ordered quantity.',
      );
      return;
    }

    final String incompleteReason = _incompleteReasonController.text.trim();

    if (_isPartialDelivery && incompleteReason.isEmpty) {
      await _showMessage(
        title: 'Reason Required',
        message:
            'Please explain why the delivery is incomplete before continuing.',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final riderService = RiderService();

      // Save the delivery first. The API must support incompleteReason
      // and mark the delivery INCOMPLETE when fewer bottles are delivered.
      await riderService.completeDelivery(
        accId: widget.account.accId,
        orderId: widget.order.orderId,
        deliveryId: widget.order.deliveryId,
        bottles: widget.scannedBottles,
        incompleteReason: _isPartialDelivery ? incompleteReason : null,
      );

      if (!mounted) return;

      /*
       * The delivery is now recorded. Do not complete it a second time
       * from PaymentScreen.
       *
       * If payment remains outstanding, open the payment screen.
       * Otherwise, return to the rider's first screen.
       */
      if (widget.order.paymentStatus == 'PAID') {
        Navigator.popUntil(context, (route) => route.isFirst);
        return;
      }

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            account: widget.account,
            order: widget.order,
            scannedBottles: widget.scannedBottles,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      String message = e.toString();

      if (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      }

      await _showMessage(title: 'Delivery Failed', message: message);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final int scannedCount = widget.scannedBottles.length;
    final int orderedCount = widget.order.totalQuantity;
    final int undeliveredCount = (orderedCount - scannedCount).clamp(
      0,
      orderedCount,
    );

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

              if (_isPartialDelivery) ...[
                const SizedBox(height: AppSpacing.md),
                _buildIncompleteDeliveryReason(undeliveredCount),
              ],

              const SizedBox(height: AppSpacing.lg),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _handleConfirmDelivery,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle),
                  label: Text(
                    _isSubmitting
                        ? 'Saving Delivery...'
                        : _isPartialDelivery
                        ? 'Confirm Incomplete Delivery'
                        : 'Confirm Delivery',
                  ),
                ),
              ),

              if (_isPartialDelivery) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Only the scanned bottles will be recorded as delivered. '
                  'The remaining $undeliveredCount bottle'
                  '${undeliveredCount == 1 ? '' : 's'} will not be marked '
                  'as delivered.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySecondary,
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
              icon: _isPartialDelivery
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle,
              color: _isPartialDelivery ? AppColors.warning : AppColors.success,
              size: AppSizes.largeIconSize,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _isPartialDelivery ? 'Partial Delivery' : 'Bottles Scanned',
              style: AppTextStyles.title,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${widget.scannedBottles.length} of '
              '${widget.order.totalQuantity} bottles scanned.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // INCOMPLETE DELIVERY REASON
  // ============================================================

  Widget _buildIncompleteDeliveryReason(int undeliveredCount) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reason for Incomplete Delivery', style: AppTextStyles.title),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '$undeliveredCount bottle'
              '${undeliveredCount == 1 ? '' : 's'} '
              'could not be delivered. Please explain why.',
              style: AppTextStyles.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _incompleteReasonController,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Enter the reason for the incomplete delivery...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                ),
                alignLabelWithHint: true,
              ),
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
                  child: Text(
                    widget.order.customerName,
                    style: AppTextStyles.body,
                  ),
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
            InfoRow(label: 'Order', value: '#${widget.order.orderId}'),
            const SizedBox(height: AppSpacing.sm),
            Text('Order Items', style: AppTextStyles.bodySecondary),
            const SizedBox(height: AppSpacing.xs),
            ...widget.order.items.map(_buildOrderItem),
            const Divider(height: AppSpacing.lg),
            InfoRow(
              label: 'Ordered Bottles',
              value: '${widget.order.totalQuantity}',
              bold: true,
            ),
            InfoRow(
              label: 'Scanned Bottles',
              value: '${widget.scannedBottles.length}',
              bold: true,
            ),
            InfoRow(
              label: 'Order Total',
              value: '₱${widget.order.totalAmount.toStringAsFixed(2)}',
              bold: true,
            ),
            InfoRow(label: 'Payment', value: widget.order.paymentStatus),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItem(OrderItemDetails item) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.water_drop_outlined, color: AppColors.accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  item.bottleType,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text('× ${item.quantity}', style: AppTextStyles.body),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          InfoRow(
            label: 'Unit Price',
            value: '₱${item.unitPrice.toStringAsFixed(2)}',
          ),
          InfoRow(
            label: 'Subtotal',
            value: '₱${item.totalAmount.toStringAsFixed(2)}',
            bold: true,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BOTTLES CARD
  // ============================================================

  Widget _buildBottlesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bottles Scanned', style: AppTextStyles.title),
            const SizedBox(height: AppSpacing.md),
            ...widget.scannedBottles.map((bottle) {
              final String bottleNumber =
                  bottle['bottleNumber']?.toString() ?? '';

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

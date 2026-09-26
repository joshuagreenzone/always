import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../models/assigned_order.dart';
import '../../models/order_details.dart';
import '../../services/rider_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

import '../../widgets/common/icon_badge.dart';
import '../../widgets/common/info_row.dart';
import '../../widgets/common/status_chip.dart';

import 'delivery_scan_screen.dart';

class OrderDetailsScreen extends StatefulWidget {
  final Account account;
  final AssignedOrder order;

  const OrderDetailsScreen({
    super.key,
    required this.account,
    required this.order,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  final RiderService _riderService = RiderService();

  bool _isLoading = true;
  String? _errorMessage;
  OrderDetails? _orderDetails;

  @override
  void initState() {
    super.initState();
    _loadOrderDetails();
  }

  Future<void> _loadOrderDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _riderService.getOrderDetails(
        orderId: widget.order.orderId,
        accId: widget.account.accId,
      );

      if (!mounted) return;

      setState(() {
        _orderDetails = result;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Order #${widget.order.orderId}')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildError();
    }

    final order = _orderDetails;

    if (order == null) {
      return const Center(child: Text('Order details unavailable.'));
    }

    return RefreshIndicator(
      onRefresh: _loadOrderDetails,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrderHeader(order),

            const SizedBox(height: AppSpacing.md),

            _buildCustomerCard(order),

            const SizedBox(height: AppSpacing.md),

            _buildOrderInformation(order),

            const SizedBox(height: AppSpacing.md),

            _buildDeliverySection(order),

            const SizedBox(height: AppSpacing.lg),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DeliveryScanScreen(
                        account: widget.account,
                        order: order,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.local_shipping),
                label: const Text('Start Delivery'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderHeader(OrderDetails order) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Row(
          children: [
            const IconBadge(
              icon: Icons.receipt_long,
              color: AppColors.primary,
              size: 52,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order #${order.orderId}', style: AppTextStyles.title),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    order.deliveryStatus,
                    style: AppTextStyles.bodySecondary,
                  ),
                ],
              ),
            ),
            StatusChip(
              label: order.paymentStatus,
              color: paymentStatusColor(order.paymentStatus),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard(OrderDetails order) {
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

  Widget _buildOrderInformation(OrderDetails order) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order Information', style: AppTextStyles.title),
            const SizedBox(height: AppSpacing.md),

            if (order.items.isEmpty)
              Text('No order items found.', style: AppTextStyles.bodySecondary)
            else
              ...order.items.map((item) => _buildOrderItem(item)),

            const Divider(height: AppSpacing.lg),

            InfoRow(
              label: 'Total Bottles',
              value: '${order.totalQuantity}',
              bold: true,
            ),

            InfoRow(
              label: 'Total Amount',
              value: '₱${order.totalAmount.toStringAsFixed(2)}',
              bold: true,
            ),

            InfoRow(label: 'Payment', value: order.paymentStatus),
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
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.border),
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

  Widget _buildDeliverySection(OrderDetails order) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBadge(
                  icon: Icons.water_drop_outlined,
                  color: AppColors.accent,
                  size: 36,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('Delivery Bottles', style: AppTextStyles.title),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            Text(
              '${order.totalQuantity} bottle'
              '${order.totalQuantity == 1 ? '' : 's'} required',
              style: AppTextStyles.body,
            ),

            const SizedBox(height: AppSpacing.sm),

            ...order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  '${item.quantity} × ${item.bottleType}',
                  style: AppTextStyles.bodySecondary,
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xs),

            Text(
              'Bottle numbers will be recorded when the rider scans the bottles during delivery.',
              style: AppTextStyles.bodySecondary,
            ),

            const SizedBox(height: AppSpacing.md),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.qr_code_scanner,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'No bottles scanned yet.',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return RefreshIndicator(
      onRefresh: _loadOrderDetails,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: [
          const SizedBox(height: 100),

          Center(
            child: IconBadge(
              icon: Icons.error_outline,
              color: AppColors.error,
              size: AppSizes.largeIconSize,
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          Center(
            child: Text('Unable to load order', style: AppTextStyles.title),
          ),

          const SizedBox(height: AppSpacing.sm),

          Center(
            child: Text(
              _errorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary,
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          Center(
            child: ElevatedButton(
              onPressed: _loadOrderDetails,
              child: const Text('Try Again'),
            ),
          ),
        ],
      ),
    );
  }
}

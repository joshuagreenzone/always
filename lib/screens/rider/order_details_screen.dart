import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../models/assigned_order.dart';
import '../../models/order_details.dart';
import '../../services/rider_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

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
      appBar: AppBar(
        title: Text('Order #${widget.order.orderId}'),
        centerTitle: true,
      ),
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
            const Icon(Icons.receipt_long, size: 44),

            const SizedBox(width: AppSpacing.md),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #${order.orderId}',
                    style: AppTextStyles.sectionTitle,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    order.deliveryStatus,
                    style: AppTextStyles.bodySecondary,
                  ),
                ],
              ),
            ),

            _PaymentStatus(status: order.paymentStatus),
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

  Widget _buildOrderInformation(OrderDetails order) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Order Information', style: AppTextStyles.sectionTitle),

            const SizedBox(height: AppSpacing.md),

            _InfoRow(label: 'Bottle Type', value: order.bottleType),

            _InfoRow(label: 'Quantity', value: '${order.quantity}'),

            _InfoRow(
              label: 'Unit Price',
              value: '₱${order.unitPrice.toStringAsFixed(2)}',
            ),

            const Divider(),

            _InfoRow(
              label: 'Total Amount',
              value: '₱${order.totalAmount.toStringAsFixed(2)}',
              bold: true,
            ),

            _InfoRow(label: 'Payment', value: order.paymentStatus),
          ],
        ),
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
            const Row(
              children: [
                Icon(Icons.water_drop_outlined),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Delivery Bottles',
                    style: AppTextStyles.sectionTitle,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            Text(
              '${order.quantity} ${order.bottleType} bottle'
              '${order.quantity == 1 ? '' : 's'} required',
              style: AppTextStyles.body,
            ),

            const SizedBox(height: AppSpacing.sm),

            const Text(
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
              child: const Row(
                children: [
                  Icon(Icons.qr_code_scanner),

                  SizedBox(width: AppSpacing.sm),

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
          const SizedBox(height: 120),

          const Icon(
            Icons.error_outline,
            size: AppSizes.largeIconSize,
            color: AppColors.error,
          ),

          const SizedBox(height: AppSpacing.md),

          const Center(
            child: Text(
              'Unable to load order',
              style: AppTextStyles.sectionTitle,
            ),
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

class _PaymentStatus extends StatelessWidget {
  final String status;

  const _PaymentStatus({required this.status});

  @override
  Widget build(BuildContext context) {
    final isPaid = status.toUpperCase() == 'PAID';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (isPaid ? AppColors.success : AppColors.warning).withOpacity(
          0.15,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isPaid ? AppColors.success : AppColors.warning,
        ),
      ),
    );
  }
}

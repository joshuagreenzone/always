import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../models/assigned_order.dart';
import '../../services/rider_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

import '../../widgets/common/icon_badge.dart';
import '../../widgets/common/info_row.dart';
import '../../widgets/common/status_chip.dart';

import 'order_details_screen.dart';

class AssignedOrdersScreen extends StatefulWidget {
  final Account account;

  const AssignedOrdersScreen({super.key, required this.account});

  @override
  State<AssignedOrdersScreen> createState() => _AssignedOrdersScreenState();
}

class _AssignedOrdersScreenState extends State<AssignedOrdersScreen> {
  final RiderService _riderService = RiderService();

  bool _isLoading = true;
  String? _errorMessage;
  List<AssignedOrder> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final orders = await _riderService.getAssignedOrders(
        widget.account.accId,
      );

      if (!mounted) return;

      setState(() {
        _orders = orders;
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
      appBar: AppBar(title: const Text('Assigned Orders')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_orders.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          return _OrderCard(account: widget.account, order: _orders[index]);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),

          Center(
            child: IconBadge(
              icon: Icons.local_shipping_outlined,
              color: AppColors.textSecondary,
              size: AppSizes.largeIconSize,
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          Center(
            child: Text('No assigned orders.', style: AppTextStyles.title),
          ),

          const SizedBox(height: AppSpacing.sm),

          Center(
            child: Text(
              'Assigned deliveries will appear here.',
              style: AppTextStyles.bodySecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return RefreshIndicator(
      onRefresh: _loadOrders,
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
            child: Text('Unable to load orders', style: AppTextStyles.title),
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
              onPressed: _loadOrders,
              child: const Text('Try Again'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Account account;
  final AssignedOrder order;

  const _OrderCard({required this.order, required this.account});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBadge(
                  icon: Icons.receipt_long,
                  color: AppColors.primary,
                ),

                const SizedBox(width: AppSpacing.md),

                Expanded(
                  child: Text(
                    'Order #${order.orderId}',
                    style: AppTextStyles.dashboardTitle,
                  ),
                ),

                StatusChip(
                  label: order.paymentStatus,
                  color: paymentStatusColor(order.paymentStatus),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            const Divider(),

            const SizedBox(height: AppSpacing.xs),

            InfoRow(
              icon: Icons.person_outline,
              label: 'Customer',
              value: order.customerName,
            ),

            const SizedBox(height: AppSpacing.xs),

            Text('Bottle Types', style: AppTextStyles.bodySecondary),

            const SizedBox(height: AppSpacing.xs),

            ...order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    const Icon(
                      Icons.water_drop_outlined,
                      size: 18,
                      color: AppColors.accent,
                    ),

                    const SizedBox(width: AppSpacing.sm),

                    Expanded(
                      child: Text(item.bottleType, style: AppTextStyles.body),
                    ),

                    Text('× ${item.quantity}', style: AppTextStyles.body),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xs),

            InfoRow(
              icon: Icons.inventory_2_outlined,
              label: 'Total Bottles',
              value: '${order.totalQuantity}',
            ),

            InfoRow(
              icon: Icons.payments_outlined,
              label: 'Total',
              value: '₱${order.totalAmount.toStringAsFixed(2)}',
              bold: true,
            ),

            const SizedBox(height: AppSpacing.sm),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          OrderDetailsScreen(account: account, order: order),
                    ),
                  );
                },
                icon: const Icon(Icons.arrow_forward),
                label: const Text('View Order'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

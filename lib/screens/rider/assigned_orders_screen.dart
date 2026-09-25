import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../models/assigned_order.dart';
import '../../services/rider_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

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
      appBar: AppBar(title: const Text('Assigned Orders'), centerTitle: true),
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
        children: const [
          SizedBox(height: 180),
          Icon(
            Icons.local_shipping_outlined,
            size: AppSizes.largeIconSize,
            color: AppColors.textSecondary,
          ),
          SizedBox(height: AppSpacing.md),
          Center(
            child: Text(
              'No assigned orders.',
              style: AppTextStyles.sectionTitle,
            ),
          ),
          SizedBox(height: AppSpacing.sm),
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
          const SizedBox(height: 120),

          const Icon(
            Icons.error_outline,
            size: AppSizes.largeIconSize,
            color: AppColors.error,
          ),

          const SizedBox(height: AppSpacing.md),

          const Center(
            child: Text(
              'Unable to load orders',
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
                const Icon(Icons.receipt_long, size: 28),

                const SizedBox(width: AppSpacing.sm),

                Expanded(
                  child: Text(
                    'Order #${order.orderId}',
                    style: AppTextStyles.dashboardTitle,
                  ),
                ),

                _StatusChip(label: order.paymentStatus),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            const Divider(),

            const SizedBox(height: AppSpacing.md),

            _InfoRow(
              icon: Icons.person_outline,
              label: 'Customer',
              value: order.customerName,
            ),

            const SizedBox(height: AppSpacing.sm),

            _InfoRow(
              icon: Icons.water_drop_outlined,
              label: 'Bottle Type',
              value: order.bottleType,
            ),

            const SizedBox(height: AppSpacing.sm),

            _InfoRow(
              icon: Icons.inventory_2_outlined,
              label: 'Quantity',
              value: '${order.quantity}',
            ),

            const SizedBox(height: AppSpacing.sm),

            _InfoRow(
              icon: Icons.payments_outlined,
              label: 'Total',
              value: '₱${order.totalAmount.toStringAsFixed(2)}',
            ),

            const SizedBox(height: AppSpacing.md),

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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),

        const SizedBox(width: AppSpacing.sm),

        Text('$label:', style: AppTextStyles.bodySecondary),

        const SizedBox(width: AppSpacing.sm),

        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTextStyles.body,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;

  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.warning,
        ),
      ),
    );
  }
}

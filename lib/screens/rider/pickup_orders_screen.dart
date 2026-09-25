import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../models/pickup_order.dart';
import '../../services/rider_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

import '../../widgets/common/icon_badge.dart';
import '../../widgets/common/info_row.dart';

import 'pickup_scan_screen.dart';

class PickupOrdersScreen extends StatefulWidget {
  final Account account;

  const PickupOrdersScreen({super.key, required this.account});

  @override
  State<PickupOrdersScreen> createState() => _PickupOrdersScreenState();
}

class _PickupOrdersScreenState extends State<PickupOrdersScreen> {
  final RiderService _riderService = RiderService();

  List<PickupOrder> _orders = [];

  bool _isLoading = true;

  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final orders = await _riderService.getPickupOrders(widget.account.accId);

      if (!mounted) {
        return;
      }

      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openPickup(PickupOrder order) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PickupScanScreen(account: widget.account, order: order),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadOrders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pickup Bottles')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconBadge(
                icon: Icons.error_outline,
                color: AppColors.error,
                size: AppSizes.largeIconSize,
              ),

              const SizedBox(height: AppSpacing.md),

              Text(
                _error!.replaceFirst('Exception: ', ''),
                textAlign: TextAlign.center,
                style: AppTextStyles.body,
              ),

              const SizedBox(height: AppSpacing.md),

              ElevatedButton(
                onPressed: _loadOrders,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_orders.isEmpty) {
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
              child: Text(
                'No bottles are waiting for pickup.',
                style: AppTextStyles.title,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, index) {
          final order = _orders[index];

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const IconBadge(
                        icon: Icons.assignment_return_outlined,
                        color: AppColors.accent,
                      ),

                      const SizedBox(width: AppSpacing.md),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order #${order.orderId}',
                              style: AppTextStyles.dashboardTitle,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              order.customerName,
                              style: AppTextStyles.bodySecondary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.md),

                  const Divider(),

                  const SizedBox(height: AppSpacing.xs),

                  InfoRow(
                    icon: Icons.water_drop_outlined,
                    label: 'Bottle Type',
                    value: '${order.bottleType} × ${order.quantity}',
                  ),

                  InfoRow(
                    icon: Icons.local_shipping_outlined,
                    label: 'Delivered',
                    value: '${order.deliveredBottleCount}',
                  ),

                  InfoRow(
                    icon: Icons.qr_code_scanner,
                    label: 'Picked up',
                    value: '${order.pickedUpBottleCount}',
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openPickup(order),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan Pickup Bottles'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

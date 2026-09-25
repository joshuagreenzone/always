import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../models/pickup_order.dart';
import '../../services/rider_service.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

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
      appBar: AppBar(title: const Text('Pickup Bottles'), centerTitle: true),

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
              const Icon(Icons.error_outline, size: 56),

              const SizedBox(height: AppSpacing.md),

              Text(
                _error!.replaceFirst('Exception: ', ''),
                textAlign: TextAlign.center,
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
          children: const [
            SizedBox(height: 180),

            Icon(Icons.local_shipping_outlined, size: 64),

            SizedBox(height: 16),

            Center(child: Text('No bottles are waiting for pickup.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,

      child: ListView.builder(
        padding: const EdgeInsets.all(AppSizes.screenPadding),

        itemCount: _orders.length,

        itemBuilder: (_, index) {
          final order = _orders[index];

          return Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),

            child: Padding(
              padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    'Order #${order.orderId}',
                    style: AppTextStyles.dashboardTitle,
                  ),

                  const SizedBox(height: AppSpacing.xs),

                  Text(order.customerName, style: AppTextStyles.screenTitle),

                  const SizedBox(height: AppSpacing.sm),

                  Text(
                    '${order.bottleType} × ${order.quantity}',
                    style: AppTextStyles.body,
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  Text(
                    'Delivered: '
                    '${order.deliveredBottleCount}',
                    style: AppTextStyles.bodySecondary,
                  ),

                  Text(
                    'Picked up: '
                    '${order.pickedUpBottleCount}',
                    style: AppTextStyles.bodySecondary,
                  ),

                  const SizedBox(height: AppSpacing.md),

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

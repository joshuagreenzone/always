import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../models/pickup_order.dart';
import '../../services/rider_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';

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

      if (!mounted) return;

      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

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

    if (!mounted) return;

    await _loadOrders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'Pickup Bottles',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.3),
        ),
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0284C7)),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!.replaceFirst('Exception: ', ''),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: 180,
                height: 44,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _loadOrders,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'RETRY',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_orders.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF0284C7),
        onRefresh: _loadOrders,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.assignment_return_rounded,
                  size: 56,
                  color: Color(0xFFD97706),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Center(
              child: Text(
                'No Pending Pickups',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Text(
                'Orders awaiting empty bottle pickups will appear here.',
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF0284C7),
      onRefresh: _loadOrders,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, index) {
          final order = _orders[index];
          return _PickupOrderCard(
            order: order,
            onScanTap: () => _openPickup(order),
          );
        },
      ),
    );
  }
}

class _PickupOrderCard extends StatelessWidget {
  final PickupOrder order;
  final VoidCallback onScanTap;

  const _PickupOrderCard({required this.order, required this.onScanTap});

  // Maps bottle types (Square, Round, Wilkins) to water styles
  _BottleStyle _getBottleStyle(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('square')) {
      return const _BottleStyle(
        color: Color(0xFF0284C7),
        bgColor: Color(0xFFE0F2FE),
        icon: Icons.crop_square_rounded,
      );
    } else if (lower.contains('round')) {
      return const _BottleStyle(
        color: Color(0xFF059669),
        bgColor: Color(0xFFD1FAE5),
        icon: Icons.trip_origin_rounded,
      );
    } else if (lower.contains('wilkins')) {
      return const _BottleStyle(
        color: Color(0xFF0D9488),
        bgColor: Color(0xFFCCFBF1),
        icon: Icons.water_drop_rounded,
      );
    }
    return const _BottleStyle(
      color: Color(0xFF2563EB),
      bgColor: Color(0xFFDBEAFE),
      icon: Icons.local_drink_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottleStyle = _getBottleStyle(order.bottleType);
    const accentAmber = Color(0xFFD97706);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentAmber.withOpacity(0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accentAmber.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Customer Name & Order ID Tag
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customerName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.assignment_return_rounded,
                            size: 13,
                            color: accentAmber,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Bottle Pickup',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: accentAmber,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Order Number Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Order #${order.orderId}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 12),

            // Middle Row: Bottle Type Badge & Target Quantity
            Row(
              children: [
                // Bottle Type Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: bottleStyle.bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: bottleStyle.color.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        bottleStyle.icon,
                        size: 14,
                        color: bottleStyle.color,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        order.bottleType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: bottleStyle.color,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                Text(
                  '× ${order.quantity} Total',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Pickup Progress Stats Grid
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _CounterStat(
                      label: 'DELIVERED',
                      count: order.deliveredBottleCount,
                      icon: Icons.local_shipping_rounded,
                      iconColor: const Color(0xFF0284C7),
                    ),
                  ),
                  Container(
                    height: 28,
                    width: 1,
                    color: const Color(0xFFCBD5E1),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12.0),
                      child: _CounterStat(
                        label: 'PICKED UP',
                        count: order.pickedUpBottleCount,
                        icon: Icons.qr_code_scanner_rounded,
                        iconColor: const Color(0xFF10B981),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Scan Action Button
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentAmber,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onScanTap,
                icon: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                label: const Text(
                  'SCAN PICKUP BOTTLES',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterStat extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color iconColor;

  const _CounterStat({
    required this.label,
    required this.count,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Color(0xFF94A3B8),
                letterSpacing: 0.5,
              ),
            ),
            Text(
              '$count Bottles',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BottleStyle {
  final Color color;
  final Color bgColor;
  final IconData icon;

  const _BottleStyle({
    required this.color,
    required this.bgColor,
    required this.icon,
  });
}

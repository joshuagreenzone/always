import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../widgets/common/rider_order_list.dart';

import '../../models/account.dart';
import '../../models/pickup_order.dart';
import '../../services/rider_service.dart';

import 'pickup_scan_screen.dart';

class PickupOrdersScreen extends StatefulWidget {
  final Account account;
  final RiderService? riderService;

  const PickupOrdersScreen({
    super.key,
    required this.account,
    this.riderService,
  });

  @override
  State<PickupOrdersScreen> createState() => _PickupOrdersScreenState();
}

class _PickupOrdersScreenState extends State<PickupOrdersScreen> {
  late final RiderService _riderService = widget.riderService ?? RiderService();

  List<PickupOrder> _orders = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

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
  Widget build(BuildContext context) => RiderOrderList(
    title: 'Pickup Bottles',
    summary: 'Awaiting collection',
    count: _orders.length,
    loading: _isLoading,
    error: _error?.replaceFirst('Exception: ', ''),
    emptyMessage: 'No Pending Pickups',
    onRefresh: _loadOrders,
    orders: _orders
        .map(
          (order) => RiderOrderCard(
            key: ValueKey(order.deliveryId),
            orderId: order.orderId,
            customer: order.customerName,
            icon: Icons.assignment_return_outlined,
            badge: RiderOrderBadge(label: '${order.remainingBottleCount} left'),
            details: [
              ...order.bottleTypes.map(
                (type) => RiderOrderDetail(
                  label: type.bottleType,
                  value: '${type.remainingBottleCount} to collect',
                ),
              ),
              RiderOrderDetail(
                label: 'Collected',
                value:
                    '${order.pickedUpBottleCount} of ${order.deliveredBottleCount} bottles',
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: order.deliveredBottleCount <= 0
                      ? 0
                      : (order.pickedUpBottleCount / order.deliveredBottleCount)
                            .clamp(0.0, 1.0),
                  minHeight: 5,
                  color: riderOrderBlue,
                  backgroundColor: const Color(0xFFE2F0F7),
                ),
              ),
              const SizedBox(height: 7),
              RiderOrderDetail(
                label: 'Delivered',
                value: DateFormat('MMM d · h:mm a')
                    .format(order.deliveryDateTime.toLocal()),
              ),
              RiderOrderDetail(
                label: 'Delivery',
                value:
                    '#${order.deliveryId} · ${order.deliveryStatus.replaceAll('_', ' ')}',
              ),
            ],
            action: 'Scan pickup bottles',
            onTap: () => _openPickup(order),
          ),
        )
        .toList(),
  );
}

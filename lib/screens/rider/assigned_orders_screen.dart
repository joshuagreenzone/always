import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../widgets/common/rider_order_list.dart';

import '../../models/account.dart';
import '../../models/assigned_order.dart';
import '../../services/rider_service.dart';

import 'order_details_screen.dart';

class AssignedOrdersScreen extends StatefulWidget {
  final Account account;
  final RiderService? riderService;

  const AssignedOrdersScreen({
    super.key,
    required this.account,
    this.riderService,
  });

  @override
  State<AssignedOrdersScreen> createState() => _AssignedOrdersScreenState();
}

class _AssignedOrdersScreenState extends State<AssignedOrdersScreen> {
  late final RiderService _riderService = widget.riderService ?? RiderService();

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
  Widget build(BuildContext context) => RiderOrderList(
    title: 'Assigned Deliveries',
    summary: 'Ready for delivery',
    count: _orders.length,
    loading: _isLoading,
    error: _errorMessage,
    emptyMessage: 'No assigned deliveries.',
    onRefresh: _loadOrders,
    orders: _orders
        .map(
          (order) => RiderOrderCard(
            key: ValueKey(order.deliveryId),
            orderId: order.orderId,
            customer: order.customerName,
            highlightCustomer: true,
            icon: Icons.local_shipping_outlined,
            badge: RiderOrderBadge(
              label: switch (order.paymentStatus.toUpperCase()) {
                'PAID' => 'Paid',
                'PARTIALLY_PAID' => 'Partial',
                'UNPAID' => 'Unpaid',
                _ => order.paymentStatus.replaceAll('_', ' '),
              },
              paid: order.paymentStatus.toUpperCase() == 'PAID',
            ),
            details: [
              ...order.items.map(
                (item) => RiderOrderDetail(
                  label: 'Bottles',
                  value: '${item.quantity} × ${item.bottleType}',
                ),
              ),
              RiderOrderDetail(
                label: 'Total bottles',
                value: '${order.totalQuantity}',
              ),
              RiderOrderDetail(
                label: 'Total',
                value: '₱${order.totalAmount.toStringAsFixed(2)}',
              ),
              RiderOrderDetail(
                label: 'Scheduled',
                value: DateFormat('MMM d · h:mm a')
                    .format(order.deliveryDateTime.toLocal()),
              ),
              RiderOrderDetail(
                label: 'Status',
                value: order.deliveryStatus.replaceAll('_', ' '),
              ),
            ],
            action: 'View Order',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      OrderDetailsScreen(account: widget.account, order: order),
                ),
              );
              if (mounted) await _loadOrders();
            },
          ),
        )
        .toList(),
  );
}

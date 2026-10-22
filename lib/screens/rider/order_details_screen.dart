import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../models/assigned_order.dart';
import '../../models/order_details.dart';
import '../../services/rider_service.dart';
import '../../theme/app_colors.dart';

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
    final status = _orderDetails?.deliveryStatus ?? widget.order.deliveryStatus;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7FB),
      body: Column(
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF07344C), Color(0xFF168DB8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -35,
                  top: -65,
                  child: Container(
                    width: 210,
                    height: 210,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: .08),
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 20, 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              Text(
                                'Order #${widget.order.orderId}',
                                style: const TextStyle(
                                  color: Color(0xFFB8E6F5),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 5),
                              const Text(
                                'Delivery details',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0F3FB),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _statusLabel(status),
                                  style: const TextStyle(
                                    color: Color(0xFF075578),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  String _statusLabel(String value) => value
      .replaceAll('_', ' ')
      .toLowerCase()
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final order = _orderDetails;
    if (_errorMessage != null || order == null) {
      return RefreshIndicator(
        onRefresh: _loadOrderDetails,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 60),
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Order details unavailable.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Center(
              child: FilledButton(
                onPressed: _loadOrderDetails,
                child: const Text('Try Again'),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadOrderDetails,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          _card([
            _detail('Customer', order.customerName),
            _detail(
              'Address',
              order.customerAddress.isEmpty
                  ? 'Not provided'
                  : order.customerAddress,
            ),
            _detail(
              'Contact',
              order.customerContact.isEmpty
                  ? 'Not provided'
                  : order.customerContact,
            ),
          ]),
          const SizedBox(height: 14),
          _card([
            if (order.items.isEmpty)
              _detail('Quantity', '${order.totalQuantity} bottles')
            else
              ...order.items.asMap().entries.map(
                (entry) => _detail(
                  entry.key == 0 ? 'Quantity' : '',
                  '${entry.value.quantity} × ${entry.value.bottleType}',
                ),
              ),
            _detail('Total', '₱${order.totalAmount.toStringAsFixed(2)}'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Payment',
                      style: TextStyle(color: Color(0xFF71869A), fontSize: 12),
                    ),
                  ),
                  Flexible(
                    child: StatusChip(
                      label: _statusLabel(order.paymentStatus),
                      color: order.paymentStatus.toUpperCase() == 'UNPAID'
                          ? const Color(0xFFB76A12)
                          : paymentStatusColor(order.paymentStatus),
                    ),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF087DA9).withValues(alpha: .2),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF087DA9),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      DeliveryScanScreen(account: widget.account, order: order),
                ),
              ),
              child: const Text(
                'Start scanning bottles',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF71869A), fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFF102B40),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

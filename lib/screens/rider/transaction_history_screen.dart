import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/account.dart';
import '../../models/rider_transaction.dart';
import '../../services/rider_transaction_service.dart';
import 'assigned_orders_screen.dart';
import 'vehicle_scan_screen.dart';

class TransactionHistoryScreen extends StatefulWidget {
  final int accId;
  final Account? account;
  final RiderTransactionService? service;
  const TransactionHistoryScreen({
    super.key,
    required this.accId,
    this.account,
    this.service,
  });
  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  static const _blue = Color(0xFF087DA9);
  late final _service = widget.service ?? RiderTransactionService();
  List<RiderTransaction> _transactions = [];
  bool _pickups = false;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final transactions = await _service.getTransactionHistory(widget.accId);
      if (mounted) setState(() => _transactions = transactions);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isPickup(RiderTransaction tx) =>
      tx.transactionType.toUpperCase().contains('PICK') ||
      tx.transactionType.toUpperCase().contains('RETURN');

  @override
  Widget build(BuildContext context) => Scaffold(
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
                  padding: const EdgeInsets.fromLTRB(8, 14, 20, 26),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rider',
                              style: TextStyle(
                                color: Color(0xFFB8E6F5),
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'Transactions',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Row(
            children: [
              Expanded(child: _tab('Deliveries', false)),
              const SizedBox(width: 10),
              Expanded(child: _tab('Pickups', true)),
            ],
          ),
        ),
        Expanded(child: _buildList()),
      ],
    ),
    bottomNavigationBar: widget.account == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: NavigationBar(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                indicatorColor: const Color(0xFFE3F4FA),
                selectedIndex: 3,
                onDestinationSelected: _navigate,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.qr_code_scanner),
                    label: 'Scan',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    label: 'Orders',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history),
                    label: 'History',
                  ),
                ],
              ),
            ),
          ),
  );

  Future<void> _navigate(int index) async {
    final account = widget.account;
    if (account == null || index == 3) return;
    if (index == 0) {
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => index == 1
            ? VehicleScanScreen(account: account, returning: false)
            : AssignedOrdersScreen(account: account),
      ),
    );
    if (mounted) await _loadTransactions();
  }

  Widget _tab(String label, bool pickups) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: _pickups == pickups ? _blue : Colors.white,
      foregroundColor: _pickups == pickups
          ? Colors.white
          : const Color(0xFF07344C),
      minimumSize: const Size.fromHeight(46),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _pickups == pickups
              ? Colors.transparent
              : const Color(0xFFD7E7F0),
        ),
      ),
    ),
    onPressed: () => setState(() => _pickups = pickups),
    child: Text(label),
  );

  Widget _buildList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _blue));
    }
    final transactions = _transactions
        .where((tx) => _isPickup(tx) == _pickups)
        .toList();
    return RefreshIndicator(
      onRefresh: _loadTransactions,
      child: _error != null || transactions.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 50),
                Icon(
                  _error != null
                      ? Icons.error_outline
                      : Icons.receipt_long_outlined,
                  color: _blue,
                  size: 40,
                ),
                const SizedBox(height: 14),
                Text(
                  _error ?? (_pickups ? 'No pickups yet' : 'No deliveries yet'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                if (_error != null)
                  Center(
                    child: TextButton(
                      onPressed: _loadTransactions,
                      child: const Text('Retry'),
                    ),
                  ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              itemCount: transactions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) => _transactionCard(transactions[index]),
            ),
    );
  }

  String _dateLabel(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final date = parsed.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final time = DateFormat('h:mm a').format(date);
    if (day == today) return 'Today · $time';
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return 'Yesterday · $time';
    }
    return DateFormat('MMM d, yyyy · h:mm a').format(date);
  }

  ({String label, Color color, Color background}) _payment(String value) =>
      switch (value.toUpperCase().replaceAll(' ', '_')) {
        'PAID' || 'SETTLED' => (
          label: 'Paid',
          color: const Color(0xFF087F5B),
          background: const Color(0xFFDCF3E7),
        ),
        'PARTIALLY_PAID' || 'PARTIAL' => (
          label: 'Partial',
          color: const Color(0xFFA76012),
          background: const Color(0xFFFFECD0),
        ),
        'UNPAID' || 'PENDING' => (
          label: 'Unpaid',
          color: const Color(0xFFA76012),
          background: const Color(0xFFFFECD0),
        ),
        _ => (
          label: value,
          color: const Color(0xFF64748B),
          background: const Color(0xFFF1F5F9),
        ),
      };

  Widget _transactionCard(RiderTransaction tx) {
    final status = _payment(tx.paymentStatus);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF07344C).withValues(alpha: .05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showDetails(tx),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1AA6CE), Color(0xFF08628C)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _isPickup(tx)
                        ? Icons.assignment_return_outlined
                        : Icons.receipt_long_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #${tx.orderId}',
                        style: const TextStyle(
                          color: Color(0xFF102B40),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _dateLabel(tx.dateTime),
                        style: const TextStyle(
                          color: Color(0xFF71869A),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: status.background,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.label,
                      style: TextStyle(
                        color: status.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDetails(RiderTransaction tx) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Order #${tx.orderId}',
              style: const TextStyle(
                color: Color(0xFF075578),
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 14),
            _detail('Type', tx.transactionType.replaceAll('_', ' ')),
            _detail('Customer', tx.customerName),
            _detail(
              'Address',
              tx.customerAddress.isEmpty ? 'Not provided' : tx.customerAddress,
            ),
            _detail('Date', _dateLabel(tx.dateTime)),
            _detail('Bottles', '${tx.quantity} × ${tx.bottleType}'),
            _detail('Unit price', '₱${tx.unitPrice.toStringAsFixed(2)}'),
            _detail('Total', '₱${tx.totalAmount.toStringAsFixed(2)}'),
            _detail('Paid', '₱${tx.paidAmount.toStringAsFixed(2)}'),
            _detail('Balance', '₱${tx.balance.toStringAsFixed(2)}'),
            _detail('Payment', _payment(tx.paymentStatus).label),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF71869A), fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFF102B40),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

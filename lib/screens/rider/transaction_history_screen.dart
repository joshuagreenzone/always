import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/rider_transaction.dart';
import '../../services/rider_transaction_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

class TransactionHistoryScreen extends StatefulWidget {
  final int accId;

  const TransactionHistoryScreen({super.key, required this.accId});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final RiderTransactionService _service = RiderTransactionService();

  List<RiderTransaction> _transactions = [];

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

      if (!mounted) return;

      setState(() {
        _transactions = transactions;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'Transaction History',
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
                  onPressed: _loadTransactions,
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

    if (_transactions.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF0284C7),
        onRefresh: _loadTransactions,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  size: 56,
                  color: Color(0xFF0284C7),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Center(
              child: Text(
                'No Transactions Found',
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
                'Delivered and picked up customer transactions will appear here.',
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
      onRefresh: _loadTransactions,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        itemCount: _transactions.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          return _TransactionCard(transaction: _transactions[index]);
        },
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final RiderTransaction transaction;

  const _TransactionCard({required this.transaction});

  String _formatDateTime(String value) {
    try {
      final dateTime = DateTime.parse(value);
      return DateFormat('MMM d, yyyy • h:mm a').format(dateTime);
    } catch (_) {
      return value;
    }
  }

  // Returns distinct styling for Transaction Types (Delivery, Pickup, etc.)
  _TransactionTypeStyle _getTransactionTypeStyle(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('deliver') || lower.contains('completed')) {
      return const _TransactionTypeStyle(
        color: Color(0xFF059669), // Emerald Green
        bgColor: Color(0xFFD1FAE5),
        icon: Icons.local_shipping_rounded,
      );
    } else if (lower.contains('pickup') || lower.contains('return')) {
      return const _TransactionTypeStyle(
        color: Color(0xFFD97706), // Amber
        bgColor: Color(0xFFFEF3C7),
        icon: Icons.assignment_return_rounded,
      );
    }
    return const _TransactionTypeStyle(
      color: Color(0xFF0284C7), // Sky Blue Fallback
      bgColor: Color(0xFFE0F2FE),
      icon: Icons.swap_horiz_rounded,
    );
  }

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

  // Payment Status Color Mapping
  _StatusStyle _getPaymentStatusStyle(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('paid') || lower.contains('settled')) {
      return const _StatusStyle(
        color: Color(0xFF10B981),
        bgColor: Color(0xFFECFDF5),
      );
    } else if (lower.contains('unpaid') || lower.contains('pending')) {
      return const _StatusStyle(
        color: Color(0xFFEF4444),
        bgColor: Color(0xFFFEF2F2),
      );
    }
    return const _StatusStyle(
      color: Color(0xFF64748B),
      bgColor: Color(0xFFF1F5F9),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txStyle = _getTransactionTypeStyle(transaction.transactionType);
    final bottleStyle = _getBottleStyle(transaction.bottleType);
    final payStyle = _getPaymentStatusStyle(transaction.paymentStatus);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: txStyle.color.withOpacity(0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: txStyle.color.withOpacity(0.08),
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
            // Header Row: Customer Name & Transaction Type Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.customerName,
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
                            Icons.location_on_rounded,
                            size: 13,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              transaction.customerAddress,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // High Contrast Transaction Type Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: txStyle.bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: txStyle.color.withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(txStyle.icon, size: 14, color: txStyle.color),
                      const SizedBox(width: 4),
                      Text(
                        transaction.transactionType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: txStyle.color,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 12),

            // Middle Row: Bottle Type Badge & Quantity
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
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: bottleStyle.color.withOpacity(0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        bottleStyle.icon,
                        size: 13,
                        color: bottleStyle.color,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        transaction.bottleType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: bottleStyle.color,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '× ${transaction.quantity}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Amount Block Matrix
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
                    child: _AmountBlock(
                      label: 'TOTAL',
                      value: transaction.totalAmount,
                    ),
                  ),
                  Container(
                    height: 24,
                    width: 1,
                    color: const Color(0xFFCBD5E1),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12.0),
                      child: _AmountBlock(
                        label: 'PAID',
                        value: transaction.paidAmount,
                        valueColor: const Color(0xFF059669),
                      ),
                    ),
                  ),
                  Container(
                    height: 24,
                    width: 1,
                    color: const Color(0xFFCBD5E1),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12.0),
                      child: _AmountBlock(
                        label: 'BALANCE',
                        value: transaction.balance,
                        valueColor: transaction.balance > 0
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Bottom Bar: Payment Status Chip & DateTime
            Row(
              children: [
                // Payment Status Chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: payStyle.bgColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    transaction.paymentStatus.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: payStyle.color,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _formatDateTime(transaction.dateTime),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountBlock extends StatelessWidget {
  final String label;
  final double value;
  final Color? valueColor;

  const _AmountBlock({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
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
        const SizedBox(height: 2),
        Text(
          '₱${value.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: valueColor ?? const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}

class _TransactionTypeStyle {
  final Color color;
  final Color bgColor;
  final IconData icon;

  const _TransactionTypeStyle({
    required this.color,
    required this.bgColor,
    required this.icon,
  });
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

class _StatusStyle {
  final Color color;
  final Color bgColor;

  const _StatusStyle({required this.color, required this.bgColor});
}

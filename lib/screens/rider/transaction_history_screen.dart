import 'package:flutter/material.dart';

import '../../models/rider_transaction.dart';
import '../../services/rider_transaction_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

import '../../widgets/common/icon_badge.dart';
import '../../widgets/common/status_chip.dart';

import 'package:intl/intl.dart';

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
      appBar: AppBar(title: const Text('Transaction History')),
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
                onPressed: _loadTransactions,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_transactions.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadTransactions,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 180),
            Center(
              child: IconBadge(
                icon: Icons.receipt_long_outlined,
                color: AppColors.textSecondary,
                size: AppSizes.largeIconSize,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Text(
                'No transaction history found.',
                style: AppTextStyles.title,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
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
      return DateFormat('MMMM d, yyyy • h:mm a').format(dateTime);
    } catch (_) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.customerName,
                        style: AppTextStyles.title,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        transaction.customerAddress,
                        style: AppTextStyles.bodySecondary,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: AppSpacing.sm),

                StatusChip(
                  label: transaction.transactionType,
                  color: transactionTypeColor(transaction.transactionType),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            const Divider(),

            const SizedBox(height: AppSpacing.xs),

            Row(
              children: [
                Icon(
                  Icons.water_drop_outlined,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${transaction.bottleType} × ${transaction.quantity}',
                  style: AppTextStyles.body,
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.sm),

            Row(
              children: [
                Expanded(
                  child: _AmountBlock(
                    label: 'Total',
                    value: transaction.totalAmount,
                  ),
                ),
                Expanded(
                  child: _AmountBlock(
                    label: 'Paid',
                    value: transaction.paidAmount,
                  ),
                ),
                Expanded(
                  child: _AmountBlock(
                    label: 'Balance',
                    value: transaction.balance,
                    valueColor: transaction.balance > 0
                        ? AppColors.error
                        : null,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.sm),

            Row(
              children: [
                StatusChip(
                  label: transaction.paymentStatus,
                  color: paymentStatusColor(transaction.paymentStatus),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _formatDateTime(transaction.dateTime),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySecondary,
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
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: 2),
        Text(
          '₱${value.toStringAsFixed(2)}',
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

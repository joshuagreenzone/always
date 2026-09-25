import 'package:flutter/material.dart';

import '../../models/rider_transaction.dart';
import '../../services/rider_transaction_service.dart';

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
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
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
          children: const [
            SizedBox(height: 200),
            Center(child: Text('No transaction history found.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTransactions,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _transactions.length,
        itemBuilder: (context, index) {
          final transaction = _transactions[index];

          return _TransactionCard(transaction: transaction);
        },
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final RiderTransaction transaction;

  //format date time
  String _formatDateTime(String value) {
    try {
      final dateTime = DateTime.parse(value);

      return DateFormat('MMMM d, yyyy • h:mm a').format(dateTime);
    } catch (_) {
      return value;
    }
  }

  const _TransactionCard({required this.transaction});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    transaction.customerName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildTypeLabel(),
              ],
            ),

            const SizedBox(height: 8),

            Text(transaction.customerAddress),

            const SizedBox(height: 12),

            Text('${transaction.bottleType} × ${transaction.quantity}'),

            const SizedBox(height: 8),

            Text('Total: ₱${transaction.totalAmount.toStringAsFixed(2)}'),

            Text('Paid: ₱${transaction.paidAmount.toStringAsFixed(2)}'),

            Text('Balance: ₱${transaction.balance.toStringAsFixed(2)}'),

            const SizedBox(height: 8),

            Text(
              transaction.paymentStatus,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Text(
              _formatDateTime(transaction.dateTime),
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeLabel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      child: Text(
        transaction.transactionType,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

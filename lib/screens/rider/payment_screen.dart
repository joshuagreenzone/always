import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/account.dart';
import '../../models/order_details.dart';
import '../../services/rider_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

class PaymentScreen extends StatefulWidget {
  final Account account;
  final OrderDetails order;
  final List<Map<String, dynamic>> scannedBottles;
  final RiderService? riderService;

  const PaymentScreen({
    super.key,
    required this.account,
    required this.order,
    required this.scannedBottles,
    this.riderService,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late final RiderService _riderService = widget.riderService ?? RiderService();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _amountController = TextEditingController();

  final TextEditingController _notesController = TextEditingController();

  String _paymentType = 'CASH';
  File? _receiptImage;
  bool _isProcessing = false;
  bool _finished = false;
  bool _loadingBalance = true;
  double? _remainingBalance;
  String? _balanceError;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    setState(() {
      _loadingBalance = true;
      _balanceError = null;
    });
    try {
      final order = await _riderService.getOrderDetails(
        orderId: widget.order.orderId,
        accId: widget.account.accId,
      );
      final balance = order.outstandingAmount;
      if (balance == null || !balance.isFinite || balance < 0) {
        throw Exception('Remaining balance is unavailable. Please try again.');
      }
      if (!mounted) return;
      setState(() {
        _remainingBalance = balance;
        _amountController.text = balance.toStringAsFixed(2);
      });
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _balanceError = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingBalance = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _takeReceiptPhoto() async {
    if (_isProcessing) return;

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (image == null || !mounted) return;

      setState(() {
        _receiptImage = File(image.path);
      });
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Unable to Open Camera',
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _submitPayment() async {
    if (_isProcessing ||
        _finished ||
        _loadingBalance ||
        _remainingBalance == null) {
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());

    if (amount == null || !amount.isFinite || amount <= 0) {
      _showMessage('Invalid Amount', 'Please enter a valid payment amount.');
      return;
    }

    if (amount > _remainingBalance!) {
      await _showMessage(
        'Invalid Amount',
        'Payment exceeds the remaining balance.',
      );
      return;
    }

    if (_paymentType != 'CASH' && _receiptImage == null) {
      _showMessage(
        'Receipt Required',
        'Please take a picture of the payment receipt.',
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final result = await _riderService.createPayment(
        accId: widget.account.accId,
        orderId: widget.order.orderId,
        paymentAmount: amount,
        paymentType: _paymentType,
        receiptImage: _receiptImage,
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;

      await _showPaymentSuccess(result);
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Payment Failed',
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _skipPayment() async {
    if (_isProcessing || _finished) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Skip Payment?'),
        content: const Text(
          'No payment will be recorded. '
          'The delivered bottles may remain unpaid or outstanding. '
          'The delivery has already been submitted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final isPartial = widget.scannedBottles.length < widget.order.totalQuantity;
    await _showMessage(
      isPartial ? 'Partial Delivery Saved' : 'Delivery Completed',
      'Order #${widget.order.orderId} ${isPartial ? 'partial delivery was recorded' : 'was delivered'} '
      'successfully. No payment was received. Any outstanding balance remains due.',
    );

    if (!mounted) return;
    await _finishAndReturn();
  }

  Future<void> _showPaymentSuccess(Map<String, dynamic> result) async {
    final paidAmount = double.tryParse('${result['paidAmount'] ?? 0}') ?? 0;

    final outstanding =
        double.tryParse('${result['outstandingAmount'] ?? 0}') ?? 0;

    final status = '${result['paymentStatus'] ?? 'UNKNOWN'}';

    final paymentId = result['paymentId'];

    final shouldFinish = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Payment Recorded'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Icon(
                Icons.check_circle,
                size: 56,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Payment received by ${widget.account.accName}.',
              style: AppTextStyles.body,
            ),
            if (paymentId != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Payment reference: $paymentId',
                style: AppTextStyles.bodySecondary,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(
              'Paid: ₱${paidAmount.toStringAsFixed(2)}',
              style: AppTextStyles.body,
            ),
            Text(
              'Outstanding: ₱${outstanding.toStringAsFixed(2)}',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Status: $status', style: AppTextStyles.dashboardTitle),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Done'),
          ),
        ],
      ),
    );

    if (shouldFinish == true && mounted) {
      await _finishAndReturn();
    }
  }

  Future<void> _finishAndReturn() async {
    if (!mounted || _finished) return;

    _finished = true;

    // Do not call completeDelivery() here.
    // DeliveryConfirmationScreen already committed the delivery.
    //
    // Return to the root screen so the rider does not accidentally
    // submit the same delivery again by navigating backwards.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _showMessage(String title, String message) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // This is the original order total for display only.
    // The API must calculate the payable total using confirmed
    // delivered bottles, especially for incomplete deliveries.
    final total = widget.order.totalAmount;

    return PopScope(
      canPop: !_isProcessing,
      child: Scaffold(
        appBar: AppBar(title: const Text('Receive Payment'), centerTitle: true),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.screenPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOrderSummary(total),
                const SizedBox(height: AppSpacing.md),
                _buildReceiverCard(),
                const SizedBox(height: AppSpacing.md),
                _buildPaymentForm(),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        _isProcessing ||
                            _finished ||
                            _loadingBalance ||
                            _balanceError != null ||
                            (_remainingBalance ?? 0) <= 0
                        ? null
                        : _submitPayment,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.payments_outlined),
                    label: Text(
                      _isProcessing ? 'Recording Payment...' : 'Record Payment',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isProcessing || _finished ? null : _skipPayment,
                    child: const Text('No Payment Received'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderSummary(double total) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Order Payment', style: AppTextStyles.sectionTitle),
            const SizedBox(height: AppSpacing.md),
            Text('Order #${widget.order.orderId}', style: AppTextStyles.body),
            const SizedBox(height: AppSpacing.xs),
            Text(widget.order.customerName, style: AppTextStyles.bodySecondary),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Original Order Total',
                    style: AppTextStyles.body,
                  ),
                ),
                Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: AppTextStyles.dashboardTitle,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Remaining Balance',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  if (_loadingBalance)
                    const LinearProgressIndicator()
                  else if (_balanceError != null) ...[
                    Text(_balanceError!),
                    TextButton(
                      onPressed: _loadBalance,
                      child: const Text('Retry'),
                    ),
                  ] else
                    Text(
                      '\u20b1${_remainingBalance!.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${widget.scannedBottles.length} bottle(s) '
              'were submitted for delivery.',
              style: AppTextStyles.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'The server validates the payable amount against '
              'confirmed delivered bottles.',
              style: AppTextStyles.bodySecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiverCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Row(
          children: [
            const Icon(Icons.account_circle_outlined, size: 40),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Payment Received By',
                    style: AppTextStyles.bodySecondary,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    widget.account.accName,
                    style: AppTextStyles.dashboardTitle,
                  ),
                  Text(
                    widget.account.accType,
                    style: AppTextStyles.bodySecondary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Payment Details', style: AppTextStyles.sectionTitle),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amountController,
              enabled:
                  !_isProcessing && !_loadingBalance && _balanceError == null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Payment Amount',
                prefixText: '₱ ',
                hintText: 'Enter amount',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              value: _paymentType,
              decoration: const InputDecoration(labelText: 'Payment Method'),
              items: const [
                DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                DropdownMenuItem(value: 'GCASH', child: Text('GCash')),
                DropdownMenuItem(
                  value: 'BANK_TRANSFER',
                  child: Text('Bank Transfer'),
                ),
              ],
              onChanged: _isProcessing
                  ? null
                  : (value) {
                      if (value == null) return;

                      setState(() {
                        _paymentType = value;
                        _receiptImage = null;
                      });
                    },
            ),
            if (_paymentType != 'CASH') ...[
              const SizedBox(height: AppSpacing.md),
              _buildReceiptSection(),
            ],
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _notesController,
              enabled: !_isProcessing,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes (Optional)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Payment Receipt', style: AppTextStyles.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Take a picture of the payment receipt or transaction confirmation.',
          style: AppTextStyles.bodySecondary,
        ),
        const SizedBox(height: AppSpacing.md),
        if (_receiptImage != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            child: Image.file(
              _receiptImage!,
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
            ),
          ),
        if (_receiptImage != null) const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isProcessing ? null : _takeReceiptPhoto,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(
              _receiptImage == null
                  ? 'Take Receipt Photo'
                  : 'Retake Receipt Photo',
            ),
          ),
        ),
      ],
    );
  }
}

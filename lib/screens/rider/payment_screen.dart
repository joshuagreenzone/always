import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/account.dart';
import '../../models/order_details.dart';
import '../../services/rider_service.dart';
import '../../theme/app_colors.dart';

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
              'Paid: â‚±${paidAmount.toStringAsFixed(2)}',
              style: AppTextStyles.body,
            ),
            Text(
              'Outstanding: â‚±${outstanding.toStringAsFixed(2)}',
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
    const blue = Color(0xFF087DA9);
    final canPay =
        !_isProcessing &&
        !_finished &&
        !_loadingBalance &&
        _balanceError == null &&
        (_remainingBalance ?? 0) > 0;
    return PopScope(
      canPop: !_isProcessing,
      child: Scaffold(
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
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
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
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order #${widget.order.orderId}',
                              style: const TextStyle(
                                color: Color(0xFFB8E6F5),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Collect payment',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Amount due',
                              style: TextStyle(
                                color: Color(0xFFB8E6F5),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (_loadingBalance)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: SizedBox(
                                  width: 120,
                                  child: LinearProgressIndicator(
                                    color: Colors.white,
                                    backgroundColor: Color(0xFF438EAC),
                                  ),
                                ),
                              )
                            else
                              Text(
                                _balanceError != null
                                    ? 'Unavailable'
                                    : '₱${_remainingBalance!.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_balanceError != null) ...[
                      Text(
                        _balanceError!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _isProcessing ? null : _loadBalance,
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                    _label('Payment method'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _method('Cash', 'CASH')),
                        const SizedBox(width: 8),
                        Expanded(child: _method('GCash', 'GCASH')),
                        const SizedBox(width: 8),
                        Expanded(child: _method('Bank', 'BANK_TRANSFER')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _label('Amount received (₱)'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _amountController,
                      enabled:
                          !_isProcessing &&
                          !_loadingBalance &&
                          _balanceError == null,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _input('Enter amount'),
                    ),
                    const SizedBox(height: 16),
                    _label('Note (optional)'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesController,
                      enabled: !_isProcessing,
                      minLines: 1,
                      maxLines: 3,
                      decoration: _input('Add a note'),
                    ),
                    const SizedBox(height: 14),
                    if (_receiptImage != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          _receiptImage!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    CustomPaint(
                      painter: _ReceiptBorderPainter(),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _isProcessing ? null : _takeReceiptPhoto,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 22,
                              horizontal: 12,
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.camera_alt_outlined,
                                  color: blue,
                                  size: 24,
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  _receiptImage == null
                                      ? 'Add receipt photo'
                                      : 'Retake receipt photo',
                                  style: const TextStyle(
                                    color: blue,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                if (_paymentType != 'CASH') ...[
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Required for this payment method',
                                    style: TextStyle(
                                      color: Color(0xFF71869A),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        elevation: 3,
                        shadowColor: blue.withValues(alpha: .3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: canPay ? _submitPayment : null,
                      child: Text(
                        _isProcessing ? 'Saving payment...' : 'Save payment',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: blue,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: blue),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isProcessing || _finished
                          ? null
                          : _skipPayment,
                      child: const Text(
                        'Continue without payment',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF506C80),
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
  );

  InputDecoration _input(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD7E7F0)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD7E7F0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF087DA9), width: 1.5),
    ),
  );

  Widget _method(String label, String value) {
    final selected = _paymentType == value;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: selected ? const Color(0xFF087DA9) : Colors.white,
        foregroundColor: selected ? Colors.white : const Color(0xFF102B40),
        minimumSize: const Size.fromHeight(44),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? Colors.transparent : const Color(0xFFD7E7F0),
          ),
        ),
      ),
      onPressed: _isProcessing || _finished
          ? null
          : () => setState(() {
              _paymentType = value;
            }),
      child: Text(label),
    );
  }
}

class _ReceiptBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    canvas.drawRRect(rect, Paint()..color = Colors.white);
    final path = Path()..addRRect(rect);
    final paint = Paint()
      ..color = const Color(0xFF73BADD)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (double distance = 0; distance < metric.length; distance += 9) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ReceiptBorderPainter oldDelegate) => false;
}

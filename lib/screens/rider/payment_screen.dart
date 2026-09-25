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

  const PaymentScreen({super.key, required this.account, required this.order});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final RiderService _riderService = RiderService();

  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _amountController = TextEditingController();

  final TextEditingController _notesController = TextEditingController();

  String _paymentType = 'CASH';

  File? _receiptImage;

  bool _isProcessing = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _takeReceiptPhoto() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (image == null) {
      return;
    }

    setState(() {
      _receiptImage = File(image.path);
    });
  }

  Future<void> _submitPayment() async {
    final amount = double.tryParse(_amountController.text.trim());

    if (amount == null || amount <= 0) {
      _showMessage('Invalid Amount', 'Please enter a valid payment amount.');
      return;
    }

    if (amount > widget.order.totalAmount) {
      _showMessage('Invalid Amount', 'Payment cannot exceed the order total.');
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

      if (!mounted) {
        return;
      }

      await _showPaymentSuccess(result);
    } catch (e) {
      if (!mounted) {
        return;
      }

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Skip Payment?'),
          content: const Text(
            'No payment will be recorded. '
            'The order will remain unpaid or outstanding.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _completeDelivery();
  }

  Future<void> _completeDelivery() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      await _riderService.completeDelivery(
        accId: widget.account.accId,
        orderId: widget.order.orderId,
        deliveryId: widget.order.deliveryId,
      );

      if (!mounted) {
        return;
      }

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) {
          return AlertDialog(
            title: const Text('Delivery Completed'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 64, color: AppColors.success),
                SizedBox(height: 16),
                Text(
                  'The delivery has been completed successfully.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);

                  /*
                   * Return all the way to Assigned Orders.
                   */
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
                child: const Text('Done'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Delivery Failed',
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

  Future<void> _showPaymentSuccess(Map<String, dynamic> result) async {
    final paidAmount = double.tryParse(result['paidAmount'].toString()) ?? 0;

    final outstanding =
        double.tryParse(result['outstandingAmount'].toString()) ?? 0;

    final status = result['paymentStatus'].toString();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
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
                'Payment received by '
                '${widget.account.accName}.',
                style: AppTextStyles.body,
              ),

              const SizedBox(height: AppSpacing.md),

              Text(
                'Paid: '
                '₱${paidAmount.toStringAsFixed(2)}',
                style: AppTextStyles.body,
              ),

              Text(
                'Outstanding: '
                '₱${outstanding.toStringAsFixed(2)}',
                style: AppTextStyles.body,
              ),

              const SizedBox(height: AppSpacing.sm),

              Text('Status: $status', style: AppTextStyles.dashboardTitle),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Complete Delivery'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    await _completeDelivery();
  }

  void _showMessage(String title, String message) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.order.totalAmount;

    return Scaffold(
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
                  onPressed: _isProcessing ? null : _submitPayment,
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
                  onPressed: _isProcessing ? null : _skipPayment,
                  child: const Text('No Payment Received'),
                ),
              ),
            ],
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
                  child: Text('Order Total', style: AppTextStyles.body),
                ),
                Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: AppTextStyles.dashboardTitle,
                ),
              ],
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
              initialValue: _paymentType,
              decoration: const InputDecoration(labelText: 'Payment Method'),
              items: const [
                DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                DropdownMenuItem(value: 'GCASH', child: Text('GCash')),
                DropdownMenuItem(
                  value: 'BANK_TRANSFER',
                  child: Text('Bank Transfer'),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }

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
            onPressed: _takeReceiptPhoto,
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

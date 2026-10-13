import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/batch_scan_location.dart';
import '../../widgets/common/bottle_scanner_view.dart';
import '../../widgets/common/rider_scan_card.dart';

import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/account.dart';
import '../../models/pickup_order.dart';
import '../../services/rider_service.dart';
import '../../widgets/common/bottle_condition_dialog.dart';

import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

class _PendingPickupBottle {
  final String bottleNumber;
  final double latitude;
  final double longitude;
  final double accuracy;

  _PendingPickupBottle({
    required this.bottleNumber,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });
}

class PickupScanScreen extends StatefulWidget {
  final Account account;
  final PickupOrder order;

  const PickupScanScreen({
    super.key,
    required this.account,
    required this.order,
  });

  @override
  State<PickupScanScreen> createState() => _PickupScanScreenState();
}

class _PickupScanScreenState extends State<PickupScanScreen> {
  final MobileScannerController _scannerController =
      createBottleScannerController();
  final RiderService _riderService = RiderService();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _paymentAmountController =
      TextEditingController();
  final TextEditingController _paymentNotesController = TextEditingController();

  File? _receiptImage;
  String _paymentType = 'CASH';
  final _batchLocation = BatchScanLocation();
  String? _scanMessage;
  bool _scanSuccess = true;
  bool _isProcessing = false;

  late int _alreadyPickedUpCount;
  final List<_PendingPickupBottle> _scannedBottles = [];

  @override
  void initState() {
    super.initState();
    _alreadyPickedUpCount = widget.order.pickedUpBottleCount;

    if (_alreadyPickedUpCount < 0) {
      _alreadyPickedUpCount = 0;
    }

    if (_alreadyPickedUpCount > widget.order.deliveredBottleCount) {
      _alreadyPickedUpCount = widget.order.deliveredBottleCount;
    }
  }

  @override
  void dispose() {
    _paymentAmountController.dispose();
    _paymentNotesController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  int get _remainingBottleCount {
    final remaining =
        widget.order.deliveredBottleCount -
        _alreadyPickedUpCount -
        _scannedBottles.length;

    return remaining < 0 ? 0 : remaining;
  }

  int get _currentPickedUpCount {
    return _alreadyPickedUpCount + _scannedBottles.length;
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_isProcessing ||
        _remainingBottleCount <= 0 ||
        capture.barcodes.isEmpty) {
      return;
    }

    final value = capture.barcodes.first.rawValue;

    if (value == null || value.trim().isEmpty) {
      return;
    }

    await _processBottle(value.trim());
  }

  Future<void> _processBottle(String bottleNumber) async {
    if (_isProcessing || _remainingBottleCount <= 0) return;
    if (_scannedBottles.any(
      (b) => b.bottleNumber.toLowerCase() == bottleNumber.toLowerCase(),
    )) {
      return;
    }
    setState(() {
      _isProcessing = true;
      _scanMessage = null;
    });
    try {
      final ready = await checkBottleConditionForScan(
        context: context,
        accId: widget.account.accId,
        bottleNumber: bottleNumber,
        allowDamagedPickup: true,
      );
      if (!mounted) return;
      if (!ready) {
        setState(() {
          _scanSuccess = false;
          _scanMessage = 'Bottle not added';
        });
        return;
      }

      final position = await _batchLocation.get();
      if (!mounted) return;
      setState(() {
        _scannedBottles.add(
          _PendingPickupBottle(
            bottleNumber: bottleNumber,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
          ),
        );
        _scanSuccess = true;
        _scanMessage = 'Scanned\n$bottleNumber';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanSuccess = false;
          _scanMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _takeReceiptPhoto(StateSetter setDialogState) async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (image == null) return;

    setDialogState(() {
      _receiptImage = File(image.path);
    });
  }

  Future<void> _completePickup() async {
    if (_scannedBottles.isEmpty || _isProcessing) return;

    setState(() => _isProcessing = true);
    final confirmed = await _showPickupConfirmation();
    if (mounted) setState(() => _isProcessing = false);

    if (confirmed != true || !mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await _scannerController.stop();
    } catch (_) {}

    try {
      final result = await _riderService.completePickup(
        accId: widget.account.accId,
        orderId: widget.order.orderId,
        deliveryId: widget.order.deliveryId,
        bottles: _scannedBottles
            .map(
              (item) => {
                'bottleNumber': item.bottleNumber,
                'latitude': item.latitude,
                'longitude': item.longitude,
                'accuracy': item.accuracy,
              },
            )
            .toList(),
      );

      if (!mounted) return;

      final delivered = _toInt(
        result['deliveredCount'],
        fallback: widget.order.deliveredBottleCount,
      );

      final pickedUp = _toInt(
        result['pickedUpCount'],
        fallback: _currentPickedUpCount,
      );

      final remaining = _toInt(
        result['remainingCount'],
        fallback: delivered - pickedUp,
      );

      final paymentStatus =
          result['paymentStatus']?.toString().toUpperCase() ?? 'UNPAID';

      final outstandingAmount = _toDouble(result['outstandingAmount']);

      _alreadyPickedUpCount = pickedUp;
      _scannedBottles.clear();
      _batchLocation.clear();

      setState(() {
        _isProcessing = false;
      });

      if (remaining > 0) {
        await _showMessage(
          'Partial Pickup Completed',
          '$pickedUp of $delivered bottles from Order #${widget.order.orderId} have been picked up.\n\n'
              '$remaining bottle${remaining == 1 ? '' : 's'} remain to be picked up later.',
        );
      } else {
        await _showMessage(
          'Pickup Completed',
          'All $delivered bottles from Order #${widget.order.orderId} have been picked up successfully.',
        );
      }

      if (!mounted) return;

      if ((paymentStatus == 'UNPAID' || paymentStatus == 'PARTIALLY_PAID') &&
          outstandingAmount > 0) {
        final paymentMade = await _showPaymentDialog(outstandingAmount);

        if (!mounted) return;

        if (paymentMade) {
          Navigator.pop(context, true);
          return;
        }

        await _showMessage(
          'Payment Not Collected',
          'The pickup was completed successfully.\n\n'
              'Outstanding balance: ₱${outstandingAmount.toStringAsFixed(2)}',
        );
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isProcessing = false;
      });

      String message = e.toString();
      if (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      }

      await _showMessage('Unable to Complete Pickup', message);

      if (!mounted) return;

      if (_scannedBottles.isNotEmpty) {
        await _scannerController.start();
      }
    }
  }

  Future<bool?> _showPickupConfirmation() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        final count = _scannedBottles.length;
        final afterPickupCount = _currentPickedUpCount;
        final delivered = widget.order.deliveredBottleCount;

        return AlertDialog(
          title: const Text('Confirm Pickup'),
          content: Text(
            'You are about to record $count bottle${count == 1 ? '' : 's'} as picked up.\n\n'
            'Pickup progress will become $afterPickupCount / $delivered.\n\n'
            'The scanned bottles will be saved to the database.\n\n'
            'Continue?',
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
        );
      },
    );
  }

  Future<bool> _showPaymentDialog(double outstandingAmount) async {
    _paymentAmountController.text = outstandingAmount.toStringAsFixed(2);
    _paymentNotesController.clear();
    _receiptImage = null;
    _paymentType = 'CASH';

    bool isSaving = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Collect Payment'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Outstanding Balance',
                      style: AppTextStyles.bodySecondary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱${outstandingAmount.toStringAsFixed(2)}',
                      style: AppTextStyles.dashboardTitle,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _paymentAmountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Payment Amount',
                        prefixText: '₱ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentType,
                      decoration: const InputDecoration(
                        labelText: 'Payment Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                        DropdownMenuItem(value: 'GCASH', child: Text('GCash')),
                        DropdownMenuItem(
                          value: 'BANK_TRANSFER',
                          child: Text('Bank Transfer'),
                        ),
                      ],
                      onChanged: isSaving
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() {
                                _paymentType = value;
                                _receiptImage = null;
                              });
                            },
                    ),
                    if (_paymentType != 'CASH') ...[
                      const SizedBox(height: 16),
                      _buildReceiptSection(setDialogState, isSaving),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: _paymentNotesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notes (Optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'You may collect the full balance or a partial payment.',
                      style: AppTextStyles.bodySecondary,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The server will reject any amount greater than the actual outstanding balance.',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(context, false),
                  child: const Text('Skip'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final amount = double.tryParse(
                            _paymentAmountController.text.trim(),
                          );

                          if (amount == null || amount <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Enter a valid payment amount.'),
                              ),
                            );
                            return;
                          }

                          if (amount > outstandingAmount) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Payment cannot exceed ₱${outstandingAmount.toStringAsFixed(2)}.',
                                ),
                              ),
                            );
                            return;
                          }

                          if (_paymentType != 'CASH' && _receiptImage == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please take a picture of the payment receipt.',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                          });

                          try {
                            await _riderService.createPayment(
                              accId: widget.account.accId,
                              orderId: widget.order.orderId,
                              paymentAmount: amount,
                              paymentType: _paymentType,
                              receiptImage: _receiptImage,
                              notes: _paymentNotesController.text.trim(),
                            );

                            if (!context.mounted) return;

                            Navigator.pop(context, true);
                          } catch (e) {
                            if (!context.mounted) return;

                            String message = e.toString();
                            if (message.startsWith('Exception: ')) {
                              message = message.substring('Exception: '.length);
                            }

                            setDialogState(() {
                              isSaving = false;
                            });

                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(message)));
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Receive Payment'),
                ),
              ],
            );
          },
        );
      },
    );

    return result == true;
  }

  Widget _buildReceiptSection(StateSetter setDialogState, bool isSaving) {
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
            onPressed: isSaving
                ? null
                : () async {
                    await _takeReceiptPhoto(setDialogState);
                  },
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

  Future<void> _handleBack() async {
    if (_scannedBottles.isEmpty) {
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }

    setState(() => _isProcessing = true);
    final discard = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: const Text('Discard Scanned Bottles?'),
          content: Text(
            '${_scannedBottles.length} bottle${_scannedBottles.length == 1 ? '' : 's'} have been scanned but not saved.\n\n'
            'If you leave this screen, these scans will be discarded.\n\n'
            'No database transaction has been created for these scans.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );

    if (mounted) setState(() => _isProcessing = false);
    if (discard == true && mounted) {
      _scannedBottles.clear();
      _batchLocation.clear();
      Navigator.pop(context);
    }
  }

  Future<void> _showMessage(String title, String message) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  int _toInt(dynamic value, {required int fallback}) {
    if (value == null) return fallback;
    return int.tryParse(value.toString()) ?? fallback;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    return double.tryParse(value.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final required = widget.order.deliveredBottleCount;
    final scanned = _scannedBottles.length;
    final completed = _currentPickedUpCount;
    final remaining = (required - completed).clamp(0, required);
    final busy = _isProcessing;
    final canConfirm = scanned > 0 && !busy;

    return PopScope(
      canPop: !busy && _scannedBottles.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || busy) return;
        await _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Pickup #${widget.order.orderId}'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: busy ? null : _handleBack,
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RiderScanCard(
                  children: [
                    Text(
                      'Order #${widget.order.orderId}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.order.customerName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (widget.order.bottleTypes.isEmpty)
                      Text('Bottles × $required'),
                    ...widget.order.bottleTypes.map(
                      (item) => Text(
                        '${item.bottleType} × ${item.deliveredBottleCount}',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Bottles picked up: $completed / $required',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: required <= 0
                          ? 0
                          : (completed / required).clamp(0.0, 1.0),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      remaining == 0
                          ? 'All bottles scanned'
                          : '$remaining remaining · Partial pickup allowed',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                RiderScanCard(
                  children: [
                    Text(
                      'Scan Bottles',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 320,
                        child: BottleScannerView(
                          controller: _scannerController,
                          onDetect: _handleScan,
                          enabled: !busy && remaining > 0,
                          busy: busy,
                          message: _scanMessage,
                          success: _scanSuccess,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Point the camera at one bottle QR code at a time.',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                PendingBottleList(
                  title: 'Bottles to Pick Up',
                  bottles: _scannedBottles.map((b) => b.bottleNumber).toList(),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: canConfirm ? _completePickup : null,
            icon: const Icon(Icons.check_circle_outline),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                busy ? 'Please wait...' : 'Confirm Pickup ($scanned)',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

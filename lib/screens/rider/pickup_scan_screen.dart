import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/account.dart';
import '../../models/pickup_order.dart';
import '../../services/rider_service.dart';
import '../../theme/app_colors.dart';
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
  final MobileScannerController _scannerController = MobileScannerController();
  final RiderService _riderService = RiderService();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _paymentAmountController =
      TextEditingController();
  final TextEditingController _paymentNotesController = TextEditingController();

  File? _receiptImage;
  String _paymentType = 'CASH';
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

  Future<Position> _getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception(
        'Location services are turned off. Please enable GPS and try again.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        throw Exception('Location permission was denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. Please enable it from app settings.',
      );
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _processBottle(String bottleNumber) async {
    if (_isProcessing || _remainingBottleCount <= 0) {
      return;
    }

    final alreadyScanned = _scannedBottles.any(
      (item) => item.bottleNumber.toLowerCase() == bottleNumber.toLowerCase(),
    );

    if (alreadyScanned) {
      await _showMessage(
        'Already Scanned',
        'Bottle $bottleNumber has already been scanned for this pickup.',
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await _scannerController.stop();
    } catch (_) {}

    try {
      final position = await _getCurrentLocation();

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
        _isProcessing = false;
      });

      final delivered = widget.order.deliveredBottleCount;
      final totalPickedUp = _currentPickedUpCount;
      final remaining = _remainingBottleCount;

      await _showMessage(
        'Bottle Scanned',
        'Bottle: $bottleNumber\n\n'
            'Picked up: $totalPickedUp / $delivered\n'
            'Remaining: $remaining\n\n'
            'This bottle has NOT been saved yet.\n'
            'Press Complete Pickup to confirm the scanned bottles.',
      );

      if (!mounted) return;

      if (_remainingBottleCount > 0) {
        await _scannerController.start();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isProcessing = false;
      });

      String message = e.toString();
      if (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      }

      await _showMessage('Unable to Scan Bottle', message);

      if (!mounted) return;

      if (_remainingBottleCount > 0) {
        await _scannerController.start();
      }
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

    final confirmed = await _showPickupConfirmation();

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

    if (discard == true && mounted) {
      _scannedBottles.clear();
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
    final pickedUp = _currentPickedUpCount;
    final remaining = _remainingBottleCount;
    final canComplete = _scannedBottles.isNotEmpty && !_isProcessing;
    final allScanned = required > 0 && pickedUp >= required;

    return PopScope(
      canPop: !_isProcessing && _scannedBottles.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isProcessing) return;
        await _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Pickup #${widget.order.orderId}'),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _isProcessing ? null : _handleBack,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Top compact summary.
              // This follows the same structure as DeliveryScanScreen.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.screenPadding,
                  8,
                  AppSizes.screenPadding,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.order.customerName,
                      style: AppTextStyles.screenTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${widget.order.bottleType} × $required',
                      style: AppTextStyles.bodySecondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        const Expanded(child: Text('Bottles picked up')),
                        Text(
                          '$pickedUp / $required',
                          style: AppTextStyles.dashboardTitle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: required <= 0
                          ? 0
                          : (pickedUp / required).clamp(0.0, 1.0),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      allScanned
                          ? 'All delivered bottles picked up'
                          : '$remaining remaining · Partial pickup allowed',
                      style: AppTextStyles.bodySecondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Scanner view fills the remaining flexible space.
              Expanded(
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.center,
                    children: [
                      MobileScanner(
                        controller: _scannerController,
                        onDetect: _handleScan,
                      ),

                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 3),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),

                      if (_isProcessing)
                        Container(
                          color: Colors.black45,
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 16),
                              Text(
                                'Processing...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Bottom persistent bar.
              // This follows the same compact structure as DeliveryScanScreen.
              Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_scannedBottles.isNotEmpty)
                      SizedBox(
                        height: 58,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.screenPadding,
                          ),
                          scrollDirection: Axis.horizontal,
                          itemCount: _scannedBottles.length,
                          itemBuilder: (_, index) {
                            final bottle = _scannedBottles[index];

                            return Container(
                              margin: const EdgeInsets.only(
                                right: AppSpacing.sm,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.success),
                                borderRadius: BorderRadius.circular(
                                  AppSizes.cardRadius,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    color: AppColors.success,
                                    size: 18,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    bottle.bottleNumber,
                                    style: AppTextStyles.body,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSizes.screenPadding,
                        6,
                        AppSizes.screenPadding,
                        4,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: canComplete ? _completePickup : null,
                          child: Text(
                            _scannedBottles.isEmpty
                                ? 'Scan at Least One Bottle'
                                : allScanned
                                ? 'Complete Pickup'
                                : 'Complete Pickup with '
                                      '${_scannedBottles.length} Bottle'
                                      '${_scannedBottles.length == 1 ? '' : 's'}',
                          ),
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
    );
  }
}

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

  /*
   * Number of bottles that were already picked up
   * by previous pickup transactions.
   *
   * This value comes from PickupOrder.pickedUpBottleCount.
   *
   * Example:
   *
   * Delivered = 3
   * Already picked up = 1
   *
   * Remaining = 2
   */
  late int _alreadyPickedUpCount;

  /*
   * Temporary bottles scanned during the current
   * pickup session.
   *
   * These are NOT saved to the database until
   * _completePickup() succeeds.
   */
  final List<_PendingPickupBottle> _scannedBottles = [];

  @override
  void initState() {
    super.initState();

    /*
     * Initialize the cumulative pickup count from
     * the server-provided PickupOrder.
     */
    _alreadyPickedUpCount = widget.order.pickedUpBottleCount;

    /*
     * Protect against an invalid value coming from
     * the API.
     */
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

  /*
   * Number of bottles still needing pickup.
   *
   * This excludes bottles already picked up in
   * previous pickup transactions and bottles
   * temporarily scanned in the current session.
   */
  int get _remainingBottleCount {
    final remaining =
        widget.order.deliveredBottleCount -
        _alreadyPickedUpCount -
        _scannedBottles.length;

    return remaining < 0 ? 0 : remaining;
  }

  /*
   * Total pickup progress including bottles that
   * were picked up previously and bottles scanned
   * during this session.
   */
  int get _currentPickedUpCount {
    return _alreadyPickedUpCount + _scannedBottles.length;
  }

  /*
   * Handles barcode/QR-code detection.
   */
  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_isProcessing) {
      return;
    }

    /*
     * Only allow scanning the bottles that still
     * need to be picked up.
     */
    if (_remainingBottleCount <= 0) {
      return;
    }

    if (capture.barcodes.isEmpty) {
      return;
    }

    final value = capture.barcodes.first.rawValue;

    if (value == null || value.trim().isEmpty) {
      return;
    }

    await _processBottle(value.trim());
  }

  /*
   * Gets the rider's current GPS position.
   */
  Future<Position> _getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception(
        'Location services are turned off. '
        'Please enable GPS and try again.',
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
        'Location permission is permanently denied. '
        'Please enable it from the app settings.',
      );
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /*
   * Processes one scanned bottle.
   *
   * The bottle is stored temporarily and is NOT
   * written to the database until Complete Pickup
   * is confirmed.
   */
  Future<void> _processBottle(String bottleNumber) async {
    if (_isProcessing) {
      return;
    }

    /*
     * Do not scan more bottles than remain.
     */
    if (_remainingBottleCount <= 0) {
      return;
    }

    /*
     * Prevent duplicate bottles in the current
     * temporary scan list.
     */
    final alreadyScanned = _scannedBottles.any(
      (item) => item.bottleNumber.toLowerCase() == bottleNumber.toLowerCase(),
    );

    if (alreadyScanned) {
      await _showMessage(
        'Already Scanned',
        'Bottle $bottleNumber has already been '
            'scanned for this pickup.',
      );

      return;
    }

    setState(() {
      _isProcessing = true;
    });

    /*
     * Stop the scanner while GPS is being obtained.
     */
    try {
      await _scannerController.stop();
    } catch (_) {}

    try {
      final position = await _getCurrentLocation();

      if (!mounted) {
        return;
      }

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
            'Press Complete Pickup to confirm '
            'the scanned bottles.',
      );

      if (!mounted) {
        return;
      }

      /*
       * Resume scanning only when there are still
       * bottles that need to be picked up.
       */
      if (_remainingBottleCount > 0) {
        await _scannerController.start();
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isProcessing = false;
      });

      String message = e.toString();

      if (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      }

      await _showMessage('Unable to Scan Bottle', message);

      if (!mounted) {
        return;
      }

      if (_remainingBottleCount > 0) {
        await _scannerController.start();
      }
    }
  }

  /*
   * Takes a picture of the customer's payment receipt.
   */
  Future<void> _takeReceiptPhoto(StateSetter setDialogState) async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (image == null) {
      return;
    }

    setDialogState(() {
      _receiptImage = File(image.path);
    });
  }

  /*
   * Commits the temporary scanned bottles to the server.
   */
  Future<void> _completePickup() async {
    if (_scannedBottles.isEmpty || _isProcessing) {
      return;
    }

    final confirmed = await _showPickupConfirmation();

    if (confirmed != true || !mounted) {
      return;
    }

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

      if (!mounted) {
        return;
      }

      /*
       * Always use the server-authoritative counts.
       */
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

      /*
       * The server has successfully committed the
       * current pickup transaction.
       *
       * Update our cumulative count before clearing
       * the temporary list.
       */
      _alreadyPickedUpCount = pickedUp;

      _scannedBottles.clear();

      setState(() {
        _isProcessing = false;
      });

      if (remaining > 0) {
        await _showMessage(
          'Partial Pickup Completed',
          '$pickedUp of $delivered bottles from '
              'Order #${widget.order.orderId} '
              'have been picked up.\n\n'
              '$remaining bottle'
              '${remaining == 1 ? '' : 's'} '
              'remain to be picked up later.',
        );
      } else {
        await _showMessage(
          'Pickup Completed',
          'All $delivered bottles from '
              'Order #${widget.order.orderId} '
              'have been picked up successfully.',
        );
      }

      if (!mounted) {
        return;
      }

      /*
       * Payment flow.
       */
      if ((paymentStatus == 'UNPAID' || paymentStatus == 'PARTIALLY_PAID') &&
          outstandingAmount > 0) {
        final paymentMade = await _showPaymentDialog(outstandingAmount);

        if (!mounted) {
          return;
        }

        if (paymentMade) {
          Navigator.pop(context, true);
          return;
        }

        await _showMessage(
          'Payment Not Collected',
          'The pickup was completed successfully.\n\n'
              'Outstanding balance: '
              '₱${outstandingAmount.toStringAsFixed(2)}',
        );
      }

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isProcessing = false;
      });

      String message = e.toString();

      if (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      }

      await _showMessage('Unable to Complete Pickup', message);

      if (!mounted) {
        return;
      }

      if (_scannedBottles.isNotEmpty) {
        await _scannerController.start();
      }
    }
  }

  /*
   * Asks the rider to confirm the pickup.
   */
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
            'You are about to record '
            '$count bottle'
            '${count == 1 ? '' : 's'} '
            'as picked up.\n\n'
            'Pickup progress will become '
            '$afterPickupCount / $delivered.\n\n'
            'The scanned bottles will be saved '
            'to the database.\n\n'
            'Continue?',
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
  }

  /*
   * Displays the payment collection dialog.
   */
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
                              if (value == null) {
                                return;
                              }

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
                      'You may collect the full '
                      'balance or a partial payment.',
                      style: AppTextStyles.bodySecondary,
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'The server will reject any '
                      'amount greater than the '
                      'actual outstanding balance.',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () {
                          Navigator.pop(context, false);
                        },
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
                                  'Payment cannot exceed '
                                  '₱${outstandingAmount.toStringAsFixed(2)}.',
                                ),
                              ),
                            );
                            return;
                          }

                          if (_paymentType != 'CASH' && _receiptImage == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please take a picture '
                                  'of the payment receipt.',
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

                            if (!context.mounted) {
                              return;
                            }

                            Navigator.pop(context, true);
                          } catch (e) {
                            if (!context.mounted) {
                              return;
                            }

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

  /*
   * Builds the payment receipt section.
   */
  Widget _buildReceiptSection(StateSetter setDialogState, bool isSaving) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Payment Receipt', style: AppTextStyles.sectionTitle),

        const SizedBox(height: AppSpacing.xs),

        const Text(
          'Take a picture of the payment receipt '
          'or transaction confirmation.',
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

  /*
   * Handles the Android/system back button and
   * AppBar back button.
   */
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
            '${_scannedBottles.length} bottle'
            '${_scannedBottles.length == 1 ? '' : 's'} '
            'have been scanned but not saved.\n\n'
            'If you leave this screen, these scans '
            'will be discarded and you can scan them '
            'again later.\n\n'
            'No database transaction has been created '
            'for these scans.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Stay'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
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

  /*
   * Displays a standard message dialog.
   */
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

  int _toInt(dynamic value, {required int fallback}) {
    if (value == null) {
      return fallback;
    }

    return int.tryParse(value.toString()) ?? fallback;
  }

  double _toDouble(dynamic value) {
    if (value == null) {
      return 0;
    }

    return double.tryParse(value.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final required = widget.order.deliveredBottleCount;

    /*
     * Previously picked up + currently scanned.
     */
    final pickedUp = _currentPickedUpCount;

    /*
     * Bottles still needing pickup.
     */
    final remaining = _remainingBottleCount;

    /*
     * The rider can complete as soon as at least
     * one new bottle has been scanned.
     */
    final canComplete = _scannedBottles.isNotEmpty && !_isProcessing;

    /*
     * Complete Pickup means the current scan session
     * will bring the cumulative pickup count to the
     * total delivered count.
     */
    final allPickedUp = pickedUp >= required;

    return PopScope(
      canPop: !_isProcessing && _scannedBottles.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }

        if (_isProcessing) {
          return;
        }

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
              /*
               * Order information and cumulative
               * pickup progress.
               */
              Padding(
                padding: const EdgeInsets.all(AppSizes.screenPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.order.customerName,
                      style: AppTextStyles.screenTitle,
                    ),

                    const SizedBox(height: AppSpacing.xs),

                    Text(
                      '${widget.order.bottleType} × $required',
                      style: AppTextStyles.bodySecondary,
                    ),

                    const SizedBox(height: AppSpacing.md),

                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Bottles picked up',
                            style: AppTextStyles.body,
                          ),
                        ),
                        Text(
                          '$pickedUp / $required',
                          style: AppTextStyles.dashboardTitle,
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.xs),

                    Text(
                      'Previously picked up: '
                      '$_alreadyPickedUpCount',
                      style: AppTextStyles.bodySecondary,
                    ),

                    const SizedBox(height: AppSpacing.xs),

                    Text(
                      'Scanning now: '
                      '${_scannedBottles.length}',
                      style: AppTextStyles.bodySecondary,
                    ),

                    const SizedBox(height: AppSpacing.xs),

                    Text(
                      'Remaining: $remaining',
                      style: AppTextStyles.bodySecondary,
                    ),

                    const SizedBox(height: AppSpacing.sm),

                    LinearProgressIndicator(
                      value: required == 0
                          ? 0
                          : (pickedUp / required).clamp(0.0, 1.0),
                    ),
                  ],
                ),
              ),

              /*
               * Barcode/QR scanner.
               */
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: _handleScan,
                    ),

                    Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),

                    if (_isProcessing)
                      Container(
                        color: Colors.black45,
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
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

              /*
               * Temporarily scanned bottles.
               */
              if (_scannedBottles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSizes.screenPadding),
                  child: SizedBox(
                    height: 90,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _scannedBottles.length,
                      itemBuilder: (_, index) {
                        final bottle = _scannedBottles[index];

                        return Container(
                          margin: const EdgeInsets.only(right: AppSpacing.sm),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
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
                              ),
                              const SizedBox(height: 4),
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
                ),

              /*
               * Complete pickup button.
               */
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.screenPadding,
                  0,
                  AppSizes.screenPadding,
                  AppSizes.screenPadding,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canComplete ? _completePickup : null,
                    child: Text(
                      allPickedUp
                          ? 'Complete Pickup'
                          : 'Complete Partial Pickup',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/*
 * Represents a bottle scanned locally but not yet
 * committed to the database.
 */
class _PendingPickupBottle {
  final String bottleNumber;

  final double latitude;

  final double longitude;

  final double accuracy;

  const _PendingPickupBottle({
    required this.bottleNumber,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });
}

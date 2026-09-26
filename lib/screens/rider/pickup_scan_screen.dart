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
  /*
   * Controls the QR/barcode scanner.
   */
  final MobileScannerController _scannerController = MobileScannerController();

  /*
   * Handles communication with the PHP API.
   */
  final RiderService _riderService = RiderService();

  /*
   * Handles taking payment receipt photos.
   */
  final ImagePicker _imagePicker = ImagePicker();

  /*
   * Payment form controllers.
   */
  final TextEditingController _paymentAmountController =
      TextEditingController();

  final TextEditingController _paymentNotesController = TextEditingController();

  /*
   * Stores the receipt image temporarily before
   * the payment is submitted.
   *
   * The image is uploaded only when the rider
   * confirms the payment.
   */
  File? _receiptImage;

  /*
   * Current payment method.
   *
   * Supported values:
   * CASH
   * GCASH
   * BANK_TRANSFER
   */
  String _paymentType = 'CASH';

  /*
   * Prevents multiple operations from happening
   * at the same time.
   */
  bool _isProcessing = false;

  /*
   * IMPORTANT:
   *
   * These bottles are temporary only.
   *
   * Scanning a bottle DOES NOT immediately create:
   *
   * pickup
   * delivery_pickup_transaction
   * bottle_scan_event
   *
   * records.
   *
   * Those records are created only when
   * _completePickup() successfully calls the server.
   */
  final List<_PendingPickupBottle> _scannedBottles = [];

  @override
  void dispose() {
    /*
     * Dispose controllers when this screen is removed.
     */
    _paymentAmountController.dispose();
    _paymentNotesController.dispose();
    _scannerController.dispose();

    super.dispose();
  }

  /*
   * Handles barcode/QR-code detection from the camera.
   *
   * The scanned bottle number is passed to
   * _processBottle(), which obtains the current
   * GPS location and temporarily stores the bottle.
   */
  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_isProcessing) {
      return;
    }

    final required = widget.order.deliveredBottleCount;

    /*
     * Do not allow more bottles to be scanned
     * than were delivered.
     */
    if (_scannedBottles.length >= required) {
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
   *
   * The location is captured at the time the bottle
   * is scanned and temporarily stored with that bottle.
   *
   * The server ultimately stores the location only
   * when the pickup transaction is successfully
   * committed.
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
   * This function:
   *
   * 1. Checks for duplicate scans.
   * 2. Makes sure the rider has not exceeded
   *    the delivered bottle count.
   * 3. Stops the scanner temporarily.
   * 4. Gets the current GPS location.
   * 5. Adds the bottle to the temporary scan list.
   * 6. Does NOT write anything to the database.
   * 7. Restarts the scanner if more bottles
   *    still need to be scanned.
   */
  Future<void> _processBottle(String bottleNumber) async {
    if (_isProcessing) {
      return;
    }

    /*
     * Prevent duplicate bottles in the temporary list.
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

    /*
     * Prevent scanning more bottles than were
     * delivered for this order.
     */
    if (_scannedBottles.length >= widget.order.deliveredBottleCount) {
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
      /*
       * Capture GPS at the time of the bottle scan.
       */
      final position = await _getCurrentLocation();

      if (!mounted) {
        return;
      }

      /*
       * Add the bottle only to the temporary list.
       *
       * Nothing is written to the database yet.
       */
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

      final required = widget.order.deliveredBottleCount;

      final scanned = _scannedBottles.length;

      final remaining = required - scanned;

      /*
       * Inform the rider that the bottle was
       * temporarily scanned.
       */
      await _showMessage(
        'Bottle Scanned',
        'Bottle: $bottleNumber\n\n'
            'Scanned: $scanned / $required\n'
            'Remaining: $remaining\n\n'
            'This bottle has NOT been saved yet.\n'
            'Press Complete Pickup to confirm all '
            'scanned bottles.',
      );

      if (!mounted) {
        return;
      }

      /*
       * If more bottles are required, resume scanning.
       */
      if (remaining > 0) {
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

      /*
       * Resume scanning after a failed scan/GPS
       * operation.
       */
      if (_scannedBottles.length < widget.order.deliveredBottleCount) {
        await _scannerController.start();
      }
    }
  }

  /*
   * Takes a picture of the customer's payment receipt.
   *
   * This is used for GCash and Bank Transfer payments.
   *
   * The image is kept temporarily in _receiptImage
   * until the rider submits the payment.
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

    /*
     * StatefulBuilder owns the payment dialog's state,
     * so update it using setDialogState.
     */
    setDialogState(() {
      _receiptImage = File(image.path);
    });
  }

  /*
   * Commits the temporary scanned bottles to the server.
   *
   * The server performs the complete pickup operation
   * inside ONE database transaction.
   *
   * The server creates:
   *
   * pickup
   * delivery_pickup_transaction
   * bottle_scan_event
   *
   * If any bottle is invalid, the server rolls back
   * the entire transaction.
   *
   * After pickup is successfully committed, this
   * function optionally opens the payment dialog.
   */
  Future<void> _completePickup() async {
    if (_scannedBottles.isEmpty || _isProcessing) {
      return;
    }

    /*
     * Ask the rider to confirm before committing
     * the temporary scans.
     */
    final confirmed = await _showPickupConfirmation();

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    /*
     * Stop scanning while the server transaction
     * is being processed.
     */
    try {
      await _scannerController.stop();
    } catch (_) {}

    try {
      /*
       * Send all temporarily scanned bottles to PHP.
       */
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
       * Use server-authoritative values.
       */
      final delivered = _toInt(
        result['deliveredCount'],
        fallback: widget.order.deliveredBottleCount,
      );

      final pickedUp = _toInt(
        result['pickedUpCount'],
        fallback: _scannedBottles.length,
      );

      final remaining = _toInt(
        result['remainingCount'],
        fallback: delivered - pickedUp,
      );

      final paymentStatus =
          result['paymentStatus']?.toString().toUpperCase() ?? 'UNPAID';

      /*
       * complete_pickup.php returns:
       *
       * outstandingAmount
       *
       * This is the actual balance remaining after
       * previous customer payments.
       */
      final outstandingAmount = _toDouble(result['outstandingAmount']);

      /*
       * The server transaction has committed successfully.
       *
       * The temporary list can now be cleared.
       */
      _scannedBottles.clear();

      setState(() {
        _isProcessing = false;
      });

      /*
       * Inform the rider that the pickup was committed.
       */
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
       * PAYMENT FLOW
       *
       * If the order is already PAID, no payment
       * dialog is necessary.
       *
       * If the order is UNPAID or PARTIALLY_PAID,
       * and there is still an outstanding balance,
       * allow the rider to collect payment.
       */
      if ((paymentStatus == 'UNPAID' || paymentStatus == 'PARTIALLY_PAID') &&
          outstandingAmount > 0) {
        final paymentMade = await _showPaymentDialog(outstandingAmount);

        if (!mounted) {
          return;
        }

        if (paymentMade) {
          /*
           * Pickup and payment have both completed.
           */
          Navigator.pop(context, true);
          return;
        }

        /*
         * Pickup is already complete even if payment
         * was skipped.
         */
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

      /*
       * Return to the previous rider screen.
       */
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) {
        return;
      }

      /*
       * If complete_pickup.php fails, its database
       * transaction rolls back.
       *
       * Therefore, the temporary bottle list is
       * intentionally retained so the rider can retry.
       */
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

      /*
       * Resume scanning if there are still temporary
       * bottles available for retry.
       */
      if (_scannedBottles.isNotEmpty) {
        await _scannerController.start();
      }
    }
  }

  /*
   * Asks the rider to confirm that the temporarily
   * scanned bottles should actually be saved.
   *
   * Returning false means nothing is sent to the server.
   */
  Future<bool?> _showPickupConfirmation() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        final count = _scannedBottles.length;

        return AlertDialog(
          title: const Text('Confirm Pickup'),
          content: Text(
            'You are about to record '
            '$count bottle'
            '${count == 1 ? '' : 's'} '
            'as picked up.\n\n'
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
   *
   * The rider can:
   *
   * - Enter a full payment.
   * - Enter a partial payment.
   * - Select Cash.
   * - Select GCash.
   * - Select Bank Transfer.
   * - Take a receipt photo for non-cash payments.
   * - Skip payment.
   *
   * The actual server also validates the amount against
   * the real outstanding balance.
   */
  Future<bool> _showPaymentDialog(double outstandingAmount) async {
    /*
     * Reset the payment form every time the dialog opens.
     */
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
                    /*
                     * Show the server-provided outstanding
                     * balance.
                     */
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

                    /*
                     * Payment amount.
                     */
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

                    /*
                     * Payment method.
                     */
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

                                /*
                                       * Clear the previous
                                       * receipt when changing
                                       * payment method.
                                       */
                                _receiptImage = null;
                              });
                            },
                    ),

                    /*
                     * Receipt is required for
                     * GCash and Bank Transfer.
                     */
                    if (_paymentType != 'CASH') ...[
                      const SizedBox(height: 16),

                      _buildReceiptSection(setDialogState, isSaving),
                    ],

                    const SizedBox(height: 16),

                    /*
                     * Optional notes.
                     */
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
                /*
                 * Skip payment.
                 *
                 * The pickup remains completed.
                 */
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () {
                          Navigator.pop(context, false);
                        },
                  child: const Text('Skip'),
                ),

                /*
                 * Submit payment.
                 */
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final amount = double.tryParse(
                            _paymentAmountController.text.trim(),
                          );

                          /*
                           * Validate amount.
                           */
                          if (amount == null || amount <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Enter a valid payment amount.'),
                              ),
                            );
                            return;
                          }

                          /*
                           * Do not allow the rider to
                           * enter more than the known
                           * outstanding balance.
                           */
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

                          /*
                           * Non-cash payments require
                           * a receipt image.
                           */
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
                            /*
                             * Send the payment and
                             * optional receipt image.
                             *
                             * RiderService converts this
                             * into multipart/form-data.
                             */
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

                            /*
                             * Payment was successfully
                             * recorded.
                             */
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

    /*
     * Return whether a payment was successfully
     * recorded.
     */
    return result == true;
  }

  /*
   * Builds the receipt-photo section of the payment
   * dialog.
   *
   * For GCash and Bank Transfer:
   *
   * 1. The rider takes a receipt photo.
   * 2. The image is displayed for review.
   * 3. The rider can retake it.
   * 4. The image is uploaded when payment is submitted.
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

        /*
         * Display receipt preview if one exists.
         */
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

        /*
         * Camera button.
         */
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
   * the AppBar back button.
   *
   * If no bottles have been scanned, the screen
   * can be left immediately.
   *
   * If bottles are temporarily scanned, the rider
   * must explicitly confirm that they want to
   * discard those scans.
   *
   * Discarding the scans does NOT affect the database
   * because the scans have not been committed yet.
   */
  Future<void> _handleBack() async {
    /*
     * No pending scans.
     *
     * It is safe to leave immediately.
     */
    if (_scannedBottles.isEmpty) {
      if (mounted) {
        Navigator.pop(context);
      }

      return;
    }

    /*
     * Pending temporary scans exist.
     *
     * Ask the rider before discarding them.
     */
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

    /*
     * Discard the temporary scans and leave.
     */
    if (discard == true && mounted) {
      _scannedBottles.clear();

      Navigator.pop(context);
    }
  }

  /*
   * Displays a standard message dialog.
   *
   * Used for scan results, errors, pickup completion,
   * payment information, and other rider messages.
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

  /*
   * Safely converts an API value to an integer.
   *
   * If conversion fails, the supplied fallback
   * value is returned.
   */
  int _toInt(dynamic value, {required int fallback}) {
    if (value == null) {
      return fallback;
    }

    return int.tryParse(value.toString()) ?? fallback;
  }

  /*
   * Safely converts an API value to a double.
   *
   * If the API value is missing or invalid,
   * zero is returned.
   */
  double _toDouble(dynamic value) {
    if (value == null) {
      return 0;
    }

    return double.tryParse(value.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final required = widget.order.deliveredBottleCount;

    final scanned = _scannedBottles.length;

    final remaining = required - scanned;

    final canComplete = scanned > 0 && !_isProcessing;

    final allScanned = scanned >= required;

    /*
     * PopScope prevents accidental navigation while
     * the rider has unsaved temporary scans.
     */
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
               * Order information and scan progress.
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
                            'Bottles scanned',
                            style: AppTextStyles.body,
                          ),
                        ),
                        Text(
                          '$scanned / $required',
                          style: AppTextStyles.dashboardTitle,
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.xs),

                    Text(
                      'Remaining: $remaining',
                      style: AppTextStyles.bodySecondary,
                    ),

                    const SizedBox(height: AppSpacing.sm),

                    LinearProgressIndicator(
                      value: required == 0 ? 0 : scanned / required,
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

                    /*
                     * Scanner guide box.
                     */
                    Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),

                    /*
                     * Processing overlay.
                     */
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
               * Displays bottles that have been
               * temporarily scanned.
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
               * Commits the temporary scans.
               *
               * The button changes its label depending
               * on whether all delivered bottles have
               * been scanned.
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
                      allScanned
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
 * Represents a bottle that has been scanned locally
 * but has NOT yet been committed to the database.
 *
 * The GPS coordinates belong to the moment the
 * bottle was scanned.
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

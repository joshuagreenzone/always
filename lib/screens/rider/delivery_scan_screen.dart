import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/account.dart';
import '../../models/order_details.dart';
import '../../services/rider_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

import 'delivery_confirmation_screen.dart';

class DeliveryScanScreen extends StatefulWidget {
  final Account account;
  final OrderDetails order;

  const DeliveryScanScreen({
    super.key,
    required this.account,
    required this.order,
  });

  @override
  State<DeliveryScanScreen> createState() => _DeliveryScanScreenState();
}

class _DeliveryScanScreenState extends State<DeliveryScanScreen> {
  final MobileScannerController _scannerController = MobileScannerController();

  final RiderService _riderService = RiderService();

  final List<String> _scannedBottles = [];

  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  // ============================================================
  // QR SCAN
  // ============================================================

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_isProcessing) {
      return;
    }

    if (_scannedBottles.length >= widget.order.quantity) {
      return;
    }

    if (capture.barcodes.isEmpty) {
      return;
    }

    final String? value = capture.barcodes.first.rawValue;

    if (value == null || value.trim().isEmpty) {
      return;
    }

    final bottleNumber = value.trim();

    await _processBottle(bottleNumber);
  }

  // ============================================================
  // PROCESS BOTTLE
  // ============================================================

  Future<void> _processBottle(String bottleNumber) async {
    if (_isProcessing) {
      return;
    }

    // Local duplicate check first.
    if (_scannedBottles.contains(bottleNumber)) {
      await _showMessage(
        'Already Scanned',
        'This bottle has already been scanned for this delivery.\n\n'
            'Bottle: $bottleNumber',
      );

      return;
    }

    setState(() {
      _isProcessing = true;
    });

    // Stop camera while the server validates the bottle.
    try {
      await _scannerController.stop();
    } catch (_) {}

    try {
      // ========================================================
      // SERVER VALIDATION
      // ========================================================

      final result = await _riderService.scanDeliveryBottle(
        accId: widget.account.accId,
        orderId: widget.order.orderId,
        deliveryId: widget.order.deliveryId,
        bottleNumber: bottleNumber,
      );

      if (!mounted) {
        return;
      }

      // ========================================================
      // SERVER ACCEPTED THE BOTTLE
      // ========================================================

      setState(() {
        _scannedBottles.add(bottleNumber);
      });

      final scanned = _scannedBottles.length;

      final required = widget.order.quantity;

      // If all bottles have been scanned,
      // don't restart the camera.
      if (scanned >= required) {
        setState(() {
          _isProcessing = false;
        });

        await _showMessage(
          'Complete',
          'All required bottles have been scanned.',
        );

        return;
      }

      setState(() {
        _isProcessing = false;
      });

      await _showMessage(
        'Bottle Accepted',
        'Bottle: $bottleNumber\n\n'
            'Scanned: $scanned / $required',
      );

      if (!mounted) {
        return;
      }

      // Restart scanner for the next bottle.
      await _scannerController.start();
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

      // ========================================================
      // BOTTLE REJECTED
      // ========================================================

      await _showMessage('Bottle Rejected', message);

      if (!mounted) {
        return;
      }

      // The bottle was NOT added to the list.
      // Allow the rider to scan another bottle.
      await _scannerController.start();
    }
  }

  // ============================================================
  // MESSAGE
  // ============================================================

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

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final required = widget.order.quantity;

    final scanned = _scannedBottles.length;

    final complete = scanned >= required;

    return Scaffold(
      appBar: AppBar(
        title: Text('Delivery #${widget.order.orderId}'),
        centerTitle: true,
      ),

      body: SafeArea(
        child: Column(
          children: [
            // ==================================================
            // ORDER INFORMATION
            // ==================================================

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

                  const SizedBox(height: AppSpacing.sm),

                  LinearProgressIndicator(
                    value: required == 0 ? 0 : scanned / required,
                  ),
                ],
              ),
            ),

            // ==================================================
            // SCANNER
            // ==================================================
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
                            'Checking bottle...',
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

            // ==================================================
            // SCANNED BOTTLES
            // ==================================================
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

                            Text(bottle, style: AppTextStyles.body),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

            // ==================================================
            // CONTINUE
            // ==================================================
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
                  onPressed: complete
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DeliveryConfirmationScreen(
                                account: widget.account,

                                order: widget.order,

                                scannedBottles: List<String>.from(
                                  _scannedBottles,
                                ),
                              ),
                            ),
                          );
                        }
                      : null,

                  child: const Text('Continue'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

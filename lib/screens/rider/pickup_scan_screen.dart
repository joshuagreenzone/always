import 'package:flutter/material.dart';
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

  final List<String> _scannedBottles = [];

  bool _isProcessing = false;

  int? _pickUpId;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_isProcessing) {
      return;
    }

    if (_scannedBottles.length >= widget.order.deliveredBottleCount) {
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

  Future<void> _processBottle(String bottleNumber) async {
    if (_isProcessing) {
      return;
    }

    if (_scannedBottles.contains(bottleNumber)) {
      await _showMessage(
        'Already Scanned',
        'This bottle has already been scanned '
            'for this pickup.',
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
      final result = await _riderService.scanPickupBottle(
        accId: widget.account.accId,
        orderId: widget.order.orderId,
        deliveryId: widget.order.deliveryId,
        bottleNumber: bottleNumber,
      );

      if (!mounted) {
        return;
      }

      final returnedPickUpId = int.tryParse(result['pickUpId'].toString());

      if (returnedPickUpId != null) {
        _pickUpId = returnedPickUpId;
      }

      setState(() {
        _scannedBottles.add(bottleNumber);
        _isProcessing = false;
      });

      final required = widget.order.deliveredBottleCount;

      final scanned = _scannedBottles.length;

      if (scanned >= required) {
        await _showMessage(
          'Pickup Ready',
          'All delivered bottles have been '
              'scanned.',
        );

        return;
      }

      await _showMessage(
        'Bottle Accepted',
        'Bottle: $bottleNumber\n\n'
            'Picked up: $scanned / $required',
      );

      if (!mounted) {
        return;
      }

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

      await _showMessage('Pickup Rejected', message);

      if (!mounted) {
        return;
      }

      await _scannerController.start();
    }
  }

  Future<void> _completePickup() async {
    if (_pickUpId == null) {
      return;
    }

    if (_scannedBottles.length != widget.order.deliveredBottleCount) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await _riderService.completePickup(
        accId: widget.account.accId,
        orderId: widget.order.orderId,
        deliveryId: widget.order.deliveryId,
        pickUpId: _pickUpId!,
      );

      if (!mounted) {
        return;
      }

      await _showMessage(
        'Pickup Completed',
        'All bottles from Order #'
            '${widget.order.orderId} '
            'have been picked up successfully.',
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context);
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
    final required = widget.order.deliveredBottleCount;

    final scanned = _scannedBottles.length;

    final complete = scanned == required && _pickUpId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('Pickup #${widget.order.orderId}'),
        centerTitle: true,
      ),

      body: SafeArea(
        child: Column(
          children: [
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
                  onPressed: complete && !_isProcessing
                      ? _completePickup
                      : null,

                  child: const Text('Complete Pickup'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

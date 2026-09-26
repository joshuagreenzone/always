import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/account.dart';
import '../../models/order_details.dart';
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

  final List<_PendingDeliveryBottle> _scannedBottles = [];

  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_isProcessing) {
      return;
    }

    if (_scannedBottles.length >= widget.order.totalQuantity) {
      return;
    }

    if (capture.barcodes.isEmpty) {
      return;
    }

    final String? value = capture.barcodes.first.rawValue;

    if (value == null || value.trim().isEmpty) {
      return;
    }

    await _processBottle(value.trim());
  }

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

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _processBottle(String bottleNumber) async {
    if (_isProcessing) {
      return;
    }

    final alreadyScanned = _scannedBottles.any(
      (item) => item.bottleNumber.toLowerCase() == bottleNumber.toLowerCase(),
    );

    if (alreadyScanned) {
      await _showMessage(
        'Already Scanned',
        'This bottle has already been scanned '
            'for this delivery.\n\n'
            'Bottle: $bottleNumber',
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

      if (!mounted) {
        return;
      }

      setState(() {
        _scannedBottles.add(
          _PendingDeliveryBottle(
            bottleNumber: bottleNumber,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
          ),
        );

        _isProcessing = false;
      });

      final scanned = _scannedBottles.length;

      final required = widget.order.totalQuantity;

      final remaining = required - scanned;

      if (scanned >= required) {
        await _showMessage(
          'Complete',
          'All required bottles have been '
              'scanned.\n\n'
              'The bottles are temporarily stored '
              'and have NOT been saved to the database yet.\n\n'
              'Press Continue to confirm the delivery.',
        );

        return;
      }

      await _showMessage(
        'Bottle Scanned',
        'Bottle: $bottleNumber\n\n'
            'Scanned: $scanned / $required\n'
            'Remaining: $remaining\n\n'
            'This bottle has NOT been saved to the '
            'database yet.',
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

      await _showMessage('Unable to Scan Bottle', message);

      if (!mounted) {
        return;
      }

      await _scannerController.start();
    }
  }

  Future<void> _continueToConfirmation() async {
    if (_isProcessing || _scannedBottles.length != widget.order.totalQuantity) {
      return;
    }

    try {
      await _scannerController.stop();
    } catch (_) {}

    if (!mounted) {
      return;
    }

    final scannedBottleData = _scannedBottles.map((item) {
      return <String, dynamic>{
        'bottleNumber': item.bottleNumber,
        'latitude': item.latitude,
        'longitude': item.longitude,
        'accuracy': item.accuracy,
      };
    }).toList();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryConfirmationScreen(
          account: widget.account,
          order: widget.order,
          scannedBottles: scannedBottleData,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    if (_scannedBottles.length < widget.order.totalQuantity) {
      await _scannerController.start();
    }
  }

  Future<void> _handleBack() async {
    if (_isProcessing) {
      return;
    }

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
            'will be discarded.\n\n'
            'No database records have been created '
            'by these scans.',
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
    final required = widget.order.totalQuantity;

    final scanned = _scannedBottles.length;

    final remaining = required - scanned;

    final complete = scanned == required;

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
          title: Text('Delivery #${widget.order.orderId}'),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _isProcessing ? null : _handleBack,
          ),
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

                    ...widget.order.items.map(
                      (item) => Text(
                        '${item.bottleType} × ${item.quantity}',
                        style: AppTextStyles.bodySecondary,
                      ),
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
                              'Getting location...',
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
                        ? _continueToConfirmation
                        : null,
                    child: Text(
                      complete ? 'Continue' : 'Scan All Bottles First',
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

class _PendingDeliveryBottle {
  final String bottleNumber;
  final double latitude;
  final double longitude;
  final double accuracy;

  const _PendingDeliveryBottle({
    required this.bottleNumber,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });
}

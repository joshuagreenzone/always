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
  bool _isNavigating = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_isProcessing || _isNavigating) return;
    if (_scannedBottles.length >= widget.order.totalQuantity) return;
    if (capture.barcodes.isEmpty) return;

    final value = capture.barcodes.first.rawValue;

    if (value == null || value.trim().isEmpty) return;

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
        'Location permission is permanently denied. '
        'Please enable it from the app settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _processBottle(String bottleNumber) async {
    if (_isProcessing || _isNavigating) return;

    if (_scannedBottles.length >= widget.order.totalQuantity) {
      return;
    }

    final alreadyScanned = _scannedBottles.any(
      (item) => item.bottleNumber.toLowerCase() == bottleNumber.toLowerCase(),
    );

    if (alreadyScanned) {
      await _pauseScanner();

      if (!mounted) return;

      await _showMessage(
        'Already Scanned',
        'This bottle has already been scanned for this delivery.\n\n'
            'Bottle: $bottleNumber',
      );

      if (mounted && _canScanMore) {
        await _resumeScanner();
      }

      return;
    }

    setState(() {
      _isProcessing = true;
    });

    await _pauseScanner();

    try {
      final position = await _getCurrentLocation();

      if (!mounted) return;

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

      await _showMessage(
        scanned == required ? 'All Bottles Scanned' : 'Bottle Scanned',
        'Bottle: $bottleNumber\n\n'
        'Scanned: $scanned / $required\n'
        'Remaining: $remaining\n\n'
        'Scans are temporary until you confirm the delivery.',
      );

      if (!mounted) return;

      if (_canScanMore) {
        await _resumeScanner();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isProcessing = false;
      });

      final message = e.toString().replaceFirst('Exception: ', '');

      await _showMessage('Unable to Scan Bottle', message);

      if (mounted && _canScanMore) {
        await _resumeScanner();
      }
    }
  }

  bool get _canScanMore =>
      !_isProcessing &&
      !_isNavigating &&
      _scannedBottles.length < widget.order.totalQuantity;

  Future<void> _pauseScanner() async {
    try {
      await _scannerController.stop();
    } catch (_) {}
  }

  Future<void> _resumeScanner() async {
    if (!mounted || !_canScanMore) return;

    try {
      await _scannerController.start();
    } catch (_) {}
  }

  Future<void> _continueToConfirmation() async {
    if (_isProcessing ||
        _isNavigating ||
        _scannedBottles.isEmpty ||
        _scannedBottles.length > widget.order.totalQuantity) {
      return;
    }

    setState(() {
      _isNavigating = true;
    });

    await _pauseScanner();

    if (!mounted) return;

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

    if (!mounted) return;

    setState(() {
      _isNavigating = false;
    });

    if (_canScanMore) {
      await _resumeScanner();
    }
  }

  Future<void> _handleBack() async {
    if (_isProcessing || _isNavigating) return;

    if (_scannedBottles.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Discard Scanned Bottles?'),
        content: Text(
          '${_scannedBottles.length} bottle'
          '${_scannedBottles.length == 1 ? '' : 's'} '
          'have been scanned but not saved.\n\n'
          'Leaving this screen will discard these temporary scans.',
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
      ),
    );

    if (discard == true && mounted) {
      _scannedBottles.clear();
      Navigator.pop(context);
    }
  }

  Future<void> _showMessage(String title, String message) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
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
    final required = widget.order.totalQuantity;
    final scanned = _scannedBottles.length;
    final remaining = (required - scanned).clamp(0, required);
    final allScanned = required > 0 && scanned >= required;
    final canContinue = scanned > 0 && !_isProcessing && !_isNavigating;

    return PopScope(
      canPop: !_isProcessing && !_isNavigating && _scannedBottles.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isProcessing || _isNavigating) return;
        await _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Delivery #${widget.order.orderId}'),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: (_isProcessing || _isNavigating) ? null : _handleBack,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Top compact summary
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
                    ...widget.order.items.map(
                      (item) => Text(
                        '${item.bottleType} × ${item.quantity}',
                        style: AppTextStyles.bodySecondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        const Expanded(child: Text('Bottles scanned')),
                        Text(
                          '$scanned / $required',
                          style: AppTextStyles.dashboardTitle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: required <= 0
                          ? 0
                          : (scanned / required).clamp(0.0, 1.0),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      allScanned
                          ? 'All ordered bottles scanned'
                          : '$remaining remaining · Partial delivery allowed',
                      style: AppTextStyles.bodySecondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Scanner view fills remaining flexible space
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
              ),

              // Bottom persistent bar with auto-fitting ListView
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
                          onPressed: canContinue
                              ? _continueToConfirmation
                              : null,
                          child: Text(
                            scanned == 0
                                ? 'Scan at Least One Bottle'
                                : allScanned
                                ? 'Continue to Confirmation'
                                : 'Continue with $scanned Bottle'
                                      '${scanned == 1 ? '' : 's'}',
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

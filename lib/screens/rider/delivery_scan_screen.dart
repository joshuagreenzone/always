import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/batch_scan_location.dart';
import '../../widgets/common/bottle_scanner_view.dart';
import '../../widgets/common/rider_scan_card.dart';

import '../../models/account.dart';
import '../../models/order_details.dart';
import '../../services/vehicle_bottle_service.dart';
import '../../widgets/common/bottle_condition_dialog.dart';

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
  final MobileScannerController _scannerController =
      createBottleScannerController();

  final List<_PendingDeliveryBottle> _scannedBottles = [];

  final _batchLocation = BatchScanLocation();
  String? _scanMessage;
  bool _scanSuccess = true;
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

  Future<void> _processBottle(String bottleNumber) async {
    if (_isProcessing ||
        _isNavigating ||
        _scannedBottles.length >= widget.order.totalQuantity) {
      return;
    }
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
        requireRecoveryRefill: true,
      );
      if (!mounted) return;
      if (!ready) {
        setState(() {
          _scanSuccess = false;
          _scanMessage = 'Bottle not added';
        });
        return;
      }
      await VehicleBottleService().verify(
        widget.account.accId,
        bottleNumber,
        'DELIVERY',
      );
      final position = await _batchLocation.get();
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

    setState(() => _isProcessing = true);
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

    if (mounted) setState(() => _isProcessing = false);
    if (discard == true && mounted) {
      _scannedBottles.clear();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final required = widget.order.totalQuantity;
    final scanned = _scannedBottles.length;
    final completed = scanned;
    final remaining = (required - completed).clamp(0, required);
    final busy = _isProcessing || _isNavigating;
    final canConfirm = scanned > 0 && !busy;

    return PopScope(
      canPop: !busy && _scannedBottles.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || busy) return;
        await _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Delivery #${widget.order.orderId}'),
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
                    ...widget.order.items.map(
                      (item) => Text('${item.bottleType} × ${item.quantity}'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Bottles scanned: $completed / $required',
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
                          : '$remaining remaining · Partial delivery allowed',
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
                  title: 'Bottles to Deliver',
                  bottles: _scannedBottles.map((b) => b.bottleNumber).toList(),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: canConfirm ? _continueToConfirmation : null,
            icon: const Icon(Icons.check_circle_outline),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                busy ? 'Please wait...' : 'Confirm Delivery ($scanned)',
              ),
            ),
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

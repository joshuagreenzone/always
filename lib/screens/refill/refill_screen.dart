import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/account.dart';

import '../../models/bottle.dart';
import '../../services/refill_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

class RefillScreen extends StatefulWidget {
  final Account account;

  const RefillScreen({super.key, required this.account});

  @override
  State<RefillScreen> createState() => _RefillScreenState();
}

class _RefillScreenState extends State<RefillScreen> {
  final RefillService _refillService = RefillService();

  Bottle? _scannedBottle;

  bool _isScanning = false;
  bool _isLoading = false;

  String? _errorMessage;

  void _scanBottle() {
    setState(() {
      _scannedBottle = null;
      _errorMessage = null;
      _isScanning = true;
      _isLoading = false;
    });
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

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _handleQrCode(String value) async {
    if (!_isScanning) return;

    setState(() {
      _isScanning = false;
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final bottle = await _refillService.verifyBottle(value);

      if (!mounted) return;

      setState(() {
        _scannedBottle = bottle;
        _isLoading = false;
      });
    } on RefillException catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      await _showInvalidBottleDialog(e.message, value);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = _cleanError(e);
      });
    }
  }

  Future<void> _confirmRefill() async {
    final bottle = _scannedBottle;

    if (bottle == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      /*
       * Get the physical location at the moment the
       * refill is confirmed.
       */
      final position = await _getCurrentLocation();

      await _refillService.createRefill(
        accId: widget.account.accId,
        bottleNumber: bottle.bottleNumber,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _scannedBottle = null;
      });

      await _showSuccessDialog(
        '${bottle.bottleNumber} has been successfully '
        'recorded as refilled.',
      );
    } on RefillException catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      await _showInvalidBottleDialog(e.message, bottle.bottleNumber);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = _cleanError(e);
      });
    }
  }

  Future<void> _showSuccessDialog(String message) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('Refill Successful')),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showInvalidBottleDialog(
    String message,
    String bottleNumber,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cancel, color: AppColors.error),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('Invalid Bottle')),
            ],
          ),
          content: Text(
            '$message\n\n'
            'Bottle: $bottleNumber',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _resetScan() {
    setState(() {
      _scannedBottle = null;
      _errorMessage = null;
      _isScanning = false;
      _isLoading = false;
    });
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Refill')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isScanning) {
      return _buildScanner();
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildError();
    }

    if (_scannedBottle != null) {
      return _buildBottleConfirmation();
    }

    return _buildStartScreen();
  }

  Widget _buildStartScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.water_drop, size: 80, color: AppColors.primary),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Bottle Refill',
              style: AppTextStyles.screenTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Scan the QR code attached to the gallon '
              'to identify the bottle before refilling.',
              style: AppTextStyles.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _scanBottle,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('SCAN QR CODE'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          onDetect: (capture) {
            if (capture.barcodes.isEmpty) {
              return;
            }

            final barcode = capture.barcodes.first;
            final value = barcode.rawValue;

            if (value == null || value.trim().isEmpty) {
              return;
            }

            _handleQrCode(value.trim());
          },
        ),
        Positioned(
          top: AppSpacing.lg,
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            ),
            child: const Text(
              'Point the camera at the QR code '
              'on the gallon.',
              style: TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        Positioned(
          bottom: AppSpacing.xl,
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          child: SizedBox(
            height: AppSizes.buttonHeight,
            child: ElevatedButton(
              onPressed: _resetScan,
              child: const Text('CANCEL'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottleConfirmation() {
    final bottle = _scannedBottle!;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.sm),
            const Icon(Icons.check_circle, size: 70, color: AppColors.success),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Bottle Verified',
              style: AppTextStyles.screenTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoItem(
                      label: 'Bottle Number',
                      value: bottle.bottleNumber,
                      valueStyle: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _InfoItem(label: 'Bottle Type', value: bottle.bottleType),
                    const SizedBox(height: AppSpacing.lg),
                    _InfoItem(
                      label: 'Refill Price',
                      value: '₱${bottle.price.toStringAsFixed(2)}',
                      valueStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              height: AppSizes.buttonHeight,
              child: ElevatedButton.icon(
                onPressed: _confirmRefill,
                icon: const Icon(Icons.water_drop),
                label: const Text('CONFIRM REFILL'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: AppSizes.buttonHeight,
              child: OutlinedButton(
                onPressed: _resetScan,
                child: const Text('SCAN DIFFERENT BOTTLE'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: AppSizes.largeIconSize,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Unable to Verify Bottle',
              style: AppTextStyles.sectionTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _errorMessage!,
              style: AppTextStyles.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _resetScan,
                child: const Text('TRY AGAIN'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;

  const _InfoItem({required this.label, required this.value, this.valueStyle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.bodySecondary),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: valueStyle ?? AppTextStyles.body),
      ],
    );
  }
}

// ============================================================
// lib/screens/station_worker/bottle_registration_scan_screen.dart
// ============================================================

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BottleRegistrationScanScreen extends StatefulWidget {
  const BottleRegistrationScanScreen({super.key});

  @override
  State<BottleRegistrationScanScreen> createState() =>
      _BottleRegistrationScanScreenState();
}

class _BottleRegistrationScanScreenState
    extends State<BottleRegistrationScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  bool _hasScanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) {
      return;
    }

    for (final barcode in capture.barcodes) {
      final String? rawValue = barcode.rawValue?.trim();

      if (rawValue == null || rawValue.isEmpty) {
        continue;
      }

      _hasScanned = true;

      _controller.stop();

      if (!mounted) {
        return;
      }

      Navigator.pop(context, rawValue);
      return;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan Bottle QR'),
        actions: [
          IconButton(
            tooltip: 'Toggle torch',
            onPressed: () {
              _controller.toggleTorch();
            },
            icon: const Icon(Icons.flash_on),
          ),
          IconButton(
            tooltip: 'Switch camera',
            onPressed: () {
              _controller.switchCamera();
            },
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,

            // IMPORTANT:
            // mobile_scanner 7.4.2 uses:
            //
            // errorBuilder(BuildContext, MobileScannerException)
            //
            // There is NO Widget child parameter.
            errorBuilder: (BuildContext context, MobileScannerException error) {
              String message =
                  'Please check the camera permission '
                  'and make sure the camera is available.';

              final String? errorMessage = error.errorDetails?.message;

              if (errorMessage != null && errorMessage.trim().isNotEmpty) {
                message = errorMessage;
              }

              return Container(
                color: Colors.black,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Unable to access the camera.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await _controller.start();
                        } catch (_) {
                          // The MobileScanner widget will continue
                          // displaying its error state if the camera
                          // cannot be started.
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              );
            },
          ),

          // ---------------------------------------------------
          // QR scanning frame
          // ---------------------------------------------------
          Center(
            child: Container(
              width: 270,
              height: 270,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),

          // ---------------------------------------------------
          // Instructions
          // ---------------------------------------------------
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: SafeArea(
              child: Column(
                children: const [
                  Text(
                    'Position the bottle QR code inside the box',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'The QR value will be saved exactly as scanned.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

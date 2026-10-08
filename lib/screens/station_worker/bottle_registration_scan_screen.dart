// ============================================================
// lib/screens/station_worker/bottle_registration_scan_screen.dart
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BottleRegistrationScanScreen extends StatefulWidget {
  /// Called when a new QR code is detected.
  ///
  /// Returns true if the bottle was accepted.
  /// Returns false if it was rejected/duplicated.
  final Future<bool> Function(String value) onScanned;

  const BottleRegistrationScanScreen({super.key, required this.onScanned});

  @override
  State<BottleRegistrationScanScreen> createState() =>
      _BottleRegistrationScanScreenState();
}

class _BottleRegistrationScanScreenState
    extends State<BottleRegistrationScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    // Only QR codes are accepted.
    formats: const [BarcodeFormat.qrCode],

    // Normal gives good continuous detection without
    // unnecessarily processing every camera frame.
    detectionSpeed: DetectionSpeed.normal,

    // Keep the scanner responsive.
    detectionTimeoutMs: 100,
  );

  // Prevents the same QR from being processed repeatedly.
  String? _lastScannedValue;

  // Prevents overlapping async scan processing.
  bool _isProcessing = false;

  // Small visual feedback after a successful scan.
  String? _statusMessage;
  bool _statusSuccess = true;

  Timer? _statusTimer;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) {
      return;
    }

    for (final barcode in capture.barcodes) {
      // Extra QR-only protection.
      if (barcode.format != BarcodeFormat.qrCode) {
        continue;
      }

      final String? rawValue = barcode.rawValue?.trim();

      if (rawValue == null || rawValue.isEmpty) {
        continue;
      }

      // Ignore the same QR while it is still in front
      // of the camera.
      if (_lastScannedValue == rawValue) {
        return;
      }

      _lastScannedValue = rawValue;
      _isProcessing = true;

      // Immediate feedback.
      await _giveScanFeedback();

      bool accepted = false;

      try {
        accepted = await widget.onScanned(rawValue);
      } catch (_) {
        accepted = false;
      }

      if (!mounted) {
        return;
      }

      if (accepted) {
        _showStatus('Scanned\n$rawValue', success: true);
      } else {
        _showStatus('Already scanned\n$rawValue', success: false);
      }

      // Very short cooldown.
      //
      // This is intentionally short so the worker can immediately
      // move to the next bottle.
      await Future<void>.delayed(const Duration(milliseconds: 350));

      if (!mounted) {
        return;
      }

      setState(() {
        _isProcessing = false;
      });

      return;
    }
  }

  Future<void> _giveScanFeedback() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {
      // Haptic feedback is optional.
    }
  }

  void _showStatus(String message, {required bool success}) {
    _statusTimer?.cancel();

    if (!mounted) {
      return;
    }

    setState(() {
      _statusMessage = message;
      _statusSuccess = success;
    });

    _statusTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = null;
      });
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
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
          // ======================================================
          // CAMERA
          // ======================================================
          //
          // IMPORTANT:
          // There is intentionally NO scanWindow here.
          //
          // This allows Mobile Scanner to detect the QR anywhere
          // in the camera view instead of requiring very precise
          // positioning.
          //
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
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
                          // Keep the error state if the camera
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

          // ======================================================
          // DARK OVERLAY
          // ======================================================
          //
          // This is only visual. It does NOT restrict detection.
          //
          IgnorePointer(child: CustomPaint(painter: _ScannerOverlayPainter())),

          // ======================================================
          // VISUAL SCAN FRAME
          // ======================================================
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isProcessing ? Colors.orangeAccent : Colors.white,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          // ======================================================
          // PROCESSING INDICATOR
          // ======================================================
          if (_isProcessing)
            Positioned(
              top: 24,
              left: 20,
              right: 20,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.72),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Ready for next bottle...',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ======================================================
          // SCAN RESULT
          // ======================================================
          if (_statusMessage != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: 140,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _statusSuccess
                      ? Colors.green.withOpacity(0.92)
                      : Colors.orange.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _statusMessage!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // ======================================================
          // INSTRUCTIONS
          // ======================================================
          Positioned(
            left: 20,
            right: 20,
            bottom: 40,
            child: SafeArea(
              child: Column(
                children: [
                  const Text(
                    'Point the camera at the bottle QR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isProcessing
                        ? 'Moving to the next bottle...'
                        : 'QR codes can be scanned continuously',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
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

// ============================================================
// VISUAL CAMERA OVERLAY
// ============================================================

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double boxSize = 220;

    final Rect scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: boxSize,
      height: boxSize,
    );

    final Paint paint = Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..style = PaintingStyle.fill;

    final Path background = Path()..addRect(Offset.zero & size);

    final Path cutout = Path()
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(20)));

    final Path overlay = Path.combine(
      PathOperation.difference,
      background,
      cutout,
    );

    canvas.drawPath(overlay, paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return false;
  }
}

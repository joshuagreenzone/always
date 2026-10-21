import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

MobileScannerController createBottleScannerController({
  bool autoStart = true,
}) => MobileScannerController(
  autoStart: autoStart,
  formats: const [BarcodeFormat.qrCode],
  detectionSpeed: DetectionSpeed.normal,
  detectionTimeoutMs: 100,
);

/// Registration-style camera shared by all bottle workflows.
/// The frame is visual only: QR detection uses the whole camera preview.
class BottleScannerView extends StatefulWidget {
  final MobileScannerController controller;
  final Future<void> Function(BarcodeCapture) onDetect;
  final bool enabled;
  final bool busy;
  final String? message;
  final bool success;

  const BottleScannerView({
    super.key,
    required this.controller,
    required this.onDetect,
    this.enabled = true,
    this.busy = false,
    this.message,
    this.success = true,
  });

  @override
  State<BottleScannerView> createState() => _BottleScannerViewState();
}

class _BottleScannerViewState extends State<BottleScannerView> {
  bool _processing = false;
  String? _lastValue;
  DateTime? _lastScan;

  Future<void> _detect(BarcodeCapture capture) async {
    if (_processing || widget.busy || !widget.enabled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (barcode.format != BarcodeFormat.qrCode ||
          value == null ||
          value.isEmpty) {
        continue;
      }
      final now = DateTime.now();
      if (_lastValue == value &&
          _lastScan != null &&
          now.difference(_lastScan!) < const Duration(seconds: 2)) {
        continue;
      }
      _lastValue = value;
      _lastScan = now;
      setState(() => _processing = true);
      try {
        unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
        if (!mounted) return;
        await widget.onDetect(BarcodeCapture(barcodes: [barcode]));
      } finally {
        if (mounted) setState(() => _processing = false);
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final frameSize = math.min(
          220.0,
          math.max(
            80.0,
            math.min(constraints.maxWidth - 48, constraints.maxHeight - 150),
          ),
        );
        final busy = widget.busy || _processing;
        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: widget.controller,
              onDetect: _detect,
              errorBuilder: (context, error) => Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.camera_alt_outlined,
                          color: Colors.white,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Unable to access the camera.\nCheck camera permissions and try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            try {
                              await widget.controller.start();
                            } catch (_) {}
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(painter: _ScannerOverlayPainter(frameSize)),
            ),
            IgnorePointer(
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: frameSize,
                  height: frameSize,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: busy ? Colors.orangeAccent : Colors.white,
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Toggle torch',
                    onPressed: () async {
                      try {
                        await widget.controller.toggleTorch();
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.flash_on, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: 'Switch camera',
                    onPressed: busy
                        ? null
                        : () async {
                            try {
                              await widget.controller.switchCamera();
                            } catch (_) {}
                          },
                    icon: const Icon(
                      Icons.cameraswitch_outlined,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.message != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: (widget.success ? Colors.green : Colors.orange)
                            .withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        widget.message!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .72),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      busy
                          ? 'Checking bottle...'
                          : widget.enabled
                          ? 'Point at a bottle QR • Keep scanning'
                          : 'Review your scanned bottles below',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _ScannerOverlayPainter extends CustomPainter {
  final double frameSize;
  _ScannerOverlayPainter(this.frameSize);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: frameSize,
      height: frameSize,
    );
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()
        ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(20))),
    );
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: .35));
  }

  @override
  bool shouldRepaint(_ScannerOverlayPainter oldDelegate) =>
      oldDelegate.frameSize != frameSize;
}

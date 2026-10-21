import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:syawla/widgets/common/bottle_scanner_view.dart';

BarcodeCapture qr(String value) => BarcodeCapture(
  barcodes: [Barcode(rawValue: value, format: BarcodeFormat.qrCode)],
);

void main() {
  testWidgets(
    'serializes scans and accepts the next bottle without a cooldown',
    (tester) async {
      final controller = createBottleScannerController(autoStart: false);
      final pending = Completer<void>();
      final scans = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BottleScannerView(
              controller: controller,
              onDetect: (capture) async {
                scans.add(capture.barcodes.first.rawValue!);
                if (scans.length == 1) await pending.future;
              },
            ),
          ),
        ),
      );
      final camera = tester.widget<MobileScanner>(find.byType(MobileScanner));
      camera.onDetect!(qr('A'));
      await tester.pump();
      camera.onDetect!(qr('B'));
      await tester.pump();
      expect(scans, ['A']);
      pending.complete();
      await tester.pump();
      camera.onDetect!(qr('A'));
      await tester.pump();
      expect(scans, ['A']);
      camera.onDetect!(qr('B'));
      await tester.pump();
      expect(scans, ['A', 'B']);
      await tester.pumpWidget(const SizedBox());
      await controller.dispose();
    },
  );

  testWidgets(
    'ignores non-QR codes and disabled scanning; fits a small viewport',
    (tester) async {
      final controller = createBottleScannerController(autoStart: false);
      var scans = 0;
      Future<void> build({required bool enabled}) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 240,
              child: BottleScannerView(
                controller: controller,
                enabled: enabled,
                onDetect: (_) async {
                  scans++;
                },
              ),
            ),
          ),
        ),
      );
      await build(enabled: true);
      tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect!(
        BarcodeCapture(
          barcodes: [Barcode(rawValue: '123', format: BarcodeFormat.ean13)],
        ),
      );
      await tester.pump();
      expect(scans, 0);
      await build(enabled: false);
      tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect!(
        qr('A'),
      );
      await tester.pump();
      expect(scans, 0);
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Toggle torch'), findsOneWidget);
      expect(find.byTooltip('Switch camera'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await controller.dispose();
    },
  );
}

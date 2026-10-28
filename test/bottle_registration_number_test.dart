import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/models/bottle_type.dart';
import 'package:syawla/screens/station_worker/bottle_registration_scan_screen.dart';
import 'package:syawla/widgets/common/bottle_scanner_view.dart';

void main() {
  testWidgets(
    'scanner rejects malformed QR before condition lookup or adding a bottle',
    (tester) async {
      var added = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: BottleRegistrationScanScreen(
            account: Account(
              accId: 1,
              accName: 'Worker',
              accEmail: '',
              accUsername: 'worker',
              accType: 'STATION_WORKER',
            ),
            bottleType: BottleType(
              bottleTypeId: 1,
              bottleType: 'Round',
              price: 50,
              bottlePrefix: 'A',
            ),
            onScanned: (_) async {
              added++;
              return true;
            },
          ),
        ),
      );
      final scanner = tester.widget<BottleScannerView>(
        find.byType(BottleScannerView),
      );
      await scanner.onDetect(
        BarcodeCapture(
          barcodes: [Barcode(rawValue: 'B-1234', format: BarcodeFormat.qrCode)],
        ),
      );
      await tester.pump();
      expect(added, 0);
      expect(
        tester
            .widget<BottleScannerView>(find.byType(BottleScannerView))
            .message,
        contains('Use A-0000'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  test('registration reads the configured prefix and requires four digits', () {
    final type = BottleType.fromJson({
      'BottleTypeID': 1,
      'BottleType': 'Round',
      'BottlePrefix': 'A',
      'Price': 50,
    });
    for (final number in ['A-0000', 'A-0001', 'A-9999']) {
      expect(type.acceptsNumber(number), isTrue, reason: number);
    }
    for (final number in [
      '',
      'B-0001',
      'a-0001',
      'A0001',
      'A-001',
      'A-00001',
      'A-ABCD',
      'A-0001\n',
      ' A-0001',
      'https://example.com/A-0001',
    ]) {
      expect(type.acceptsNumber(number), isFalse, reason: number);
    }
    expect(type.numberExample, 'A-0000');
  });
  test('multi-letter prefixes are matched literally and missing prefixes reject scans', () {
    final type = BottleType(
      bottleTypeId: 1,
      bottleType: 'Round',
      price: 50,
      bottlePrefix: 'RG',
    );
    expect(type.acceptsNumber('RG-0023'), isTrue);
    expect(type.acceptsNumber('SG-0023'), isFalse);
    final literal = BottleType(
      bottleTypeId: 1,
      bottleType: 'Test',
      price: 50,
      bottlePrefix: 'A+',
    );
    expect(literal.acceptsNumber('A+-0001'), isTrue);
    expect(literal.acceptsNumber('AA-0001'), isFalse);
    expect(
      BottleType(
        bottleTypeId: 1,
        bottleType: 'Missing',
        price: 50,
      ).acceptsNumber('A-0001'),
      isTrue,
    );
  });
  test('legacy A codes can be registered as either Slim or Round', () {
    for (final prefix in ['SG', 'RG']) {
      final type = BottleType(
        bottleTypeId: 1,
        bottleType: prefix,
        price: 50,
        bottlePrefix: prefix,
      );
      expect(type.acceptsNumber('A-0000'), isTrue);
      expect(type.acceptsNumber('A-1234'), isTrue);
      expect(type.acceptsNumber('A-123'), isFalse);
      expect(type.acceptsNumber('A-12345'), isFalse);
      expect(type.acceptedNumberExamples, contains('A-0000 (legacy QR)'));
    }
  });
}

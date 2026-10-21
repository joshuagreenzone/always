import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/models/bottle_condition.dart';
import 'package:syawla/models/order_details.dart';
import 'package:syawla/models/pickup_order.dart';
import 'package:syawla/screens/rider/pickup_scan_screen.dart';
import 'package:syawla/screens/rider/delivery_scan_screen.dart';
import 'package:syawla/screens/rider/delivery_confirmation_screen.dart';
import 'package:syawla/services/batch_scan_location.dart';
import 'package:syawla/services/scan_lookup_service.dart';
import 'package:syawla/services/vehicle_bottle_service.dart';
import 'package:syawla/widgets/common/bottle_scanner_view.dart';

import 'batch_scan_location_test.dart' as gps;

class Lookup extends ScanLookupService {
  final numbers = <String>[];
  @override
  Future<ScanLookup> get(int accId, String number, String eventType) async {
    numbers.add(number);
    return ScanLookup(
      BottleCondition(bottleNumber: number, condition: 'HEALTHY'),
      {'isCycleJump': false, 'previousScanEventId': 7},
      vehicle: {'bottleNumber': number},
    );
  }
}

class Vehicle extends VehicleBottleService {
  @override
  Future<Map<String, dynamic>> verify(
    int accId,
    String number,
    String action,
  ) async =>
      throw StateError('Combined lookup must avoid another vehicle request.');
}

void main() {
  testWidgets('pickup reuses one GPS fix and still checks every bottle', (
    tester,
  ) async {
    var fixes = 0;
    final lookup = Lookup();
    await tester.pumpWidget(
      MaterialApp(
        home: PickupScanScreen(
          account: Account(
            accId: 3,
            accName: 'Rider',
            accEmail: '',
            accUsername: 'rider',
            accType: 'RIDER',
          ),
          order: PickupOrder(
            deliveryId: 1,
            orderId: 1,
            accId: 3,
            customerId: 1,
            customerName: 'Customer',
            bottleTypes: const [],
            quantity: 2,
            deliveredBottleCount: 2,
            pickedUpBottleCount: 0,
            remainingBottleCount: 2,
            deliveryDateTime: DateTime(2026),
            deliveryStatus: 'DELIVERED',
          ),
          lookupService: lookup,
          batchLocation: BatchScanLocation(
            locate: () async {
              fixes++;
              return gps.position(14);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final number in ['A', 'B']) {
      final scanner = tester.widget<BottleScannerView>(
        find.byType(BottleScannerView),
      );
      await scanner.onDetect(
        BarcodeCapture(
          barcodes: [Barcode(rawValue: number, format: BarcodeFormat.qrCode)],
        ),
      );
      await tester.pump();
    }
    expect(fixes, 1);
    expect(lookup.numbers, ['A', 'B']);
    expect(find.text('Confirm Pickup (2)'), findsOneWidget);
  });

  testWidgets('delivery batch shares first GPS coordinates across bottles', (
    tester,
  ) async {
    var fixes = 0;
    final lookup = Lookup();
    await tester.pumpWidget(
      MaterialApp(
        home: DeliveryScanScreen(
          account: Account(
            accId: 3,
            accName: 'Rider',
            accEmail: '',
            accUsername: 'rider',
            accType: 'RIDER',
          ),
          order: OrderDetails(
            orderId: 1,
            customerId: 1,
            customerName: 'Customer',
            items: const [],
            totalQuantity: 2,
            totalAmount: 30,
            orderDateTime: DateTime(2026),
            orderStatus: 'ASSIGNED',
            paymentStatus: 'UNPAID',
            deliveryId: 1,
            deliveryDateTime: DateTime(2026),
            deliveryStatus: 'ASSIGNED',
          ),
          lookupService: lookup,
          vehicleService: Vehicle(),
          batchLocation: BatchScanLocation(
            locate: () async {
              fixes++;
              return gps.position(14);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final number in ['A', 'B']) {
      final scanner = tester.widget<BottleScannerView>(
        find.byType(BottleScannerView),
      );
      await scanner.onDetect(
        BarcodeCapture(
          barcodes: [Barcode(rawValue: number, format: BarcodeFormat.qrCode)],
        ),
      );
      await tester.pump();
    }
    expect(fixes, 1);
    expect(lookup.numbers, ['A', 'B']);
    await tester.tap(find.text('Confirm Delivery (2)'));
    await tester.pumpAndSettle();
    final confirmation = tester.widget<DeliveryConfirmationScreen>(
      find.byType(DeliveryConfirmationScreen),
    );
    expect(confirmation.scannedBottles.map((b) => b['latitude']), [14, 14]);
    expect(confirmation.scannedBottles.map((b) => b['longitude']), [121, 121]);
    expect(confirmation.scannedBottles.map((b) => b['accuracy']), [5, 5]);
  });
}

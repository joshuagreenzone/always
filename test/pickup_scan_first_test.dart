import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/models/bottle_condition.dart';
import 'package:syawla/models/order_details.dart';
import 'package:syawla/models/pickup_order.dart';
import 'package:syawla/screens/rider/pickup_scan_screen.dart';
import 'package:syawla/services/batch_scan_location.dart';
import 'package:syawla/services/rider_service.dart';
import 'package:syawla/services/scan_lookup_service.dart';

PickupOrder order(int id) => PickupOrder(
  deliveryId: id,
  orderId: id,
  accId: 3,
  customerId: 2,
  customerName: 'Sample customer',
  quantity: 3,
  bottleTypes: const [
    PickupBottleType(
      bottleTypeId: 1,
      bottleType: 'Round',
      deliveredBottleCount: 3,
      pickedUpBottleCount: 0,
      remainingBottleCount: 3,
    ),
  ],
  deliveredBottleCount: 3,
  pickedUpBottleCount: 0,
  remainingBottleCount: 3,
  deliveryDateTime: DateTime(2026),
  deliveryStatus: 'DELIVERED',
);

class PickupService extends RiderService {
  int lookups = 0;
  int assignedLoads = 0;
  bool failAssigned = true;

  @override
  Future<List<PickupOrder>> getPickupOrders(int accId) async {
    assignedLoads++;
    if (failAssigned) throw Exception('Could not load deliveries');
    return [order(42), order(99)];
  }

  @override
  Future<PickupOrder> getPickupOrderForBottle(
    int accId,
    String bottleNumber,
  ) async {
    lookups++;
    if (bottleNumber == 'UNKNOWN') throw Exception('No pending pickup found.');
    return order(bottleNumber == 'OTHER' ? 99 : 42);
  }

  @override
  Future<OrderDetails> getOrderDetails({
    required int orderId,
    required int accId,
  }) async => throw Exception('Balance unavailable');
}

class HealthyLookup extends ScanLookupService {
  @override
  Future<ScanLookup> get(int accId, String number, String eventType) async =>
      ScanLookup(BottleCondition(bottleNumber: number, condition: 'HEALTHY'), {
        'isCycleJump': false,
        'previousScanEventId': 1,
      });
}

Future<void> enter(WidgetTester tester, String number) async {
  await tester.ensureVisible(find.text('Enter Bottle Number'));
  await tester.tap(find.text('Enter Bottle Number'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), number);
  await tester.tap(find.text('Add Bottle'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'scan identifies order below scanner, rejects other orders, and clears batch',
    (tester) async {
      final service = PickupService();
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
            riderService: service,
            lookupService: HealthyLookup(),
            batchLocation: BatchScanLocation(
              locate: () async => Position(
                latitude: 14,
                longitude: 121,
                timestamp: DateTime(2026),
                accuracy: 5,
                altitude: 0,
                altitudeAccuracy: 0,
                heading: 0,
                headingAccuracy: 0,
                speed: 0,
                speedAccuracy: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start Scanning'), findsOneWidget);
      expect(find.text('Order #42'), findsNothing);
      final confirm = find.widgetWithText(FilledButton, 'Confirm pickup');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await enter(tester, 'UNKNOWN');
      expect(find.text('No pending pickup found.'), findsOneWidget);
      expect(find.text('Order #42'), findsNothing);
      await enter(tester, 'B-1');
      expect(find.text('Order #42'), findsOneWidget);
      expect(find.text('Sample customer'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Order #42')).dy,
        greaterThan(tester.getTopLeft(find.text('Start Scanning')).dy),
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.ensureVisible(find.text('Assigned deliveries'));
      await tester.tap(find.text('Assigned deliveries'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load deliveries'), findsOneWidget);
      service.failAssigned = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(service.assignedLoads, 2);
      expect(find.text('Order #42'), findsOneWidget);
      expect(find.text('Order #99'), findsOneWidget);
      final actions = find.widgetWithText(TextButton, 'Scan pickup bottles');
      expect(tester.widget<TextButton>(actions.at(0)).onPressed, isNotNull);
      expect(tester.widget<TextButton>(actions.at(1)).onPressed, isNull);
      await tester.ensureVisible(find.text('Pickup bottles').last);
      await tester.tap(find.text('Pickup bottles').last);
      await tester.pumpAndSettle();
      expect(find.text('Order #42'), findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      final previousLookups = service.lookups;
      await enter(tester, 'B-1');
      expect(service.lookups, previousLookups);
      await enter(tester, 'OTHER');
      expect(find.textContaining('belongs to Order #99'), findsOneWidget);
      expect(find.text('Order #99'), findsNothing);
      expect(find.text('Order #42'), findsOneWidget);
      final remove = find.byTooltip('Remove B-1 from scanned list');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.text('Order #42'), findsNothing);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

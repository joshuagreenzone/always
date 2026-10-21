import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/models/assigned_order.dart';
import 'package:syawla/screens/rider/assigned_orders_screen.dart';
import 'package:syawla/services/rider_service.dart';

class FakeAssignedDeliveries extends RiderService {
  @override
  Future<List<AssignedOrder>> getAssignedOrders(int accId) async {
    dispenserAssignments = [
      {
        'AssignmentID': 42,
        'CustomerID': 3,
        'CustomerName': 'Sample Customer',
        'DispenserNumber': 'DSP-001',
        'Brand': 'Sample brand',
        'Model': 'Cooler',
        'OrderID': 16,
        'DeliveryStatus': 'ASSIGNED',
        'Notes': 'Deliver at reception',
      },
    ];
    return [];
  }
}

void main() {
  testWidgets('dispenser assignments are excluded from assigned deliveries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AssignedOrdersScreen(
          account: Account(
            accId: 7,
            accName: 'Rider',
            accEmail: 'rider@example.invalid',
            accUsername: 'rider',
            accType: 'RIDER',
            accRoles: ['RIDER'],
          ),
          riderService: FakeAssignedDeliveries(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Assigned Deliveries'), findsOneWidget);
    expect(find.text('Dispenser Delivery'), findsNothing);
    expect(find.text('DSP-001'), findsNothing);
    expect(find.text('Scan Dispenser Delivery'), findsNothing);
    expect(find.text('No assigned deliveries.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

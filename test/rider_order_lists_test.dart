import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/models/assigned_order.dart';
import 'package:syawla/models/pickup_order.dart';
import 'package:syawla/screens/rider/assigned_orders_screen.dart';
import 'package:syawla/screens/rider/pickup_orders_screen.dart';
import 'package:syawla/services/rider_service.dart';

class OrderListService extends RiderService {
  bool fail = false;
  final date = DateTime(2026, 10, 22, 10);

  @override
  Future<List<AssignedOrder>> getAssignedOrders(int accId) async {
    if (fail) throw Exception('Orders unavailable');
    return [
      AssignedOrder(
        orderId: 140,
        customerId: 26,
        customerName: 'Customer with a long name',
        items: const [
          AssignedOrderItem(
            orderItemId: 1,
            bottleTypeId: 1,
            bottleType: '5-gallon round bottle',
            quantity: 3,
            unitPrice: 50,
            totalAmount: 150,
          ),
        ],
        totalQuantity: 3,
        totalAmount: 150,
        orderDateTime: date,
        orderStatus: 'PENDING',
        paymentStatus: 'UNPAID',
        deliveryId: 1,
        deliveryDateTime: date,
        deliveryStatus: 'OUT_FOR_DELIVERY',
      ),
    ];
  }

  @override
  Future<List<PickupOrder>> getPickupOrders(int accId) async {
    if (fail) throw Exception('Orders unavailable');
    return [
      PickupOrder(
        deliveryId: 1,
        orderId: 140,
        accId: accId,
        customerId: 26,
        customerName: 'Customer with a long name',
        bottleTypes: const [
          PickupBottleType(
            bottleTypeId: 1,
            bottleType: '5-gallon round bottle',
            deliveredBottleCount: 3,
            pickedUpBottleCount: 1,
            remainingBottleCount: 2,
          ),
        ],
        quantity: 3,
        deliveredBottleCount: 3,
        pickedUpBottleCount: 1,
        remainingBottleCount: 2,
        deliveryDateTime: date,
        deliveryStatus: 'DELIVERED',
      ),
    ];
  }
}

void main() {
  final account = Account(
    accId: 3,
    accName: 'Rider',
    accEmail: '',
    accUsername: 'rider',
    accType: 'RIDER',
  );
  for (final pickup in [false, true]) {
    Widget screen(OrderListService service) => MaterialApp(
      home: pickup
          ? PickupOrdersScreen(account: account, riderService: service)
          : AssignedOrdersScreen(account: account, riderService: service),
    );

    testWidgets(
      '${pickup ? 'Pickup' : 'Delivery'} cards fit small screens with large text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(screen(OrderListService()));
        await tester.pumpAndSettle();
        expect(find.text('Order #140'), findsOneWidget);
        expect(find.text(pickup ? '2 left' : 'Unpaid'), findsOneWidget);
        final action = find.text(pickup ? 'Scan pickup bottles' : 'View Order');
        await tester.scrollUntilVisible(action, 150);
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${pickup ? 'Pickup' : 'Delivery'} list recovers after a failed load',
      (tester) async {
        final service = OrderListService()..fail = true;
        await tester.pumpWidget(screen(service));
        await tester.pumpAndSettle();
        expect(find.text('Orders unavailable'), findsOneWidget);
        service.fail = false;
        await tester.tap(find.text('Try Again'));
        await tester.pumpAndSettle();
        expect(find.text('Order #140'), findsOneWidget);
      },
    );
  }
}

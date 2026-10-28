import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/models/order_details.dart';
import 'package:syawla/models/pickup_order.dart';
import 'package:syawla/screens/rider/delivery_scan_screen.dart';
import 'package:syawla/screens/rider/pickup_scan_screen.dart';
import 'package:syawla/widgets/common/rider_scan_card.dart';
import 'package:syawla/widgets/common/bottle_scanner_view.dart';

final account = Account(
  accId: 3,
  accName: 'Rider',
  accEmail: '',
  accUsername: 'rider',
  accType: 'RIDER',
);

void main() {
  for (final pickup in [false, true]) {
    testWidgets(
      '${pickup ? 'Pickup' : 'Delivery'} has order card, scanner, and fixed confirmation on a small phone',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final date = DateTime(2026, 10, 13);
        final screen = pickup
            ? PickupScanScreen(
                account: account,
                order: PickupOrder(
                  deliveryId: 1,
                  orderId: 42,
                  accId: 3,
                  customerId: 2,
                  customerName: 'Customer with a long name',
                  bottleTypes: const [
                    PickupBottleType(
                      bottleTypeId: 1,
                      bottleType: 'Round',
                      deliveredBottleCount: 2,
                      pickedUpBottleCount: 0,
                      remainingBottleCount: 2,
                    ),
                    PickupBottleType(
                      bottleTypeId: 2,
                      bottleType: 'Slim',
                      deliveredBottleCount: 1,
                      pickedUpBottleCount: 0,
                      remainingBottleCount: 1,
                    ),
                  ],
                  quantity: 3,
                  deliveredBottleCount: 3,
                  pickedUpBottleCount: 0,
                  remainingBottleCount: 3,
                  deliveryDateTime: date,
                  deliveryStatus: 'DELIVERED',
                ),
              )
            : DeliveryScanScreen(
                account: account,
                order: OrderDetails(
                  orderId: 42,
                  customerId: 2,
                  customerName: 'Customer with a long name',
                  items: const [
                    OrderItemDetails(
                      orderItemId: 1,
                      bottleTypeId: 1,
                      bottleType: 'Round',
                      quantity: 3,
                      unitPrice: 10,
                      totalAmount: 30,
                    ),
                  ],
                  totalQuantity: 3,
                  totalAmount: 30,
                  orderDateTime: date,
                  orderStatus: 'PENDING',
                  paymentStatus: 'UNPAID',
                  deliveryId: 1,
                  deliveryDateTime: date,
                  deliveryStatus: 'PENDING',
                ),
              );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: screen,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RiderScanCard), findsNWidgets(3));
        expect(find.text('Order #42'), findsOneWidget);
        if (pickup) expect(find.text('0 of 3 bottles'), findsOneWidget);
        final confirm = find.widgetWithText(
          FilledButton,
          pickup ? 'Confirm pickup' : 'Confirm Delivery (0)',
        );
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        expect(confirm.hitTestable(), findsOneWidget);
        await tester.ensureVisible(
          pickup ? find.text('Start Scanning') : find.byType(BottleScannerView),
        );
        await tester.pumpAndSettle();
        expect(confirm.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}

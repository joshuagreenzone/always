import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/models/order_details.dart';
import 'package:syawla/screens/rider/payment_screen.dart';
import 'package:syawla/services/rider_service.dart';

OrderDetails order({double? balance}) => OrderDetails(
  orderId: 201,
  customerId: 1,
  customerName: 'Customer',
  items: const [],
  totalQuantity: 3,
  totalAmount: 35,
  orderDateTime: DateTime(2026, 10, 21),
  orderStatus: 'DELIVERED',
  paymentStatus: 'PARTIALLY_PAID',
  deliveryId: 1,
  deliveryDateTime: DateTime(2026, 10, 21),
  deliveryStatus: 'DELIVERED',
  outstandingAmount: balance,
);

class BalanceService extends RiderService {
  bool fail = false;
  double balance = 15;
  @override
  Future<OrderDetails> getOrderDetails({
    required int orderId,
    required int accId,
  }) async {
    if (fail) throw Exception('Unable to connect.');
    return order(balance: balance);
  }
}

void main() {
  Future<void> open(WidgetTester tester, BalanceService service) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PaymentScreen(
          account: Account(
            accId: 3,
            accName: 'Rider',
            accEmail: '',
            accUsername: 'rider',
            accType: 'RIDER',
          ),
          order: order(),
          scannedBottles: const [{}, {}, {}],
          riderService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows highlighted remaining balance and defaults amount to zero',
    (tester) async {
      await open(tester, BalanceService());
      expect(find.text('Collect payment'), findsOneWidget);
      expect(find.text('Amount due'), findsOneWidget);
      expect(find.text('\u20b115.00'), findsOneWidget);
      final amount = tester.widget<TextField>(find.byType(TextField).first);
      expect(amount.controller!.text, '0');
      expect(amount.enabled, isTrue);
    },
  );

  testWidgets(
    'balance fetch failure allows retry without defaulting to order total',
    (tester) async {
      final service = BalanceService()..fail = true;
      await open(tester, service);
      expect(find.text('Unable to connect.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse,
      );
      service.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('\u20b115.00'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '0',
      );
    },
  );

  testWidgets('fully settled order defaults to zero and disables payment', (
    tester,
  ) async {
    await open(tester, BalanceService()..balance = 0);
    expect(find.text('\u20b10.00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Save payment'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Save payment'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('electronic methods show receipt requirement and retain amount', (
    tester,
  ) async {
    await open(tester, BalanceService());
    expect(find.text('Required for this payment method'), findsNothing);
    expect(find.text('Add receipt photo'), findsNothing);
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    for (final method in ['GCash', 'Bank']) {
      await tester.tap(find.text(method));
      await tester.pumpAndSettle();
      expect(find.text('Required for this payment method'), findsOneWidget);
      expect(find.text('Add receipt photo'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '0',
      );
    }
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    expect(find.text('Required for this payment method'), findsNothing);
    expect(find.text('Add receipt photo'), findsNothing);
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
  });
}

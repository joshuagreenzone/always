import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/models/rider_transaction.dart';
import 'package:syawla/screens/rider/transaction_history_screen.dart';
import 'package:syawla/services/rider_transaction_service.dart';

RiderTransaction transaction(int id, String type, String status) =>
    RiderTransaction(
      orderId: id,
      transactionType: type,
      customerName: 'Customer $id',
      customerAddress: 'Libjo',
      bottleType: '5-gallon',
      quantity: 2,
      unitPrice: 50,
      totalAmount: 100,
      paidAmount: status == 'PAID' ? 100 : 0,
      balance: status == 'PAID' ? 0 : 100,
      paymentStatus: status,
      dateTime: '2026-10-22 10:20:00',
    );

class HistoryService extends RiderTransactionService {
  bool fail = false;
  @override
  Future<List<RiderTransaction>> getTransactionHistory(int accId) async {
    if (fail) throw Exception('Connection unavailable');
    return [
      transaction(140, 'DELIVERED', 'UNPAID'),
      transaction(141, 'DELIVERED', 'PARTIALLY_PAID'),
      transaction(142, 'PICKED_UP', 'PAID'),
    ];
  }
}

void main() {
  Future<void> open(WidgetTester tester, HistoryService service) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TransactionHistoryScreen(
          accId: 3,
          account: Account(
            accId: 3,
            accName: 'Rider',
            accEmail: '',
            accUsername: 'rider',
            accType: 'RIDER',
          ),
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'tabs filter transaction types and distinguish payment statuses',
    (tester) async {
      await open(tester, HistoryService());
      expect(find.text('Order #140'), findsOneWidget);
      expect(find.text('Order #141'), findsOneWidget);
      expect(find.text('Order #142'), findsNothing);
      expect(find.text('Unpaid'), findsOneWidget);
      expect(find.text('Partial'), findsOneWidget);
      expect(find.text('Paid'), findsNothing);
      await tester.tap(find.text('Pickups'));
      await tester.pumpAndSettle();
      expect(find.text('Order #140'), findsNothing);
      expect(find.text('Order #142'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
    },
  );

  testWidgets('compact cards retain customer and payment details in a sheet', (
    tester,
  ) async {
    await open(tester, HistoryService());
    await tester.tap(find.text('Order #140'));
    await tester.pumpAndSettle();
    expect(find.text('Customer 140'), findsOneWidget);
    expect(find.text('Libjo'), findsOneWidget);
    expect(find.text('2 × 5-gallon'), findsOneWidget);
    expect(find.text('Balance'), findsOneWidget);
    expect(find.text('₱100.00'), findsNWidgets(2));
  });

  testWidgets('load failure can be retried', (tester) async {
    final service = HistoryService()..fail = true;
    await open(tester, service);
    expect(find.text('Connection unavailable'), findsOneWidget);
    service.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Order #140'), findsOneWidget);
  });

  testWidgets('history and details fit a small phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester, HistoryService());
    expect(tester.takeException(), isNull);
    expect(find.text('History').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Order #140'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Done'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Transactions'), findsOneWidget);
  });
}

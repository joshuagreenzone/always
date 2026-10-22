import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/screens/rider/dispenser_scan_screen.dart';
import 'package:syawla/services/dispenser_service.dart';

class InventoryService extends DispenserService {
  bool fail = false;
  @override
  Future<Map<String, dynamic>> inventory() async {
    if (fail) throw Exception('Inventory unavailable');
    return {
      'counts': {
        'READY_TO_LOAD': 12,
        'LOADED': 3,
        'DELIVERED': 8,
        'PICKED_UP': 2,
      },
      'dispensers': [],
      'customers': [],
    };
  }
}

void main() {
  Future<void> open(
    WidgetTester tester,
    InventoryService service,
    String role,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DispenserScanScreen(
          account: Account(
            accId: 3,
            accName: 'Staff',
            accEmail: '',
            accUsername: 'staff',
            accType: role,
          ),
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final rider in [true, false]) {
    testWidgets(
      '${rider ? 'Rider' : 'Worker'} sees only permitted dispenser processes',
      (tester) async {
        await open(
          tester,
          InventoryService(),
          rider ? 'RIDER' : 'STATION_WORKER',
        );
        await tester.scrollUntilVisible(
          find.byType(DropdownButtonFormField<String>),
          150,
        );
        await tester.ensureVisible(
          find.byType(DropdownButtonFormField<String>),
        );
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        expect(find.text('Return to station'), findsWidgets);
        expect(find.text('Maintenance'), findsOneWidget);
        expect(
          find.text('Deliver to customer'),
          rider ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Pick up from customer'),
          rider ? findsOneWidget : findsNothing,
        );
      },
    );
  }

  testWidgets('inventory failure stops loading and can be retried', (
    tester,
  ) async {
    final service = InventoryService()..fail = true;
    await open(tester, service, 'RIDER');
    expect(find.text('Inventory unavailable'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    service.fail = false;
    await tester.tap(find.byTooltip('Refresh dispensers'));
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Inventory unavailable'), findsNothing);
  });

  testWidgets('dispenser screen fits small phones with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester, InventoryService(), 'STATION_WORKER');
    final save = find.widgetWithText(FilledButton, 'Save scan');
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.scrollUntilVisible(find.text('Scan dispenser QR'), 150);
    await tester.ensureVisible(find.text('Scan dispenser QR'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

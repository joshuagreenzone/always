import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/models/bottle_condition.dart';
import 'package:syawla/services/bottle_condition_service.dart';
import 'package:syawla/screens/rider/vehicle_scan_screen.dart';
import 'package:syawla/services/vehicle_bottle_service.dart';

class _InventoryService extends VehicleBottleService {
  bool fail = false;
  bool failSave = false;
  bool failVerify = false;
  bool returned = false;
  int saves = 0;
  String? savedAction;
  List<String>? savedNumbers;
  @override
  Future<Map<String, dynamic>> verify(
    int accId,
    String number,
    String action,
  ) async {
    if (failVerify) {
      throw Exception('Pick up this bottle from the customer first.');
    }
    return {'bottleNumber': number};
  }

  @override
  Future<Map<String, dynamic>> save(
    int accId,
    List<String> numbers,
    String action,
  ) async {
    saves++;
    if (failSave) throw Exception('Unable to connect to the server.');
    savedNumbers = List.of(numbers);
    savedAction = action;
    returned = true;
    return {'count': numbers.length};
  }

  @override
  Future<Map<String, dynamic>> getInventory(int accId) async {
    if (fail) throw Exception('Unable to connect to the server.');
    return {
      'bottles': [
        {
          'bottleNumber': 'LOADED-1',
          'status': 'LOADED',
          'condition': 'HEALTHY',
        },
        {
          'bottleNumber': 'COLLECTED-1',
          'status': 'COLLECTED',
          'condition': 'DAMAGED',
        },
        if (!returned)
          {
            'bottleNumber': 'COLLECTED-2',
            'status': 'COLLECTED',
            'condition': 'HEALTHY',
          },
      ],
      'returns': [
        if (returned)
          {'batchId': 2, 'count': 1, 'scannedAt': '2026-10-12 16:00:00'},
        {'batchId': 1, 'count': 4, 'scannedAt': '2026-10-12 15:00:00'},
      ],
    };
  }
}

class _HealthyConditionService extends BottleConditionService {
  @override
  Future<BottleCondition?> getCondition({
    required int accId,
    required String bottleNumber,
    bool allowUnregistered = false,
  }) async => BottleCondition(bottleNumber: bottleNumber, condition: 'HEALTHY');
}

Future<void> _openReturn(WidgetTester tester, _InventoryService service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: VehicleScanScreen(
        account: _account,
        returning: true,
        service: service,
        conditionService: _HealthyConditionService(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterBottle(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Enter Bottle Number'));
  await tester.tap(find.text('Enter Bottle Number'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'COLLECTED-2');
  await tester.tap(find.text('Add Bottle'));
  await tester.pumpAndSettle();
}

final _account = Account(
  accId: 3,
  accName: 'Rider',
  accEmail: '',
  accUsername: 'rider',
  accType: 'RIDER',
);

void main() {
  testWidgets(
    'Return screen counts only collected bottles and shows confirmed arrivals',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VehicleScanScreen(
            account: _account,
            returning: true,
            service: _InventoryService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Awaiting station return: 2'), findsOneWidget);
      expect(find.text('COLLECTED-1'), findsNothing);
      await tester.tap(find.text('View Return Inventory'));
      await tester.pumpAndSettle();
      expect(find.text('4 bottles returned'), findsOneWidget);
      expect(find.text('LOADED-1'), findsNothing);
      expect(find.text('COLLECTED-1'), findsOneWidget);
    },
  );

  testWidgets(
    'Loading screen counts loaded stock separately from customer collections',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VehicleScanScreen(
            account: _account,
            returning: false,
            service: _InventoryService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Loaded for delivery: 1'), findsOneWidget);
      expect(find.text('LOADED-1'), findsNothing);
      expect(find.textContaining('/200'), findsNothing);
      await tester.tap(find.text('View Loaded Bottles'));
      await tester.pumpAndSettle();
      expect(find.text('LOADED-1'), findsOneWidget);
      expect(find.text('COLLECTED-1'), findsNothing);
      expect(find.text('4 bottles returned'), findsNothing);
    },
  );

  testWidgets(
    'Failed inventory refresh preserves the last confirmed counts and reports failure',
    (tester) async {
      final service = _InventoryService();
      await tester.pumpWidget(
        MaterialApp(
          home: VehicleScanScreen(
            account: _account,
            returning: true,
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      service.fail = true;
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(find.text('Awaiting station return: 2'), findsOneWidget);
      expect(
        find.textContaining('Could not refresh the bottle counts.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Return remains pending until confirmation, then records arrival count',
    (tester) async {
      final service = _InventoryService();
      await _openReturn(tester, service);
      await _enterBottle(tester);
      expect(
        find.text('Bottle COLLECTED-2 added. Tap Confirm Return to save it.'),
        findsOneWidget,
      );
      expect(service.saves, 0);
      await tester.tap(find.text('Confirm Return (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Station Return?'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(service.savedAction, 'RETURN');
      expect(service.savedNumbers, ['COLLECTED-2']);
      expect(
        find.textContaining(
          '1 bottle returned to the station. Saved successfully.',
        ),
        findsWidgets,
      );
      expect(find.text('No bottles scanned yet.'), findsOneWidget);
      expect(find.textContaining('/200'), findsNothing);
      expect(find.text('Awaiting station return: 1'), findsOneWidget);
      await tester.ensureVisible(find.text('View Return Inventory'));
      await tester.tap(find.text('View Return Inventory'));
      await tester.pumpAndSettle();
      expect(find.text('1 bottle returned'), findsOneWidget);
    },
  );

  testWidgets('Rejected pickup is explained and never added to return list', (
    tester,
  ) async {
    final service = _InventoryService()..failVerify = true;
    await _openReturn(tester, service);
    await _enterBottle(tester);
    expect(
      find.text(
        'Bottle not added. Pick up this bottle from the customer first.',
      ),
      findsOneWidget,
    );
    expect(find.text('No bottles scanned yet.'), findsOneWidget);
    expect(find.textContaining('/200'), findsNothing);
    expect(service.saves, 0);
  });

  testWidgets('Failed confirmation retains scanned bottles for retry', (
    tester,
  ) async {
    final service = _InventoryService()..failSave = true;
    await _openReturn(tester, service);
    await _enterBottle(tester);
    await tester.tap(find.text('Confirm Return (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your scanned list is kept.'), findsOneWidget);
    expect(find.text('COLLECTED-2'), findsOneWidget);
    expect(find.text('Bottles to Return'), findsOneWidget);
    expect(find.text('Awaiting station return: 2'), findsOneWidget);
    service.failSave = false;
    await tester.tap(find.text('Confirm Return (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('No bottles scanned yet.'), findsOneWidget);
    expect(find.textContaining('/200'), findsNothing);
  });

  testWidgets('Return layout fits a small phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: VehicleScanScreen(
          account: _account,
          returning: true,
          service: _InventoryService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('View Return Inventory'));
    await tester.tap(find.text('View Return Inventory'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Recent Station Returns'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/models/bottle_condition.dart';
import 'package:syawla/services/bottle_condition_service.dart';
import 'package:syawla/screens/rider/vehicle_scan_screen.dart';
import 'package:syawla/services/vehicle_bottle_service.dart';
import 'package:syawla/services/scan_transition_service.dart';

class _TransitionService extends ScanTransitionService {
  final bool jump;
  _TransitionService({this.jump = false});

  @override
  Future<Map<String, dynamic>> check(String number, String eventType) async => {
    'isCycleJump': jump,
    'previousScanEventId': 1,
    'previousEventType': jump ? 'REFILL_SCAN' : 'PICKUP_SCAN',
    'expectedPreviousEventType': 'PICKUP_SCAN',
  };
}

class _InventoryService extends VehicleBottleService {
  bool fail = false;
  bool failSave = false;
  bool failVerify = false;
  bool returned = false;
  int saves = 0;
  String? savedAction;
  List<String>? savedNumbers;
  Map<String, Map<String, dynamic>>? savedJumpDetails;
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
    String action, {
    Map<String, Map<String, dynamic>> jumpDetails = const {},
  }) async {
    saves++;
    if (failSave) throw Exception('Unable to connect to the server.');
    savedNumbers = List.of(numbers);
    savedJumpDetails = Map.of(jumpDetails);
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

Future<void> _openReturn(
  WidgetTester tester,
  _InventoryService service, {
  ScanTransitionService? transitionService,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: VehicleScanScreen(
        account: _account,
        returning: true,
        service: service,
        conditionService: _HealthyConditionService(),
        transitionService: transitionService ?? _TransitionService(),
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
  for (final returning in [false, true]) {
    testWidgets(
      'Confirmed ${returning ? 'return' : 'loading'} returns home with a success message',
      (tester) async {
        final service = _InventoryService();
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Open loading'),
                  onPressed: () async {
                    final message = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VehicleScanScreen(
                          account: _account,
                          returning: returning,
                          service: service,
                          conditionService: _HealthyConditionService(),
                          transitionService: _TransitionService(),
                        ),
                      ),
                    );
                    if (!context.mounted || message == null) return;
                    await showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Loading Completed'),
                        content: Text(message),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open loading'));
        await tester.pumpAndSettle();
        await _enterBottle(tester);
        await tester.tap(
          find.text(
            returning ? 'Review and save return' : 'Review and save loading',
          ),
        );
        await tester.pumpAndSettle();
        expect(service.saves, 0);
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(service.savedAction, returning ? 'RETURN' : 'LOAD');
        expect(find.byType(VehicleScanScreen), findsNothing);
        expect(find.text('Open loading'), findsOneWidget);
        expect(
          find.text(
            returning
                ? '1 bottle returned to the station. Saved successfully.'
                : '1 bottle loaded for delivery. Saved successfully.',
          ),
          findsOneWidget,
        );
      },
    );
  }

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
      expect(find.text('Awaiting return (2)'), findsOneWidget);
      expect(find.text('COLLECTED-1'), findsNothing);
      await tester.tap(find.text('Awaiting return (2)'));
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
      expect(find.text('In vehicle (1)'), findsOneWidget);
      expect(find.text('LOADED-1'), findsNothing);
      expect(find.textContaining('/200'), findsNothing);
      await tester.tap(find.text('In vehicle (1)'));
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
      expect(find.text('Awaiting return (2)'), findsOneWidget);
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
        find.text(
          'Bottle COLLECTED-2 added. Tap Review and save return to save it.',
        ),
        findsOneWidget,
      );
      expect(service.saves, 0);
      await tester.tap(find.text('Review and save return'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Station Return?'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(service.savedAction, 'RETURN');
      expect(service.savedNumbers, ['COLLECTED-2']);
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
    await tester.scrollUntilVisible(
      find.text('Your scanned bottles will appear here.'),
      150,
    );
    expect(find.text('Your scanned bottles will appear here.'), findsOneWidget);
    expect(find.textContaining('/200'), findsNothing);
    expect(service.saves, 0);
  });

  testWidgets('A jump needs a reason and saves it with the bottle', (
    tester,
  ) async {
    final service = _InventoryService();
    await _openReturn(
      tester,
      service,
      transitionService: _TransitionService(jump: true),
    );
    await _enterBottle(tester);
    expect(find.text('A step was skipped'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Found at station');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Review and save return'), findsOneWidget);
    await tester.tap(find.text('Review and save return'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(
      service.savedJumpDetails?['collected-2']?['jumpReason'],
      'Found at station',
    );
  });

  testWidgets('Failed confirmation retains scanned bottles for retry', (
    tester,
  ) async {
    final service = _InventoryService()..failSave = true;
    await _openReturn(tester, service);
    await _enterBottle(tester);
    await tester.tap(find.text('Review and save return'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your scanned list is kept.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('COLLECTED-2'), 200);
    expect(find.text('COLLECTED-2'), findsOneWidget);
    expect(find.text('Ready to return'), findsOneWidget);
    service.failSave = false;
    await tester.tap(find.text('Review and save return'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(service.saves, 2);
    expect(service.savedAction, 'RETURN');
    expect(service.savedNumbers, ['COLLECTED-2']);
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
    await tester.ensureVisible(find.text('Awaiting return (2)'));
    await tester.tap(find.text('Awaiting return (2)'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Recent Station Returns'), 150);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

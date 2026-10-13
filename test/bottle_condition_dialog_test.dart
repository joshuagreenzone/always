import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/bottle_condition.dart';
import 'package:syawla/services/bottle_condition_service.dart';
import 'package:syawla/widgets/common/bottle_condition_dialog.dart';

class _ConditionService extends BottleConditionService {
  BottleCondition? bottle;
  int updates = 0;
  String? lastNote;
  String? lastCondition;
  Object? error;
  Completer<BottleCondition>? pending;
  bool needsRecoveryRefill = false;

  _ConditionService(this.bottle);

  @override
  Future<BottleCondition?> getCondition({
    required int accId,
    required String bottleNumber,
    bool allowUnregistered = false,
  }) async => bottle;

  @override
  Future<BottleCondition> updateCondition({
    required int accId,
    required BottleCondition bottle,
    required String condition,
    required String note,
  }) async {
    updates++;
    lastCondition = condition;
    lastNote = note.trim();
    if (error != null) throw error!;
    if (pending != null) return pending!.future;
    return BottleCondition(
      bottleNumber: bottle.bottleNumber,
      condition: condition,
      note: note.trim(),
      updatedAt: DateTime(2026, 10, 12, 14, 30),
      needsRefillAfterRecovery: needsRecoveryRefill,
    );
  }
}

Future<void> _openScannerCheck(
  WidgetTester tester,
  _ConditionService service,
  void Function(bool) onResult, {
  bool pickup = false,
  bool delivery = false,
  void Function(Object)? onError,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              try {
                onResult(
                  await checkBottleConditionForScan(
                    context: context,
                    accId: 2,
                    bottleNumber: 'RG-0001',
                    service: service,
                    allowUnregistered: true,
                    allowDamagedPickup: pickup,
                    requireRecoveryRefill: delivery,
                  ),
                );
              } catch (e) {
                if (onError == null) rethrow;
                onError(e);
              }
            },
            child: const Text('Scan'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Scan'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Delivery rejects a healthy bottle still needing recovery refill',
    (tester) async {
      final service = _ConditionService(
        const BottleCondition(
          bottleNumber: 'RG-0001',
          condition: 'HEALTHY',
          needsRefillAfterRecovery: true,
        ),
      );
      bool? result;
      Object? error;
      await _openScannerCheck(
        tester,
        service,
        (value) => result = value,
        delivery: true,
        onError: (value) => error = value,
      );
      expect(result, isNull);
      expect(error.toString(), contains('Refill it again before delivery'));
    },
  );

  testWidgets('Delivery accepts healthy bottles after the recovery refill', (
    tester,
  ) async {
    final service = _ConditionService(
      const BottleCondition(bottleNumber: 'RG-0001', condition: 'HEALTHY'),
    );
    bool? result;
    await _openScannerCheck(
      tester,
      service,
      (value) => result = value,
      delivery: true,
    );
    expect(result, true);
  });
  testWidgets(
    'Damaged pickup keeps the damaged state without requiring a note',
    (tester) async {
      final service = _ConditionService(
        const BottleCondition(bottleNumber: 'RG-0001', condition: 'DAMAGED'),
      );
      bool? result;
      await _openScannerCheck(
        tester,
        service,
        (value) => result = value,
        pickup: true,
      );
      await tester.tap(find.text('Pick Up Damaged Bottle'));
      await tester.pumpAndSettle();
      expect(result, true);
      expect(service.updates, 0);
      expect(service.bottle!.condition, 'DAMAGED');
    },
  );

  testWidgets('Missing pickup does not allow keeping the missing state', (
    tester,
  ) async {
    final service = _ConditionService(
      const BottleCondition(bottleNumber: 'RG-0001', condition: 'MISSING'),
    );
    bool? result;
    await _openScannerCheck(
      tester,
      service,
      (value) => result = value,
      pickup: true,
    );
    expect(find.text('Pick Up Damaged Bottle'), findsNothing);
    await tester.tap(find.text('Skip Bottle'));
    await tester.pumpAndSettle();
    expect(result, false);
  });

  testWidgets(
    'Restoring healthy during delivery saves but requires a fresh refill',
    (tester) async {
      final service = _ConditionService(
        const BottleCondition(bottleNumber: 'RG-0001', condition: 'MISSING'),
      )..needsRecoveryRefill = true;
      bool? result;
      await _openScannerCheck(
        tester,
        service,
        (value) => result = value,
        delivery: true,
      );
      await tester.enterText(find.byType(TextFormField), 'Found in storage');
      await tester.tap(find.text('Save State'));
      await tester.pumpAndSettle();
      expect(
        find.text('Refill this bottle again before delivery.'),
        findsOneWidget,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(service.updates, 1);
      expect(result, false);
    },
  );

  testWidgets('Restored healthy bottles can enter the refill process', (
    tester,
  ) async {
    final service = _ConditionService(
      const BottleCondition(
        bottleNumber: 'RG-0001',
        condition: 'HEALTHY',
        needsRefillAfterRecovery: true,
      ),
    );
    bool? result;
    await _openScannerCheck(tester, service, (value) => result = value);
    expect(result, true);
  });
  for (final state in ['MISSING', 'DAMAGED']) {
    testWidgets('$state bottle prompts and cannot save without a note', (
      tester,
    ) async {
      final service = _ConditionService(
        BottleCondition(bottleNumber: 'RG-0001', condition: state),
      );
      await _openScannerCheck(tester, service, (_) {});
      expect(find.text('Bottle ${state.toLowerCase()}'), findsOneWidget);
      await tester.tap(find.text('Save State'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a note before saving.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.text('Save State'));
      await tester.pumpAndSettle();
      expect(service.updates, 0);
    });
  }

  testWidgets('Skip leaves the state unchanged and rejects the scan', (
    tester,
  ) async {
    final service = _ConditionService(
      const BottleCondition(bottleNumber: 'RG-0001', condition: 'MISSING'),
    );
    bool? result;
    await _openScannerCheck(tester, service, (value) => result = value);
    await tester.tap(find.text('Skip Bottle'));
    await tester.pumpAndSettle();
    expect(result, false);
    expect(service.updates, 0);
  });

  testWidgets('Healthy update shows the recorded date and accepts the scan', (
    tester,
  ) async {
    final service = _ConditionService(
      const BottleCondition(bottleNumber: 'RG-0001', condition: 'MISSING'),
    );
    bool? result;
    await _openScannerCheck(tester, service, (value) => result = value);
    await tester.enterText(find.byType(TextFormField), ' Found in storage ');
    await tester.tap(find.text('Save State'));
    await tester.pumpAndSettle();
    expect(service.lastNote, 'Found in storage');
    expect(service.lastCondition, 'HEALTHY');
    expect(find.textContaining('Oct 12, 2026 2:30:00 PM'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, true);
  });

  testWidgets(
    'Changing missing to damaged saves the state and skips the scan',
    (tester) async {
      final service = _ConditionService(
        const BottleCondition(bottleNumber: 'RG-0001', condition: 'MISSING'),
      );
      bool? result;
      await _openScannerCheck(tester, service, (value) => result = value);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DAMAGED').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Found with a crack');
      await tester.tap(find.text('Save State'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(service.lastCondition, 'DAMAGED');
      expect(result, false);
    },
  );

  testWidgets(
    'Failed update keeps the dialog open and does not accept the scan',
    (tester) async {
      final service = _ConditionService(
        const BottleCondition(bottleNumber: 'RG-0001', condition: 'DAMAGED'),
      )..error = Exception('The bottle state changed. Scan it again.');
      bool? result;
      await _openScannerCheck(tester, service, (value) => result = value);
      await tester.enterText(
        find.byType(TextFormField),
        'Repaired and checked',
      );
      await tester.tap(find.text('Save State'));
      await tester.pumpAndSettle();
      expect(
        find.text('The bottle state changed. Scan it again.'),
        findsOneWidget,
      );
      expect(result, isNull);
      expect(find.text('Skip Bottle'), findsOneWidget);
    },
  );

  testWidgets('Repeated save taps issue only one update while saving', (
    tester,
  ) async {
    final service = _ConditionService(
      const BottleCondition(bottleNumber: 'RG-0001', condition: 'MISSING'),
    )..pending = Completer<BottleCondition>();
    await _openScannerCheck(tester, service, (_) {});
    await tester.enterText(find.byType(TextFormField), 'Recovered');
    await tester.tap(find.text('Save State'));
    await tester.pump();
    await tester.tap(find.text('Saving...'));
    expect(service.updates, 1);
    service.pending!.complete(
      const BottleCondition(bottleNumber: 'RG-0001', condition: 'HEALTHY'),
    );
    await tester.pumpAndSettle();
  });

  for (final bottle in [
    null,
    const BottleCondition(bottleNumber: 'RG-0001', condition: 'HEALTHY'),
  ]) {
    testWidgets(
      '${bottle == null ? 'Unregistered registration' : 'Healthy'} scan continues without a prompt',
      (tester) async {
        final service = _ConditionService(bottle);
        bool? result;
        await _openScannerCheck(tester, service, (value) => result = value);
        expect(result, true);
        expect(find.byType(AlertDialog), findsNothing);
        expect(service.updates, 0);
      },
    );
  }
}

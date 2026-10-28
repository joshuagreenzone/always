import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/models/bottle_condition.dart';
import 'package:syawla/screens/bottles/bottle_state_screen.dart';
import 'package:syawla/services/bottle_condition_service.dart';

class _Service extends BottleConditionService {
  BottleCondition bottle = BottleCondition(
    bottleNumber: 'RG-1046',
    condition: 'HEALTHY',
  );
  bool fail = false;
  String? requestedNumber;
  String? savedState;

  @override
  Future<BottleCondition?> getCondition({
    required int accId,
    required String bottleNumber,
    bool allowUnregistered = false,
  }) async {
    requestedNumber = bottleNumber;
    if (fail) throw Exception('Connection unavailable');
    return bottle;
  }

  @override
  Future<BottleCondition> updateCondition({
    required int accId,
    required BottleCondition bottle,
    required String condition,
    required String note,
    List<int> repairSupplyIds = const [],
  }) async {
    savedState = condition;
    return this.bottle = BottleCondition(
      bottleNumber: bottle.bottleNumber,
      condition: condition,
      note: note,
    );
  }
}

void main() {
  final account = Account(
    accId: 2,
    accName: 'Station worker',
    accEmail: '',
    accUsername: 'worker',
    accType: 'STATION_WORKER',
  );

  testWidgets('worker can scan a healthy bottle and report damage', (
    tester,
  ) async {
    final service = _Service();
    await tester.pumpWidget(
      MaterialApp(
        home: BottleStateScreen(
          account: account,
          service: service,
          scanCode: (_) async => 'RG-1046',
        ),
      ),
    );
    await tester.tap(find.text('Scan bottle QR'));
    await tester.pumpAndSettle();
    expect(service.requestedNumber, 'RG-1046');
    await tester.tap(find.text('Update bottle state'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Cracked bottle');
    await tester.ensureVisible(find.text('Save condition'));
    await tester.tap(find.text('Save condition'));
    await tester.pumpAndSettle();
    expect(service.savedState, 'DAMAGED');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('DAMAGED'), findsOneWidget);
    expect(find.text('Cracked bottle'), findsOneWidget);
  });

  testWidgets('manual lookup can retry after a connection error', (
    tester,
  ) async {
    final service = _Service()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: BottleStateScreen(account: account, service: service),
      ),
    );
    await tester.enterText(find.byType(TextField), ' RG-1046 ');
    await tester.tap(find.text('Find bottle'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connection unavailable'), findsOneWidget);
    service.fail = false;
    await tester.tap(find.text('Find bottle'));
    await tester.pumpAndSettle();
    expect(service.requestedNumber, 'RG-1046');
    expect(find.text('HEALTHY'), findsOneWidget);
    expect(find.textContaining('Connection unavailable'), findsNothing);
  });
}

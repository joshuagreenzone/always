import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/bottle_condition.dart';
import 'package:syawla/models/bottle_type.dart';
import 'package:syawla/services/bottle_service.dart';
import 'package:syawla/services/scan_lookup_service.dart';
import 'package:syawla/widgets/common/unregistered_qr_dialog.dart';

class _Lookup extends ScanLookupService {
  final bool isNew;
  _Lookup(this.isNew);
  @override
  Future<ScanLookup> get(int accId, String number, String eventType) async =>
      ScanLookup(BottleCondition(bottleNumber: number, condition: 'HEALTHY'), {
        'isCycleJump': false,
      }, isNewUnregistered: isNew);
}

class _Types extends BottleService {
  int loads = 0;
  @override
  Future<List<BottleType>> getBottleTypes() async {
    loads++;
    return [BottleType(bottleTypeId: 9, bottleType: 'Round', price: 30)];
  }
}

void main() {
  for (final action in ['choose', 'cancel', 'existing']) {
    testWidgets('$action type selection keeps scans local to the batch', (
      tester,
    ) async {
      final types = _Types();
      ScanLookup? result;
      Object? error;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  try {
                    result = await lookupBottleForScan(
                      context,
                      _Lookup(action != 'existing'),
                      3,
                      'external-123',
                      'REFILL_SCAN',
                      bottleService: types,
                    );
                  } catch (e) {
                    error = e;
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
      if (action == 'existing') {
        expect(types.loads, 0);
        expect(result, isNotNull);
        expect(find.text('Choose bottle type'), findsNothing);
        return;
      }
      expect(result, isNull);
      expect(find.text('Choose bottle type'), findsOneWidget);
      await tester.tap(
        find.text(action == 'choose' ? 'Round · ₱30.00' : 'Cancel scan'),
      );
      await tester.pumpAndSettle();
      if (action == 'choose') {
        expect(result!.transition['bottleTypeId'], 9);
        expect(result!.transition['bottleType'], 'Round');
        expect(result!.transition['price'], 30);
        expect(error, isNull);
      } else {
        expect(result, isNull);
        expect(error, isNotNull);
      }
    });
  }
}

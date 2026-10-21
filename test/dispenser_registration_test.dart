import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/screens/station_worker/dispenser_registration_screen.dart';
import 'package:syawla/services/dispenser_service.dart';

class RegistrationService extends DispenserService {
  bool fail = false;
  Map<String, dynamic>? saved;

  @override
  Future<Map<String, dynamic>> register({
    required int accId,
    required String dispenserNumber,
    required String brand,
    required String model,
    required String dispenserAcquisition,
    required String dispenserPaymentStatus,
    required double dispenserCost,
  }) async {
    if (fail) throw Exception('Dispenser number is already registered.');
    saved = {'number': dispenserNumber, 'brand': brand, 'cost': dispenserCost};
    return saved!;
  }
}

void main() {
  Future<void> open(WidgetTester tester, RegistrationService service) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DispenserRegistrationScreen(
          account: Account(
            accId: 7,
            accName: 'Worker',
            accEmail: 'worker@example.invalid',
            accUsername: 'worker',
            accType: 'STATION_WORKER',
          ),
          service: service,
          scanCode: (_) async => ' dsp-001 ',
        ),
      ),
    );
    await tester.tap(find.text('Scan Dispenser QR'));
    await tester.pumpAndSettle();
  }

  testWidgets('scan opens details and saves a free dispenser', (tester) async {
    final service = RegistrationService();
    await open(tester, service);
    expect(find.text('DSP-001'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Brand'),
      'Sample',
    );
    await tester.scrollUntilVisible(
      find.text('Register Dispenser'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Register Dispenser'));
    await tester.pumpAndSettle();
    expect(service.saved, {
      'number': 'DSP-001',
      'brand': 'Sample',
      'cost': 0.0,
    });
    expect(find.text('Scan Dispenser QR'), findsOneWidget);
    expect(
      find.text('Dispenser DSP-001 registered successfully.'),
      findsOneWidget,
    );
  });

  testWidgets('duplicate registration retains scanned details for correction', (
    tester,
  ) async {
    final service = RegistrationService()..fail = true;
    await open(tester, service);
    await tester.scrollUntilVisible(
      find.text('Register Dispenser'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Register Dispenser'));
    await tester.pumpAndSettle();
    expect(
      find.text('Dispenser number is already registered.'),
      findsOneWidget,
    );
    expect(find.text('DSP-001'), findsOneWidget);
    expect(service.saved, isNull);
  });
}

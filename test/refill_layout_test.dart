import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/screens/refill/refill_screen.dart';
import 'package:syawla/widgets/common/bottle_scanner_view.dart';

void main() {
  testWidgets('Refill supports scanning on a small phone with large text', (
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
        home: RefillScreen(
          account: Account(
            accId: 3,
            accName: 'Worker',
            accEmail: '',
            accUsername: 'worker',
            accType: 'STATION_WORKER',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Review and save refill');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Start Scanning'), 100);
    await tester.ensureVisible(find.text('Start Scanning'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Scanning'));
    await tester.pumpAndSettle();
    expect(find.byType(BottleScannerView), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Stop Camera'), 100);
    await tester.ensureVisible(find.text('Stop Camera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop Camera'));
    await tester.pumpAndSettle();
    expect(find.byType(BottleScannerView), findsNothing);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

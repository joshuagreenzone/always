import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/screens/home/home_screen.dart';

void main() {
  Account account(List<String> roles) => Account(
    accId: 7,
    accName: 'Rider Worker',
    accEmail: 'staff@example.invalid',
    accUsername: 'staff',
    accType: roles.first,
    accRoles: roles,
  );

  testWidgets('dual role account can open refill from rider home', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(account: account(['STATION_WORKER', 'RIDER'])),
      ),
    );
    expect(find.text('Assigned Orders'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Refill'), 250);
    expect(find.text('Refill'), findsOneWidget);
  });

  testWidgets('rider without worker role has no refill action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(account: account(['RIDER']))),
    );
    expect(find.text('Assigned Orders'), findsOneWidget);
    expect(find.text('Refill'), findsNothing);
  });
}

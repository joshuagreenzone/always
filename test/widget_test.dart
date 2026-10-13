import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/widgets/login/login_form.dart';

void main() {
  testWidgets('Login requires username and password before calling the API', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LoginForm())),
    );
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(
      find.text('Please enter your username and password.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNWidgets(2));
  });
}

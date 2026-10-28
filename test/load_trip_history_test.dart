import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/widgets/common/load_trip_history.dart';

final _trips = <Map<String, dynamic>>[
  {
    'batchCode': '102826-12',
    'count': 18,
    'carriedCount': 2,
    'scannedAt': '2026-10-28 14:30:00',
    'bottles': [
      {'bottleNumber': 'RG-0001', 'isCarryOver': 1},
      {'bottleNumber': 'SG-0002', 'isCarryOver': 0},
    ],
  },
];

void main() {
  testWidgets('trip card shows counts and opens clear bottle details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              LoadTripSummary(count: 12, loading: false, onViewTrips: () {}),
              LoadTripHistory(trips: _trips),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Trips today'), findsOneWidget);
    expect(find.text('18 bottles'), findsOneWidget);
    expect(find.text('16 new'), findsOneWidget);
    expect(find.text('2 carried over'), findsOneWidget);
    await tester.tap(find.text('102826-12'));
    await tester.pumpAndSettle();
    expect(find.text('RG-0001'), findsOneWidget);
    expect(find.text('Carried over'), findsOneWidget);
    expect(find.text('SG-0002'), findsOneWidget);
    expect(find.text('Newly loaded'), findsOneWidget);
    await tester.tap(find.byTooltip('Close trip details'));
    await tester.pumpAndSettle();
    expect(find.text('TRIP DETAILS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trip summary and cards fit a narrow phone with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LoadTripSummary(count: 12, loading: false, onViewTrips: () {}),
              LoadTripHistory(trips: _trips),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('102826-12'), 160);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('102826-12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('102826-12'));
    await tester.pumpAndSettle();
    expect(find.text('RG-0001'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty history gives a useful state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LoadTripHistory(trips: [])),
      ),
    );
    expect(find.text('No loading trips yet'), findsOneWidget);
    expect(
      find.text('Your trips will appear here after you save a load batch.'),
      findsOneWidget,
    );
  });
}

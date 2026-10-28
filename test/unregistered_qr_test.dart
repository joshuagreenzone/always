import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/qr_registration.dart';
import 'package:syawla/widgets/common/rider_scan_card.dart';

void main() {
  test('only complete supported QR formats count as registered formats', () {
    for (final qr in ['A-0000', 'RG-0123', 'SG-9999', 'rg-0001']) {
      expect(isUnregisteredQr(qr), isFalse);
    }
    for (final qr in [
      'external-123',
      'RG-other',
      'SG',
      'A-12345',
      'https://bottle/1',
    ]) {
      expect(isUnregisteredQr(qr), isTrue);
    }
  });

  testWidgets('external QR is orange and removable in the same batch', (
    tester,
  ) async {
    final bottles = ['A-0001', 'external-123'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PendingBottleList(
              title: 'Batch',
              bottles: bottles,
              onRemove: (number) => setState(() => bottles.remove(number)),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Unregistered QR · Ready to confirm'), findsOneWidget);
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles[0].tileColor, isNull);
    expect(tiles[1].tileColor, Colors.orange.shade50);
    await tester.tap(find.byTooltip('Remove external-123 from scanned list'));
    await tester.pump();
    expect(find.text('external-123'), findsNothing);
    expect(bottles, ['A-0001']);
  });
}

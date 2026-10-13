import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:syawla/services/batch_scan_location.dart';

Position position(double latitude) => Position(
  longitude: 121,
  latitude: latitude,
  timestamp: DateTime(2026),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  test('one fix is shared by concurrent and subsequent bottles', () async {
    var calls = 0;
    final pending = Completer<Position>();
    final batch = BatchScanLocation(
      locate: () {
        calls++;
        return pending.future;
      },
    );
    final first = batch.get();
    final second = batch.get();
    final fix = position(14);
    pending.complete(fix);
    expect(await first, same(fix));
    expect(await second, same(fix));
    expect(await batch.get(), same(fix));
    expect(calls, 1);
  });

  test('failed GPS lookup can be retried', () async {
    var calls = 0;
    final batch = BatchScanLocation(
      locate: () async {
        if (++calls == 1) throw Exception('Permission denied');
        return position(14);
      },
    );
    await expectLater(batch.get(), throwsException);
    expect((await batch.get()).latitude, 14);
    await batch.get();
    expect(calls, 2);
  });

  test('a new batch gets a fresh location', () async {
    var calls = 0;
    final batch = BatchScanLocation(
      locate: () async => position((++calls).toDouble()),
    );
    expect((await batch.get()).latitude, 1);
    batch.clear();
    expect((await batch.get()).latitude, 2);
    expect(calls, 2);
  });
}

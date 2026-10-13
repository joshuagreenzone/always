import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/bottle_condition.dart';
import 'package:syawla/services/bottle_condition_service.dart';

class _Adapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) respond;

  _Adapter(this.respond);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> data, int status) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

BottleConditionService _service(ResponseBody Function(RequestOptions) respond) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost/'))
    ..httpClientAdapter = _Adapter(respond);
  return BottleConditionService(dio: dio);
}

void main() {
  test(
    'Lookup sends account and QR and parses the saved note and date',
    () async {
      final service = _service((options) {
        expect(options.method, 'GET');
        expect(options.queryParameters, {
          'accId': 2,
          'bottleNumber': 'RG-0001',
        });
        return _json({
          'success': true,
          'data': {
            'bottleNumber': 'RG-0001',
            'condition': 'MISSING',
            'note': 'Not returned',
            'updatedAt': '2026-10-12 14:30:00.123456',
          },
        }, 200);
      });
      final bottle = await service.getCondition(
        accId: 2,
        bottleNumber: 'RG-0001',
      );
      expect(bottle!.isHealthy, false);
      expect(bottle.note, 'Not returned');
      expect(bottle.updatedAt, DateTime(2026, 10, 12, 14, 30, 0, 123, 456));
    },
  );

  test('Unknown bottles are permitted only during registration', () async {
    final service = _service(
      (_) => _json({'success': false, 'message': 'Bottle not found.'}, 404),
    );
    expect(
      await service.getCondition(
        accId: 2,
        bottleNumber: 'NEW',
        allowUnregistered: true,
      ),
      isNull,
    );
    await expectLater(
      service.getCondition(accId: 3, bottleNumber: 'NEW'),
      throwsA(isA<Exception>()),
    );
  });

  test('Updates send the observed state and trimmed required note', () async {
    final service = _service((options) {
      expect(options.method, 'POST');
      expect(options.data, {
        'accId': 3,
        'bottleNumber': 'RG-0001',
        'expectedCondition': 'MISSING',
        'condition': 'HEALTHY',
        'note': 'Found at station',
      });
      return _json({
        'success': true,
        'data': {'bottleNumber': 'RG-0001', 'condition': 'HEALTHY'},
      }, 200);
    });
    final updated = await service.updateCondition(
      accId: 3,
      bottle: const BottleCondition(
        bottleNumber: 'RG-0001',
        condition: 'MISSING',
      ),
      condition: 'HEALTHY',
      note: ' Found at station ',
    );
    expect(updated.isHealthy, true);
  });

  test('Server conflicts surface as a useful message', () async {
    final service = _service(
      (_) => _json({
        'success': false,
        'message': 'The bottle state changed.',
      }, 409),
    );
    await expectLater(
      service.updateCondition(
        accId: 2,
        bottle: const BottleCondition(
          bottleNumber: 'RG-0001',
          condition: 'MISSING',
        ),
        condition: 'HEALTHY',
        note: 'Found',
      ),
      throwsA(
        predicate((e) => e.toString().contains('The bottle state changed.')),
      ),
    );
  });

  test('Unknown server states cannot silently pass as healthy', () async {
    final service = _service(
      (_) => _json({
        'success': true,
        'data': {'bottleNumber': 'RG-0001', 'condition': 'ACTIVE'},
      }, 200),
    );
    await expectLater(
      service.getCondition(accId: 2, bottleNumber: 'RG-0001'),
      throwsFormatException,
    );
  });
}

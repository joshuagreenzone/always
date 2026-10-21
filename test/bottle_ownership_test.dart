import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/models/account.dart';
import 'package:syawla/models/bottle_condition.dart';
import 'package:syawla/screens/station_worker/bottle_registration_screen.dart';
import 'package:syawla/services/bottle_condition_service.dart';
import 'package:syawla/services/bottle_service.dart';
import 'package:syawla/widgets/common/bottle_condition_dialog.dart';

class _Adapter implements HttpClientAdapter {
  final Map<String, dynamic> Function(RequestOptions) respond;
  _Adapter(this.respond);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(respond(options)),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  void close({bool force = false}) {}
}

Dio _dio(Map<String, dynamic> Function(RequestOptions) respond) =>
    Dio(BaseOptions(baseUrl: 'http://localhost/'))
      ..httpClientAdapter = _Adapter(respond);

Map<String, dynamic> _bottle(String owner) => {
  'bottleId': 1,
  'bottleNumber': 'RG-9001',
  'bottleTypeId': 1,
  'bottleType': 'Round',
  'bottleBrand': '',
  'bottleCondition': 'SECOND_HAND',
  'bottleOwner': owner,
  'bottleCost': 0,
  'bottleRegDateTime': '2026-10-20 10:00:00',
};

void main() {
  for (final owner in ['COMPANY', 'CUSTOMER']) {
    test(
      '$owner is sent by single and batch registration and read from responses',
      () async {
        final requests = <RequestOptions>[];
        final service = BottleService(
          dio: _dio((options) {
            requests.add(options);
            expect(options.data['bottleOwner'], owner);
            return {
              'success': true,
              'data': options.path.endsWith('register_bottles_batch.php')
                  ? {
                      'bottles': [_bottle(owner)],
                      'existingBottles': ['ALREADY-REGISTERED'],
                    }
                  : {'bottle': _bottle(owner)},
            };
          }),
        );
        final single = await service.registerBottle(
          accId: 2,
          bottleNumber: 'RG-9001',
          bottleTypeId: 1,
          bottleCondition: 'SECOND_HAND',
          bottleCost: 0,
          bottleOwner: owner,
        );
        final batch = await service.registerBottlesBatch(
          accId: 2,
          bottleNumbers: ['RG-9001'],
          bottleTypeId: 1,
          bottleCondition: 'SECOND_HAND',
          bottleCost: 0,
          bottleOwner: owner,
        );
        expect(single.bottleOwner, owner);
        expect(batch.registeredBottles.single.bottleOwner, owner);
        expect(batch.existingBottles, ['ALREADY-REGISTERED']);
        expect(requests.length, 2);
      },
    );

    testWidgets(
      '$owner bottle passes the shared scanner check with ownership visible',
      (tester) async {
        bool? accepted;
        final service = BottleConditionService(
          dio: _dio(
            (_) => {
              'success': true,
              'data': {
                'bottleNumber': 'RG-9001',
                'condition': 'HEALTHY',
                'bottleOwner': owner,
              },
            },
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    accepted = await checkBottleConditionForScan(
                      context: context,
                      accId: 2,
                      bottleNumber: 'RG-9001',
                      service: service,
                    );
                  },
                  child: const Text('Scan'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Scan'));
        await tester.pumpAndSettle();
        expect(accepted, isTrue);
        expect(
          find.text(
            'RG-9001 · ${owner == 'CUSTOMER' ? 'Customer bottle' : 'Company bottle'}',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('Legacy scan responses default to company ownership', () {
    expect(
      BottleCondition.fromJson({'bottleNumber': 'RG-1', 'condition': 'HEALTHY'})
          .bottleOwner,
      'COMPANY',
    );
  });

  test(
    'Bottle list reads ownership from the existing list response shape',
    () async {
      final service = BottleService(
        dio: _dio(
          (_) => {
            'success': true,
            'data': [
              {
                'BottleID': 1,
                'BottleNumber': 'RG-9001',
                'BottleTypeID': 1,
                'BottleType': 'Round',
                'BottleOwner': 'CUSTOMER',
                'Price': 10,
                'BottleRegDateTime': '2026-10-20 10:00:00',
              },
            ],
          },
        ),
      );
      expect((await service.getBottles()).single.bottleOwner, 'CUSTOMER');
    },
  );

  testWidgets('Registration offers company and customer ownership', (
    tester,
  ) async {
    final service = BottleService(
      dio: _dio(
        (_) => {
          'success': true,
          'data': {'bottleTypes': []},
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BottleRegistrationScreen(
          account: Account(
            accId: 2,
            accName: 'Worker',
            accEmail: '',
            accUsername: 'worker',
            accType: 'STATION_WORKER',
          ),
          bottleService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bottle owner'), findsOneWidget);
    await tester.tap(find.text('Company bottle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customer bottle').last);
    await tester.pumpAndSettle();
    expect(find.text('Customer bottle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

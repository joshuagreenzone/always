import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/services/scan_lookup_service.dart';

void main() {
  test(
    'condition and transition share a single request for each bottle',
    () async {
      var requests = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            expect(options.queryParameters['eventType'], 'PICKUP_SCAN');
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'success': true,
                  'data': {
                    'bottleNumber': options.queryParameters['bottleNumber'],
                    'condition': 'HEALTHY',
                    'transition': {
                      'isCycleJump': false,
                      'previousScanEventId': 7,
                    },
                  },
                },
              ),
            );
          },
        ),
      );
      final service = ScanLookupService(dio: dio);
      final first = await service.get(3, 'A', 'PICKUP_SCAN');
      final second = await service.get(3, 'B', 'PICKUP_SCAN');
      expect(requests, 2);
      expect(first.condition.bottleNumber, 'A');
      expect(second.condition.bottleNumber, 'B');
      expect(first.transition['previousScanEventId'], 7);
    },
  );
}

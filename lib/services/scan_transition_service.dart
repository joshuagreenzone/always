import 'package:dio/dio.dart';

import 'api_service.dart';

class ScanTransitionService {
  final Dio _dio;
  ScanTransitionService({Dio? dio}) : _dio = dio ?? ApiService().dio;

  Future<Map<String, dynamic>> check(String number, String eventType) async {
    try {
      final response = await _dio.get(
        'api/bottles/scan_transition.php',
        queryParameters: {'bottleNumber': number, 'eventType': eventType},
      );
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        throw Exception(
          body is Map ? body['message'] : 'Unable to check scan history.',
        );
      }
      return Map<String, dynamic>.from(body['data']);
    } on DioException catch (e) {
      final body = e.response?.data;
      throw Exception(
        body is Map ? body['message'] : 'Unable to check scan history.',
      );
    }
  }
}

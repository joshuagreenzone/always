import 'package:dio/dio.dart';

import 'api_service.dart';

class VehicleBottleService {
  final Dio _dio;
  VehicleBottleService({Dio? dio}) : _dio = dio ?? ApiService().dio;

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.request(
        'api/rider/vehicle_bottles.php',
        options: Options(method: method),
        queryParameters: method == 'GET' ? data : null,
        data: method == 'POST' ? data : null,
      );
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        throw Exception(
          body is Map
              ? body['message'] ?? 'Invalid server response.'
              : 'Invalid server response.',
        );
      }
      return Map<String, dynamic>.from(body['data']);
    } on DioException catch (e) {
      final body = e.response?.data;
      throw Exception(
        body is Map
            ? body['message'] ?? 'Unable to process bottle.'
            : 'Unable to connect to the server.',
      );
    }
  }

  Future<Map<String, dynamic>> getInventory(int accId) =>
      _request('GET', {'accId': accId});
  Future<Map<String, dynamic>> verify(
    int accId,
    String number,
    String action,
  ) => _request('GET', {
    'accId': accId,
    'bottleNumber': number,
    'action': action,
  });
  Future<Map<String, dynamic>> save(
    int accId,
    List<String> numbers,
    String action, {
    Map<String, Map<String, dynamic>> jumpDetails = const {},
    Map<String, dynamic>? loadContext,
    String? requestKey,
  }) => _request('POST', {
    'accId': accId,
    'bottleNumbers': numbers,
    'action': action,
    'jumpDetails': jumpDetails,
    'loadContext': ?loadContext,
    'requestKey': ?requestKey,
  });
}

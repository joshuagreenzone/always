import 'package:dio/dio.dart';

import '../models/bottle_condition.dart';
import 'api_service.dart';

class BottleConditionService {
  final Dio _dio;

  BottleConditionService({Dio? dio}) : _dio = dio ?? ApiService().dio;

  Future<BottleCondition?> getCondition({
    required int accId,
    required String bottleNumber,
    bool allowUnregistered = false,
  }) async {
    try {
      final response = await _dio.get(
        'api/bottles/get_bottle_condition.php',
        queryParameters: {'accId': accId, 'bottleNumber': bottleNumber},
      );
      return _parseResponse(response.data);
    } on DioException catch (e) {
      if (allowUnregistered && e.response?.statusCode == 404) return null;
      throw Exception(_errorMessage(e));
    }
  }

  Future<BottleCondition> updateCondition({
    required int accId,
    required BottleCondition bottle,
    required String condition,
    required String note,
  }) async {
    try {
      final response = await _dio.post(
        'api/bottles/update_bottle_condition.php',
        data: {
          'accId': accId,
          'bottleNumber': bottle.bottleNumber,
          'expectedCondition': bottle.condition,
          'condition': condition,
          'note': note.trim(),
        },
      );
      return _parseResponse(response.data);
    } on DioException catch (e) {
      throw Exception(_errorMessage(e));
    }
  }

  BottleCondition _parseResponse(dynamic data) {
    if (data is! Map || data['success'] != true || data['data'] is! Map) {
      throw Exception(
        data is Map
            ? data['message']?.toString() ?? 'Unable to read the bottle state.'
            : 'Invalid response from server.',
      );
    }
    return BottleCondition.fromJson(Map<String, dynamic>.from(data['data']));
  }

  String _errorMessage(DioException e) {
    final data = e.response?.data;
    return data is Map && data['message'] != null
        ? data['message'].toString()
        : 'Unable to connect to the server. Please try again.';
  }
}

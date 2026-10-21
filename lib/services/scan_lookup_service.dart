import 'package:dio/dio.dart';

import '../models/bottle_condition.dart';
import 'api_service.dart';

class ScanLookup {
  final BottleCondition condition;
  final Map<String, dynamic> transition;
  final Map<String, dynamic>? vehicle;
  const ScanLookup(this.condition, this.transition, {this.vehicle});
}

/// One read-only request for a bottle's condition and expected scan step.
class ScanLookupService {
  final Dio _dio;
  ScanLookupService({Dio? dio}) : _dio = dio ?? ApiService().dio;

  Future<ScanLookup> get(int accId, String number, String eventType) async {
    try {
      final response = await _dio.get(
        'api/bottles/get_bottle_condition.php',
        queryParameters: {
          'accId': accId,
          'bottleNumber': number,
          'eventType': eventType,
        },
      );
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        throw Exception(
          body is Map
              ? body['message'] ?? 'Unable to check bottle.'
              : 'Invalid scan response.',
        );
      }
      final data = Map<String, dynamic>.from(body['data']);
      if (data['transition'] is! Map) {
        throw Exception(
          'Update the mobile API to support combined scan checks.',
        );
      }
      return ScanLookup(
        BottleCondition.fromJson(data),
        Map<String, dynamic>.from(data['transition']),
        vehicle: data['vehicle'] is Map
            ? Map<String, dynamic>.from(data['vehicle'])
            : null,
      );
    } on DioException catch (error) {
      final body = error.response?.data;
      throw Exception(
        body is Map
            ? body['message'] ?? 'Unable to check bottle.'
            : 'Unable to connect to the server.',
      );
    }
  }
}

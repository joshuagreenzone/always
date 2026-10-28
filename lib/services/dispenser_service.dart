import 'package:dio/dio.dart';

import 'api_service.dart';

class DispenserService {
  final Dio _dio;
  DispenserService({Dio? dio}) : _dio = dio ?? ApiService().dio;

  Future<Map<String, dynamic>> _request(
    String endpoint, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _dio.request(
        'api/dispensers/$endpoint.php',
        options: Options(method: data == null ? 'GET' : 'POST'),
        data: data,
      );
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        throw Exception(
          body is Map
              ? body['message'] ?? 'Invalid response.'
              : 'Invalid response.',
        );
      }
      return Map<String, dynamic>.from(body['data']);
    } on DioException catch (error) {
      final body = error.response?.data;
      throw Exception(
        body is Map
            ? body['message'] ?? 'Dispenser request failed.'
            : 'Unable to connect to the server.',
      );
    }
  }

  Future<Map<String, dynamic>> inventory() => _request('inventory');

  Future<Map<String, dynamic>> register({
    required int accId,
    required String dispenserNumber,
    required String brand,
    required String model,
    required String dispenserAcquisition,
    required String dispenserPaymentStatus,
    required double dispenserCost,
  }) => _request(
    'register',
    data: {
      'accId': accId,
      'dispenserNumber': dispenserNumber,
      'brand': brand,
      'model': model,
      'dispenserAcquisition': dispenserAcquisition,
      'dispenserPaymentStatus': dispenserPaymentStatus,
      'dispenserCost': dispenserCost,
    },
  );

  Future<Map<String, dynamic>> scan({
    required int accId,
    required String dispenserNumber,
    required String eventType,
    int? customerId,
    String? jumpReason,
  }) => _request(
    'scan',
    data: {
      'accId': accId,
      'dispenserNumber': dispenserNumber,
      'eventType': eventType,
      'customerId': ?customerId,
      'jumpReason': ?jumpReason,
    },
  );

  Future<Map<String, dynamic>> maintenance({
    required int accId,
    required String dispenserNumber,
    required String maintenanceNote,
    required String workDone,
    required String locationType,
    int? customerId,
    String? locationNote,
    String? newPhysicalState,
  }) => _request(
    'maintenance',
    data: {
      'accId': accId,
      'dispenserNumber': dispenserNumber,
      'maintenanceNote': maintenanceNote,
      'workDone': workDone,
      'locationType': locationType,
      'customerId': ?customerId,
      if (locationNote != null && locationNote.isNotEmpty)
        'locationNote': locationNote,
      if (newPhysicalState != null && newPhysicalState.isNotEmpty)
        'newPhysicalState': newPhysicalState,
      'performedAt': DateTime.now()
          .toIso8601String()
          .substring(0, 19)
          .replaceFirst('T', ' '),
    },
  );
}

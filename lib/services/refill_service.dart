import 'package:dio/dio.dart';

import '../models/bottle.dart';
import '../models/refill.dart';
import 'api_service.dart';

class RefillService {
  final ApiService _apiService = ApiService();

  // ------------------------------------------------------------
  // VERIFY BOTTLE
  // ------------------------------------------------------------

  Future<Bottle> verifyBottle(String bottleNumber) async {
    try {
      final response = await _apiService.dio.get(
        'api/refill/verify_refill_bottle.php',
        queryParameters: {'bottleNumber': bottleNumber},
      );

      if (response.data['success'] != true) {
        throw RefillException(
          response.data['message']?.toString() ??
              'This bottle cannot be refilled.',
        );
      }

      return Bottle.fromJson(Map<String, dynamic>.from(response.data['data']));
    } on DioException catch (e) {
      final responseData = e.response?.data;

      if (responseData is Map && responseData['message'] != null) {
        throw RefillException(responseData['message'].toString());
      }

      throw Exception(_getDioMessage(e));
    }
  }

  // ------------------------------------------------------------
  // CREATE REFILL
  // ------------------------------------------------------------

  Future<Map<String, dynamic>> createRefill({
    required int accId,
    required String bottleNumber,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    try {
      final response = await _apiService.dio.post(
        'api/refill/create_refill.php',
        data: {
          'accId': accId,
          'bottleNumber': bottleNumber,
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
        },
      );

      if (response.data['success'] != true) {
        final message = response.data['message']?.toString();

        if (message != null && message.toLowerCase().contains('already')) {
          throw RefillException('This bottle has already been scanned.');
        }

        throw RefillException(message ?? 'Unable to record refill.');
      }

      return Map<String, dynamic>.from(response.data['data'] ?? {});
    } on DioException catch (e) {
      // HTTP 409 = duplicate/conflicting refill scan.
      if (e.response?.statusCode == 409) {
        final responseData = e.response?.data;

        if (responseData is Map && responseData['message'] != null) {
          throw RefillException(responseData['message'].toString());
        }

        throw RefillException('This bottle has already been scanned.');
      }

      final responseData = e.response?.data;

      if (responseData is Map && responseData['message'] != null) {
        throw RefillException(responseData['message'].toString());
      }

      throw Exception(_getDioMessage(e));
    }
  }

  // ------------------------------------------------------------
  // GET CURRENT REFILLED BOTTLES
  // ------------------------------------------------------------

  Future<List<Refill>> getRefills() async {
    try {
      final response = await _apiService.dio.get('api/refill/get_refills.php');

      if (response.data['success'] != true) {
        throw Exception(
          response.data['message']?.toString() ??
              'Unable to load refilled bottles.',
        );
      }

      final List<dynamic> data = response.data['data'] ?? [];

      return data
          .map((item) => Refill.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on DioException catch (e) {
      throw Exception(_getDioMessage(e));
    }
  }

  // ------------------------------------------------------------
  // GET REFILL HISTORY
  // ------------------------------------------------------------

  Future<List<Refill>> getRefillHistory() async {
    try {
      final response = await _apiService.dio.get(
        'api/refill/get_refill_history.php',
      );

      if (response.data['success'] != true) {
        throw Exception(
          response.data['message']?.toString() ??
              'Unable to load refill history.',
        );
      }

      final List<dynamic> data = response.data['data'] ?? [];

      return data
          .map((item) => Refill.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on DioException catch (e) {
      throw Exception(_getDioMessage(e));
    }
  }

  // ------------------------------------------------------------
  // DIO ERROR MESSAGE
  // ------------------------------------------------------------

  String _getDioMessage(DioException e) {
    final statusCode = e.response?.statusCode;

    if (statusCode == 400) {
      final responseData = e.response?.data;

      if (responseData is Map && responseData['message'] != null) {
        return responseData['message'].toString();
      }

      return 'Invalid refill request.';
    }

    if (statusCode == 404) {
      return 'Bottle not found.';
    }

    if (statusCode == 409) {
      return 'This bottle has already been scanned.';
    }

    if (statusCode == 500) {
      return 'Server error. Please try again.';
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Unable to connect to the server.';
    }

    return 'Unable to process the request.';
  }
}

// ------------------------------------------------------------
// REFILL EXCEPTION
// ------------------------------------------------------------

class RefillException implements Exception {
  final String message;

  RefillException(this.message);

  @override
  String toString() => message;
}

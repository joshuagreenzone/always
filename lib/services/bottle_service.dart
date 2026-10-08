import 'package:dio/dio.dart';

import '../models/bottle.dart';
import '../models/bottle_registration.dart';
import '../models/bottle_type.dart';
import 'api_service.dart';

class BottleBatchRegistrationException implements Exception {
  final String message;
  final String? bottleNumber;
  final String? errorType;

  const BottleBatchRegistrationException({
    required this.message,
    this.bottleNumber,
    this.errorType,
  });

  @override
  String toString() => message;
}

/// Result returned after registering a batch of bottles.
///
/// [registeredBottles] contains bottles that were newly inserted
/// into the database.
///
/// [existingBottles] contains QR values that were already registered
/// in the database and were therefore skipped.
class BottleBatchRegistrationResult {
  final List<BottleRegistration> registeredBottles;
  final List<String> existingBottles;

  const BottleBatchRegistrationResult({
    required this.registeredBottles,
    required this.existingBottles,
  });
}

class BottleService {
  final ApiService _apiService = ApiService();

  Future<List<Bottle>> getBottles() async {
    try {
      final response = await _apiService.dio.get('api/bottles/get_bottles.php');

      final responseData = Map<String, dynamic>.from(response.data);

      if (responseData['success'] != true) {
        throw Exception(
          responseData['message']?.toString() ?? 'Unable to load bottles.',
        );
      }

      final dynamic data = responseData['data'];

      if (data is! Map) {
        throw Exception('Invalid response from server.');
      }

      final dynamic rawBottles = data['bottles'];

      if (rawBottles is! List) {
        throw Exception('Invalid bottle data returned by server.');
      }

      return rawBottles
          .map((json) => Bottle.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } on DioException catch (e) {
      final responseData = e.response?.data;

      if (responseData is Map) {
        final message = responseData['message']?.toString();

        if (message != null && message.isNotEmpty) {
          throw Exception(message);
        }
      }

      throw Exception('Unable to connect to the server.');
    }
  }

  Future<List<BottleType>> getBottleTypes() async {
    try {
      final response = await _apiService.dio.get(
        'api/bottles/get_bottle_types.php',
      );

      final responseData = Map<String, dynamic>.from(response.data);

      if (responseData['success'] != true) {
        throw Exception(
          responseData['message']?.toString() ?? 'Unable to load bottle types.',
        );
      }

      final dynamic data = responseData['data'];

      if (data is! Map) {
        throw Exception('Invalid response from server.');
      }

      final dynamic rawBottleTypes = data['bottleTypes'];

      if (rawBottleTypes is! List) {
        throw Exception('Invalid bottle type data returned by server.');
      }

      return rawBottleTypes
          .map((json) => BottleType.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } on DioException catch (e) {
      final responseData = e.response?.data;

      if (responseData is Map) {
        final message = responseData['message']?.toString();

        if (message != null && message.isNotEmpty) {
          throw Exception(message);
        }
      }

      throw Exception('Unable to connect to the server.');
    }
  }

  Future<BottleRegistration> registerBottle({
    required int accId,
    required String bottleNumber,
    required int bottleTypeId,
    String? bottleBrand,
    required String bottleCondition,
    required double bottleCost,
  }) async {
    try {
      final response = await _apiService.dio.post(
        'api/bottles/register_bottle.php',
        data: {
          'accId': accId,
          'bottleNumber': bottleNumber,
          'bottleTypeId': bottleTypeId,
          'bottleBrand': bottleBrand ?? '',
          'bottleCondition': bottleCondition,
          'bottleCost': bottleCost,
        },
      );

      final responseData = Map<String, dynamic>.from(response.data);

      if (responseData['success'] != true) {
        throw Exception(
          responseData['message']?.toString() ?? 'Unable to register bottle.',
        );
      }

      final dynamic data = responseData['data'];

      if (data is! Map || data['bottle'] is! Map) {
        throw Exception('Invalid bottle data returned by server.');
      }

      return BottleRegistration.fromJson(
        Map<String, dynamic>.from(data['bottle']),
      );
    } on DioException catch (e) {
      final responseData = e.response?.data;

      if (responseData is Map) {
        final message = responseData['message']?.toString();

        if (message != null && message.isNotEmpty) {
          throw Exception(message);
        }
      }

      throw Exception('Unable to connect to the server.');
    }
  }

  /// Registers a batch of bottles.
  ///
  /// Already-existing bottles are NOT treated as an error.
  /// They are returned through [BottleBatchRegistrationResult.existingBottles].
  Future<BottleBatchRegistrationResult> registerBottlesBatch({
    required int accId,
    required List<String> bottleNumbers,
    required int bottleTypeId,
    String? bottleBrand,
    required String bottleCondition,
    required double bottleCost,
  }) async {
    if (bottleNumbers.isEmpty) {
      throw const BottleBatchRegistrationException(
        message: 'No bottles were selected for registration.',
      );
    }

    try {
      final response = await _apiService.dio.post(
        'api/bottles/register_bottles_batch.php',
        data: {
          'accId': accId,
          'bottleTypeId': bottleTypeId,
          'bottleBrand': bottleBrand ?? '',
          'bottleCondition': bottleCondition,
          'bottleCost': bottleCost,
          'bottles': bottleNumbers,
        },
      );

      final responseData = Map<String, dynamic>.from(response.data);

      if (responseData['success'] != true) {
        throw _createBatchException(responseData);
      }

      final dynamic data = responseData['data'];

      if (data is! Map) {
        throw const BottleBatchRegistrationException(
          message: 'Invalid response from server.',
        );
      }

      // ----------------------------------------------------------
      // Newly registered bottles
      // ----------------------------------------------------------

      final dynamic rawBottles = data['bottles'];

      if (rawBottles is! List) {
        throw const BottleBatchRegistrationException(
          message: 'Invalid bottle data returned by server.',
        );
      }

      final registeredBottles = rawBottles
          .map(
            (json) =>
                BottleRegistration.fromJson(Map<String, dynamic>.from(json)),
          )
          .toList();

      // ----------------------------------------------------------
      // Bottles that already existed in the database
      // ----------------------------------------------------------

      final dynamic rawExistingBottles = data['existingBottles'];

      final List<String> existingBottles = [];

      if (rawExistingBottles is List) {
        for (final value in rawExistingBottles) {
          final bottleNumber = value.toString().trim();

          if (bottleNumber.isNotEmpty) {
            existingBottles.add(bottleNumber);
          }
        }
      }

      return BottleBatchRegistrationResult(
        registeredBottles: registeredBottles,
        existingBottles: existingBottles,
      );
    } on BottleBatchRegistrationException {
      rethrow;
    } on DioException catch (e) {
      final responseData = e.response?.data;

      if (responseData is Map) {
        throw _createBatchException(Map<String, dynamic>.from(responseData));
      }

      throw const BottleBatchRegistrationException(
        message: 'Unable to connect to the server.',
      );
    }
  }

  BottleBatchRegistrationException _createBatchException(
    Map<dynamic, dynamic> responseData,
  ) {
    final String message =
        responseData['message']?.toString() ?? 'Bottle registration failed.';

    final dynamic data = responseData['data'];

    if (data is! Map) {
      return BottleBatchRegistrationException(message: message);
    }

    final String? errorType = data['errorType']?.toString();

    String? bottleNumber;
    String? existingBottleType;
    String? requestedBottleType;

    final dynamic bottle = data['bottle'];

    if (bottle is Map) {
      bottleNumber = bottle['bottleNumber']?.toString();

      existingBottleType = bottle['bottleType']?.toString();
    }

    requestedBottleType = data['requestedBottleType']?.toString();

    // ----------------------------------------------------------
    // Already registered
    //
    // This is kept as fallback handling in case another API
    // endpoint still returns ALREADY_REGISTERED.
    //
    // The batch endpoint should now return existing bottles
    // as a successful response instead.
    // ----------------------------------------------------------

    if (errorType == 'ALREADY_REGISTERED' &&
        bottleNumber != null &&
        bottleNumber.isNotEmpty) {
      if (existingBottleType != null &&
          existingBottleType.isNotEmpty &&
          requestedBottleType != null &&
          requestedBottleType.isNotEmpty &&
          existingBottleType != requestedBottleType) {
        return BottleBatchRegistrationException(
          message:
              'Bottle "$bottleNumber" is already '
              'registered as $existingBottleType, '
              'but this batch is '
              '$requestedBottleType.',
          bottleNumber: bottleNumber,
          errorType: errorType,
        );
      }

      if (existingBottleType != null && existingBottleType.isNotEmpty) {
        return BottleBatchRegistrationException(
          message:
              'Bottle "$bottleNumber" is already '
              'registered as $existingBottleType.',
          bottleNumber: bottleNumber,
          errorType: errorType,
        );
      }

      return BottleBatchRegistrationException(
        message: 'Bottle "$bottleNumber" is already registered.',
        bottleNumber: bottleNumber,
        errorType: errorType,
      );
    }

    // ----------------------------------------------------------
    // Duplicate inside current batch
    // ----------------------------------------------------------

    if (errorType == 'DUPLICATE_IN_BATCH') {
      final dynamic duplicateBottle = data['duplicateBottle'];

      if (duplicateBottle is Map) {
        final duplicateNumber = duplicateBottle['bottleNumber']?.toString();

        if (duplicateNumber != null && duplicateNumber.isNotEmpty) {
          return BottleBatchRegistrationException(
            message:
                'Bottle "$duplicateNumber" was '
                'scanned more than once in this batch.\n\n'
                'Please remove the duplicate.',
            bottleNumber: duplicateNumber,
            errorType: errorType,
          );
        }
      }
    }

    // ----------------------------------------------------------
    // Generic structured bottle error
    // ----------------------------------------------------------

    if (bottleNumber != null && bottleNumber.isNotEmpty) {
      return BottleBatchRegistrationException(
        message: message,
        bottleNumber: bottleNumber,
        errorType: errorType,
      );
    }

    return BottleBatchRegistrationException(
      message: message,
      errorType: errorType,
    );
  }
}

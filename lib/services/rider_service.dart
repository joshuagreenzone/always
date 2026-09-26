import 'dart:io';

import 'package:dio/dio.dart';

import '../models/assigned_order.dart';
import '../models/order_details.dart';
import '../models/pickup_order.dart';
import 'api_service.dart';

class RiderService {
  final ApiService _apiService = ApiService();

  Future<List<AssignedOrder>> getAssignedOrders(int accId) async {
    try {
      final response = await _apiService.dio.get(
        'api/rider/get_assigned_orders.php',
        queryParameters: {'accId': accId},
      );

      if (response.data['success'] != true) {
        throw Exception(
          response.data['message']?.toString() ??
              'Unable to load assigned orders.',
        );
      }

      final List<dynamic> data = response.data['data'] ?? [];

      return data
          .map(
            (item) => AssignedOrder.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on DioException catch (e) {
      throw Exception(_getDioMessage(e));
    }
  }

  Future<OrderDetails> getOrderDetails({
    required int orderId,
    required int accId,
  }) async {
    try {
      final response = await _apiService.dio.get(
        'api/rider/get_order_details.php',
        queryParameters: {'orderId': orderId, 'accId': accId},
      );

      if (response.data['success'] != true) {
        throw Exception(
          response.data['message']?.toString() ??
              'Unable to load order details.',
        );
      }

      return OrderDetails.fromJson(
        Map<String, dynamic>.from(response.data['data']),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw Exception('Order not found or not assigned to this rider.');
      }

      throw Exception(_getDioMessage(e));
    }
  }

  // ============================================================
  // SCAN DELIVERY BOTTLE
  // ============================================================
  //
  // IMPORTANT:
  // This function is kept for compatibility with the existing
  // project, but the new DeliveryScanScreen should NOT call it.
  //
  // The new delivery scanning flow stores scanned bottles only
  // in temporary Flutter memory. The bottles are sent to the
  // server together through completeDelivery() only after the
  // rider confirms the delivery.
  //
  // Calling this function during scanning will immediately save
  // the bottle into the database, which defeats the new flow.
  //

  Future<Map<String, dynamic>> scanDeliveryBottle({
    required int accId,
    required int orderId,
    required int deliveryId,
    required String bottleNumber,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    try {
      final response = await _apiService.dio.post(
        'api/rider/scan_delivery_bottle.php',
        data: {
          'accId': accId,
          'orderId': orderId,
          'deliveryId': deliveryId,
          'bottleNumber': bottleNumber,
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
        },
      );

      if (response.data['success'] != true) {
        throw Exception(
          response.data['message']?.toString() ?? 'Bottle scan was rejected.',
        );
      }

      return Map<String, dynamic>.from(response.data['data'] ?? {});
    } on DioException catch (e) {
      final responseData = e.response?.data;

      if (responseData is Map && responseData['message'] != null) {
        throw Exception(responseData['message'].toString());
      }

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception('Unable to connect to the server.');
      }

      throw Exception('Bottle scan failed. Please try again.');
    }
  }

  // ============================================================
  // PAYMENT
  // ============================================================

  Future<Map<String, dynamic>> createPayment({
    required int accId,
    required int orderId,
    required double paymentAmount,
    required String paymentType,
    File? receiptImage,
    String? notes,
  }) async {
    try {
      final formData = FormData.fromMap({
        'accId': accId,
        'orderId': orderId,
        'paymentAmount': paymentAmount,
        'paymentType': paymentType,
        'notes': notes ?? '',
      });

      if (receiptImage != null) {
        formData.files.add(
          MapEntry(
            'receiptImage',
            await MultipartFile.fromFile(
              receiptImage.path,
              filename: receiptImage.path.split('/').last,
            ),
          ),
        );
      }

      final response = await _apiService.dio.post(
        'api/rider/create_payment.php',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (response.data is! Map || response.data['success'] != true) {
        throw Exception(
          response.data is Map
              ? response.data['message']?.toString() ?? 'Payment was rejected.'
              : 'Payment was rejected.',
        );
      }

      return Map<String, dynamic>.from(response.data['data'] ?? {});
    } on DioException catch (e) {
      if (e.response?.data is Map && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message'].toString());
      }

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception('Unable to connect to the server.');
      }

      throw Exception('Payment failed. Please try again.');
    }
  }

  // ============================================================
  // COMPLETE DELIVERY
  // ============================================================
  //
  // NEW DELIVERY FLOW:
  //
  // 1. Rider scans bottles.
  // 2. DeliveryScanScreen keeps the scans temporarily in memory.
  // 3. Nothing is inserted into the database during scanning.
  // 4. Rider proceeds to DeliveryConfirmationScreen.
  // 5. After the rider confirms, this function sends ALL scanned
  //    bottles to complete_delivery.php in one request.
  // 6. The PHP endpoint validates every bottle and, inside one
  //    database transaction:
  //
  //       - inserts order_delivery_transaction records
  //       - inserts bottle_scan_event records
  //       - marks the delivery as DELIVERED
  //       - marks the order as DELIVERED
  //
  // 7. If any bottle fails validation, the server rolls back
  //    the entire transaction.
  //
  // The bottles parameter should contain objects like:
  //
  // {
  //   "bottleNumber": "BTL001",
  //   "latitude": 13.12345678,
  //   "longitude": 121.12345678,
  //   "accuracy": 8.5
  // }
  //
  // This means GPS information collected during scanning is
  // preserved until the final delivery confirmation.
  //

  Future<Map<String, dynamic>> completeDelivery({
    required int accId,
    required int orderId,
    required int deliveryId,
    required List<Map<String, dynamic>> bottles,
  }) async {
    try {
      final response = await _apiService.dio.post(
        'api/rider/complete_delivery.php',
        data: {
          'accId': accId,
          'orderId': orderId,
          'deliveryId': deliveryId,
          'bottles': bottles,
        },
      );

      if (response.data is! Map || response.data['success'] != true) {
        throw Exception(
          response.data is Map
              ? response.data['message']?.toString() ??
                    'Unable to complete delivery.'
              : 'Unable to complete delivery.',
        );
      }

      return Map<String, dynamic>.from(response.data['data'] ?? {});
    } on DioException catch (e) {
      if (e.response?.data is Map && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message'].toString());
      }

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception('Unable to connect to the server.');
      }

      throw Exception('Unable to complete delivery. Please try again.');
    }
  }

  String _getDioMessage(DioException e) {
    if (e.response?.statusCode == 400) {
      return 'Invalid rider account.';
    }

    if (e.response?.statusCode == 500) {
      return 'Server error. Please try again.';
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Unable to connect to the server.';
    }

    return 'Unable to load assigned orders.';
  }

  // ============================================================
  // PICKUP ORDERS
  // ============================================================

  Future<List<PickupOrder>> getPickupOrders(int accId) async {
    try {
      final response = await _apiService.dio.get(
        'api/rider/get_pickup_orders.php',
        queryParameters: {'accId': accId},
      );

      if (response.data['success'] != true) {
        throw Exception(
          response.data['message']?.toString() ??
              'Unable to load pickup orders.',
        );
      }

      final List<dynamic> data = response.data['data'] ?? [];

      return data
          .map((item) => PickupOrder.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on DioException catch (e) {
      if (e.response?.data is Map && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message'].toString());
      }

      throw Exception('Unable to load pickup orders.');
    }
  }

  // ============================================================
  // PICKUP
  // ============================================================
  //
  // Pickup bottles are intentionally NOT sent to the server
  // individually anymore.
  //
  // The scanner stores them temporarily in PickupScanScreen.
  // They are committed together when completePickup() is called.
  //

  Future<Map<String, dynamic>> completePickup({
    required int accId,
    required int orderId,
    required int deliveryId,
    required List<Map<String, dynamic>> bottles,
  }) async {
    try {
      final response = await _apiService.dio.post(
        'api/rider/complete_pickup.php',
        data: {
          'accId': accId,
          'orderId': orderId,
          'deliveryId': deliveryId,
          'bottles': bottles,
        },
      );

      if (response.data['success'] != true) {
        throw Exception(
          response.data['message']?.toString() ?? 'Unable to complete pickup.',
        );
      }

      return Map<String, dynamic>.from(response.data['data'] ?? {});
    } on DioException catch (e) {
      if (e.response?.data is Map && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message'].toString());
      }

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception('Unable to connect to the server.');
      }

      throw Exception('Unable to complete pickup. Please try again.');
    }
  }
}

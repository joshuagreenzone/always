import 'dart:io';

import 'package:dio/dio.dart';

import '../models/assigned_order.dart';
import '../models/order_details.dart';
import '../models/pickup_order.dart';
import 'api_service.dart';

class RiderService {
  final ApiService _apiService = ApiService();

  // ============================================================
  // ASSIGNED ORDERS
  // ============================================================

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

  // ============================================================
  // ORDER DETAILS
  // ============================================================

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
  // Kept for compatibility with existing project code.
  //
  // The temporary delivery scanning flow should not call this
  // method because it saves a scan immediately on the server.
  // Instead, collect bottle numbers and GPS data in memory and
  // submit them together through completeDelivery().
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

      if (_isConnectionError(e)) {
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

      if (_isConnectionError(e)) {
        throw Exception('Unable to connect to the server.');
      }

      throw Exception('Payment failed. Please try again.');
    }
  }

  // ============================================================
  // COMPLETE DELIVERY
  // ============================================================
  //
  // The rider scans bottles and temporarily stores the results
  // in Flutter memory.
  //
  // On confirmation, this method submits all scanned bottles in
  // one request. The PHP endpoint must validate the bottles and
  // commit the delivery records inside a database transaction.
  //
  // For partial deliveries:
  // - incompleteReason is required.
  // - Only scanned and validated bottles are recorded as delivered.
  // - The delivery is marked INCOMPLETE.
  // - Undelivered bottles are not automatically rescheduled.
  //
  // Example bottle:
  // {
  //   "bottleNumber": "BTL001",
  //   "latitude": 13.12345678,
  //   "longitude": 121.12345678,
  //   "accuracy": 8.5
  // }
  //

  Future<Map<String, dynamic>> completeDelivery({
    required int accId,
    required int orderId,
    required int deliveryId,
    required List<Map<String, dynamic>> bottles,
    String? incompleteReason,
  }) async {
    final String reason = incompleteReason?.trim() ?? '';

    if (bottles.isEmpty) {
      throw Exception('Scan at least one bottle before confirming delivery.');
    }

    if (reason.isEmpty && incompleteReason != null) {
      throw Exception('Please provide a reason for the incomplete delivery.');
    }

    try {
      final response = await _apiService.dio.post(
        'api/rider/complete_delivery.php',
        data: {
          'accId': accId,
          'orderId': orderId,
          'deliveryId': deliveryId,
          'bottles': bottles,
          'incompleteReason': reason.isEmpty ? null : reason,
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

      if (_isConnectionError(e)) {
        throw Exception('Unable to connect to the server.');
      }

      throw Exception('Unable to complete delivery. Please try again.');
    }
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

      if (_isConnectionError(e)) {
        throw Exception('Unable to connect to the server.');
      }

      throw Exception('Unable to load pickup orders.');
    }
  }

  // ============================================================
  // COMPLETE PICKUP
  // ============================================================
  //
  // Pickup bottles are collected temporarily in the scanner
  // screen and submitted together when the rider confirms.
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

      if (response.data is! Map || response.data['success'] != true) {
        throw Exception(
          response.data is Map
              ? response.data['message']?.toString() ??
                    'Unable to complete pickup.'
              : 'Unable to complete pickup.',
        );
      }

      return Map<String, dynamic>.from(response.data['data'] ?? {});
    } on DioException catch (e) {
      if (e.response?.data is Map && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message'].toString());
      }

      if (_isConnectionError(e)) {
        throw Exception('Unable to connect to the server.');
      }

      throw Exception('Unable to complete pickup. Please try again.');
    }
  }

  // ============================================================
  // ERROR HELPERS
  // ============================================================

  bool _isConnectionError(DioException e) {
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError;
  }

  String _getDioMessage(DioException e) {
    if (e.response?.statusCode == 400) {
      return 'Invalid rider account.';
    }

    if (e.response?.statusCode == 500) {
      return 'Server error. Please try again.';
    }

    if (_isConnectionError(e)) {
      return 'Unable to connect to the server.';
    }

    return 'Unable to load assigned orders.';
  }
}

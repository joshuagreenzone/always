import 'dart:io';

import 'package:dio/dio.dart';

import '../models/assigned_order.dart';
import '../models/order_details.dart';
import 'api_service.dart';

import '../models/pickup_order.dart';

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

  Future<Map<String, dynamic>> scanDeliveryBottle({
    required int accId,
    required int orderId,
    required int deliveryId,
    required String bottleNumber,
  }) async {
    try {
      final response = await _apiService.dio.post(
        'api/rider/scan_delivery_bottle.php',
        data: {
          'accId': accId,
          'orderId': orderId,
          'deliveryId': deliveryId,
          'bottleNumber': bottleNumber,
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
    String notes = '',
  }) async {
    try {
      final formData = FormData.fromMap({
        'accId': accId,
        'orderId': orderId,
        'paymentAmount': paymentAmount,
        'paymentType': paymentType,
        'notes': notes,

        if (receiptImage != null)
          'receiptImage': await MultipartFile.fromFile(
            receiptImage.path,
            filename: receiptImage.path.split(Platform.pathSeparator).last,
          ),
      });

      final response = await _apiService.dio.post(
        'api/rider/create_payment.php',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (response.data['success'] != true) {
        throw Exception(
          response.data['message']?.toString() ?? 'Unable to record payment.',
        );
      }

      return Map<String, dynamic>.from(response.data['data']);
    } on DioException catch (e) {
      if (e.response?.data is Map && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message'].toString());
      }

      throw Exception('Unable to record payment. Please try again.');
    }
  }

  // ============================================================
  // COMPLETE DELIVERY
  // ============================================================

  Future<void> completeDelivery({
    required int accId,
    required int orderId,
    required int deliveryId,
  }) async {
    try {
      final response = await _apiService.dio.post(
        'api/rider/complete_delivery.php',
        data: {'accId': accId, 'orderId': orderId, 'deliveryId': deliveryId},
      );

      if (response.data['success'] != true) {
        throw Exception(
          response.data['message']?.toString() ??
              'Unable to complete delivery.',
        );
      }
    } on DioException catch (e) {
      if (e.response?.data is Map && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message'].toString());
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

  //pick up service

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

  //Scan pickup bottle

  Future<Map<String, dynamic>> scanPickupBottle({
    required int accId,
    required int orderId,
    required int deliveryId,
    required String bottleNumber,
  }) async {
    try {
      final response = await _apiService.dio.post(
        'api/rider/scan_pickup_bottle.php',
        data: {
          'accId': accId,
          'orderId': orderId,
          'deliveryId': deliveryId,
          'bottleNumber': bottleNumber,
        },
      );

      if (response.data['success'] != true) {
        throw Exception(
          response.data['message']?.toString() ?? 'Bottle pickup was rejected.',
        );
      }

      return Map<String, dynamic>.from(response.data['data'] ?? {});
    } on DioException catch (e) {
      if (e.response?.data is Map && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message'].toString());
      }

      throw Exception('Bottle pickup failed. Please try again.');
    }
  }

  //Complete pickup

  Future<void> completePickup({
    required int accId,
    required int orderId,
    required int deliveryId,
    required int pickUpId,
  }) async {
    try {
      final response = await _apiService.dio.post(
        'api/rider/complete_pickup.php',
        data: {
          'accId': accId,
          'orderId': orderId,
          'deliveryId': deliveryId,
          'pickUpId': pickUpId,
        },
      );

      if (response.data['success'] != true) {
        throw Exception(
          response.data['message']?.toString() ?? 'Unable to complete pickup.',
        );
      }
    } on DioException catch (e) {
      if (e.response?.data is Map && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message'].toString());
      }

      throw Exception('Unable to complete pickup. Please try again.');
    }
  }
}

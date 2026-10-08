import 'package:dio/dio.dart';

import '../models/rider_transaction.dart';
import 'api_service.dart';

class RiderTransactionService {
  final ApiService _apiService = ApiService();

  Future<List<RiderTransaction>> getTransactionHistory(int accId) async {
    try {
      final response = await _apiService.dio.get(
        'api/rider/get_transaction_history.php',
        queryParameters: {'accId': accId},
      );

      final data = response.data;

      if (data['success'] != true) {
        throw Exception(
          data['message']?.toString() ?? 'Failed to load transactions.',
        );
      }

      final List transactions = data['data'] ?? [];

      return transactions
          .map(
            (item) =>
                RiderTransaction.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on DioException catch (e) {
      throw Exception(e.message ?? 'Failed to load transaction history.');
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }
}

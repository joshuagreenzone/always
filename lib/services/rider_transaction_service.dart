import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/rider_transaction.dart';

class RiderTransactionService {
  static const String baseUrl =
      'http://192.168.1.76/fluttercodes/syawla/syawla_api/api/rider';

  Future<List<RiderTransaction>> getTransactionHistory(int accId) async {
    final url = Uri.parse('$baseUrl/get_transaction_history.php?accId=$accId');

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('Failed to load transaction history.');
    }

    final data = jsonDecode(response.body);

    if (data['success'] != true) {
      throw Exception(
        data['message']?.toString() ?? 'Failed to load transactions.',
      );
    }

    final List transactions = data['data'] ?? [];

    return transactions
        .map(
          (item) => RiderTransaction.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }
}

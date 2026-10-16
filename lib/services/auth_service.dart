import 'package:dio/dio.dart';

import '../models/account.dart';
import 'api_service.dart';

class AuthService {
  AuthService({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  final ApiService _apiService;

  Future<Account> login({
    required String username,
    required String password,
  }) async {
    ApiService.setAccessToken(null);
    try {
      final response = await _apiService.dio.post(
        'api/auth/login.php',
        data: {'username': username, 'password': password},
      );
      final body = response.data;
      if (body is! Map || body['success'] != true) {
        throw Exception(
          body is Map ? body['message'] ?? 'Login failed.' : 'Login failed.',
        );
      }

      final token = body['token'];
      final account = body['data'];
      if (token is! String || token.isEmpty || account is! Map) {
        throw Exception('Invalid login response from the server.');
      }

      final signedInAccount = Account.fromJson(Map<String, dynamic>.from(account));
      ApiService.setAccessToken(token);
      return signedInAccount;
    } on DioException catch (error) {
      final body = error.response?.data;
      final message = body is Map ? body['message'] : null;
      throw Exception(
        message is String ? message : 'Unable to connect to the server.',
      );
    }
  }
}

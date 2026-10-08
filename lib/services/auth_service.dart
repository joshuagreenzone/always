import '../models/account.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _apiService = ApiService();

  Future<Account> login({
    required String username,
    required String password,
  }) async {
    final response = await _apiService.dio.post(
      'api/auth/login.php',
      data: {'username': username, 'password': password},
    );

    if (response.data['success'] != true) {
      throw Exception(response.data['message'] ?? 'Login failed.');
    }

    return Account.fromJson(response.data['data']);
  }
}

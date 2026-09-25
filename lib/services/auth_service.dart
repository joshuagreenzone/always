import '../models/account.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _apiService = ApiService();

  Future<Account> login({
    required String username,
    required String password,
  }) async {
    final response = await _apiService.dio.post(
      // Changed 10.0.2.2 to your PC's IP address (192.168.1.76)
      'http://192.168.1.76/fluttercodes/syawla/syawla_api/api/auth/login.php',
      data: {'username': username, 'password': password},
    );

    if (response.data['success'] != true) {
      throw Exception(response.data['message'] ?? 'Login failed.');
    }

    return Account.fromJson(response.data['data']);
  }
}

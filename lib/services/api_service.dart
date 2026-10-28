import 'package:dio/dio.dart';

class ApiService {
  static const baseUrl = String.fromEnvironment(
    'SYAWLA_API_BASE_URL',
    // Local XAMPP / CodeIgniter API (same Wi-Fi as the phone).
    defaultValue: 'http://192.168.1.76:8081/mobile/',
    // Hosted API: comment the local default above and uncomment this line.
    //defaultValue: 'https://always-system.greenzoneph.com/mobile/',
  );

  static String? _accessToken;

  ApiService() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_accessToken != null) {
            options.headers['Authorization'] = 'Bearer $_accessToken';
          }
          handler.next(options);
        },
      ),
    );
  }

  static void setAccessToken(String? token) {
    _accessToken = token;
  }

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  Dio get dio => _dio;
}

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syawla/services/api_service.dart';
import 'package:syawla/services/auth_service.dart';

void main() {
  tearDown(() => ApiService.setAccessToken(null));

  test('login token is sent with later mobile API requests', () async {
    final loginApi = ApiService();
    loginApi.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.path, 'api/auth/login.php');
          expect(options.data, {'username': 'rider01', 'password': 'secret'});
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'success': true,
                'token': 'test-token',
                'data': {
                  'AccID': 3,
                  'AccName': 'Rider',
                  'AccEmail': 'rider@example.com',
                  'AccUsername': 'rider01',
                  'AccType': 'RIDER',
                },
              },
            ),
          );
        },
      ),
    );

    final account = await AuthService(apiService: loginApi)
        .login(username: 'rider01', password: 'secret');
    expect(account.accId, 3);

    final api = ApiService();
    api.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.headers['Authorization'], 'Bearer test-token');
          handler.resolve(
            Response(requestOptions: options, data: {'success': true}),
          );
        },
      ),
    );
    await api.dio.get('api/bottles/get_bottle_types.php');
  });

  test('login displays the API error message', () async {
    final api = ApiService();
    api.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 401,
                data: {
                  'success': false,
                  'message': 'Invalid username or password.',
                },
              ),
            ),
          );
        },
      ),
    );

    expect(
      () =>
          AuthService(apiService: api)
              .login(username: 'rider01', password: 'wrong'),
      throwsA(
        predicate(
          (error) => error.toString().contains('Invalid username or password.'),
        ),
      ),
    );
  });
}

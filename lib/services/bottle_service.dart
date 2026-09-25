import '../models/bottle.dart';
import 'api_service.dart';

class BottleService {
  final ApiService _apiService = ApiService();

  Future<List<Bottle>> getBottles() async {
    final response = await _apiService.dio.get('api/bottles/get_bottles.php');

    if (response.data['success'] != true) {
      throw Exception(response.data['message'] ?? 'Failed to load bottles.');
    }

    final List<dynamic> data = response.data['data'];

    return data
        .map((json) => Bottle.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }
}

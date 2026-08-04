import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  ApiClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: const String.fromEnvironment(
                'API_BASE_URL',
                defaultValue: 'http://127.0.0.1:8000/api/v1',
              ),
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ),
          );

  final Dio _dio;

  Dio get dio => _dio;

  Future<bool> isHealthy() async {
    final response = await _dio.get<Map<String, dynamic>>('/health');
    return response.data?['status'] == 'ok';
  }
}

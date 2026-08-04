import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  ApiClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: kIsWeb
                  ? null
                  : {'cookie': 'foliox_account=${_accountId}'},
            ),
          );

  final Dio _dio;

  static String get _baseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return configured;
    return kIsWeb
        ? '${Uri.base.origin}/api/v1'
        : 'https://foliox.foliox.workers.dev/api/v1';
  }

  static String get _accountId {
    final box = Hive.box<String>('foliox_settings');
    final saved = box.get('account_id');
    if (saved != null && saved.isNotEmpty) return saved;
    final generated =
        'android-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random.secure().nextInt(1 << 32).toRadixString(36)}';
    box.put('account_id', generated);
    return generated;
  }

  Dio get dio => _dio;

  Future<bool> isHealthy() async {
    final response = await _dio.get<Map<String, dynamic>>('/health');
    return response.data?['status'] == 'ok';
  }
}

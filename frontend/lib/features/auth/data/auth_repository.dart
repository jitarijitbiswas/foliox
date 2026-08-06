import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/network/api_client.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider).dio),
);

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.picture,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'].toString(),
    email: json['email'].toString(),
    name: json['name'].toString(),
    picture: json['picture']?.toString() ?? '',
  );

  final String id;
  final String email;
  final String name;
  final String picture;
}

class AuthRepository {
  const AuthRepository(this._dio);
  final Dio _dio;

  Future<AuthUser?> restoreSession() async {
    if (!Hive.isBoxOpen('foliox_settings')) return null;
    if (_box.get('session_token') == null) return null;
    try {
      final response = await _dio.get<Map<String, dynamic>>('/auth/me');
      return AuthUser.fromJson(response.data!['user'] as Map<String, dynamic>);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) await clearSession();
      return null;
    }
  }

  Future<AuthUser> exchangeGoogleToken(String idToken) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/google',
      data: {'id_token': idToken},
    );
    await _box.put('session_token', response.data!['token'].toString());
    return AuthUser.fromJson(response.data!['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    try {
      await _dio.post<void>('/auth/logout');
    } finally {
      await clearSession();
    }
  }

  Future<void> clearSession() => _box.delete('session_token');
  Box<String> get _box => Hive.box<String>('foliox_settings');
}

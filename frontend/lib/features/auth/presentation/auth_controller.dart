import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/auth_repository.dart';

const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(ref.watch(authRepositoryProvider));
  },
);

class AuthState {
  const AuthState({
    this.user,
    this.isLoading = true,
    this.isSigningIn = false,
    this.error,
  });
  final AuthUser? user;
  final bool isLoading;
  final bool isSigningIn;
  final String? error;

  AuthState copyWith({
    AuthUser? user,
    bool? isLoading,
    bool? isSigningIn,
    String? error,
    bool clearUser = false,
  }) => AuthState(
    user: clearUser ? null : user ?? this.user,
    isLoading: isLoading ?? this.isLoading,
    isSigningIn: isSigningIn ?? this.isSigningIn,
    error: error,
  );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthState()) {
    unawaited(_initialize());
  }
  final AuthRepository _repository;
  final GoogleSignIn _google = GoogleSignIn.instance;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _events;

  Future<void> _initialize() async {
    final restored = await _repository.restoreSession();
    if (restored != null) {
      state = AuthState(user: restored, isLoading: false);
      return;
    }
    if (googleClientId.isEmpty) {
      state = const AuthState(
        isLoading: false,
        error: 'Google OAuth client ID is not configured.',
      );
      return;
    }
    try {
      await _google.initialize(
        clientId: kIsWeb ? googleClientId : null,
        serverClientId: googleClientId,
      );
      _events = _google.authenticationEvents.listen(
        _handleGoogleEvent,
        onError: _handleError,
      );
      state = const AuthState(isLoading: false);
      _google.attemptLightweightAuthentication();
    } catch (error) {
      _handleError(error);
    }
  }

  Future<void> signIn() async {
    state = state.copyWith(isSigningIn: true, error: null);
    try {
      await _google.authenticate();
    } catch (error) {
      _handleError(error);
    }
  }

  Future<void> _handleGoogleEvent(GoogleSignInAuthenticationEvent event) async {
    if (event is GoogleSignInAuthenticationEventSignOut) return;
    final user = (event as GoogleSignInAuthenticationEventSignIn).user;
    final idToken = user.authentication.idToken;
    if (idToken == null) {
      _handleError('Google did not return an ID token.');
      return;
    }
    try {
      final account = await _repository.exchangeGoogleToken(idToken);
      state = AuthState(user: account, isLoading: false);
    } catch (error) {
      _handleError(error);
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    await _google.signOut();
    state = const AuthState(isLoading: false);
  }

  void _handleError(Object error) {
    state = AuthState(isLoading: false, error: error.toString());
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}

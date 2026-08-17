import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum AuthMode { login, signUp }

/// Hashes a local-device profile password without retaining the password itself.
/// This is only for the offline paper-trading profile; it is not a substitute
/// for server-side authentication.
String hashLocalPassword(String password, String salt) =>
    sha256.convert(utf8.encode('$salt:$password')).toString();

String generatePasswordSalt() {
  final random = Random.secure();
  return List<String>.generate(
    32,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Normalizes the identifier used as the local account key. Email addresses
/// are case-insensitive; phone formatting characters do not affect lookup.
String normalizeLoginIdentifier(String value) {
  final trimmed = value.trim();
  if (trimmed.contains('@')) return trimmed.toLowerCase();
  return trimmed.replaceAll(RegExp(r'[\s().-]'), '');
}

String? validateLoginIdentifier(String? value) {
  final identifier = value?.trim() ?? '';
  if (identifier.isEmpty) return 'Email or phone number is required';
  final isEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(identifier);
  final normalizedPhone = normalizeLoginIdentifier(identifier);
  final isPhone = RegExp(r'^\+?[0-9]{7,15}$').hasMatch(normalizedPhone);
  return isEmail || isPhone ? null : 'Enter a valid email or phone number';
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.initialMode});
  final AuthMode initialMode;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late AuthMode _mode = widget.initialMode;
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  var _obscurePassword = true;
  var _isSubmitting = false;
  String? _accountError;

  void _clearAccountError() {
    if (_accountError != null) setState(() => _accountError = null);
  }

  @override
  void dispose() {
    _name.dispose();
    _identifier.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final identifier = normalizeLoginIdentifier(_identifier.text);
    final settings = Hive.box<String>('foliox_settings');
    final accounts = _accounts(settings);
    if (_mode == AuthMode.signUp && accounts.containsKey(identifier)) {
      setState(
        () => _accountError =
            'An account already exists for this email or phone number. Please log in.',
      );
      return;
    }
    if (_mode == AuthMode.login && !accounts.containsKey(identifier)) {
      setState(
        () =>
            _accountError = 'No local account found. Create an account first.',
      );
      return;
    }
    if (_mode == AuthMode.login) {
      final account = Map<String, dynamic>.from(accounts[identifier] as Map);
      final salt = account['password_salt']?.toString();
      final savedHash = account['password_hash']?.toString();
      if (salt == null || savedHash == null ||
          hashLocalPassword(_password.text, salt) != savedHash) {
        setState(
          () => _accountError =
              'The email or password is incorrect. Please try again.',
        );
        return;
      }
    }
    setState(() => _isSubmitting = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (_mode == AuthMode.signUp) {
      final passwordSalt = generatePasswordSalt();
      accounts[identifier] = {
        'name': _name.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
        'password_salt': passwordSalt,
        'password_hash': hashLocalPassword(_password.text, passwordSalt),
      };
      await settings.put('local_accounts', jsonEncode(accounts));
    }
    final account = Map<String, dynamic>.from(accounts[identifier] as Map);
    await settings.put('active_account_id', identifier);
    await settings.put(
      'local_account_name',
      account['name']?.toString() ?? 'Paper Trader',
    );
    if (mounted) context.go('/home');
  }

  Map<String, dynamic> _accounts(Box<String> settings) {
    final saved = settings.get('local_accounts');
    if (saved == null || saved.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(saved);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final signUp = _mode == AuthMode.signUp;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Close',
                        onPressed: () => context.go('/onboarding'),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      signUp ? 'Create your account' : 'Welcome back!',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      signUp
                          ? 'Start practising with virtual money.'
                          : 'Log in to continue your paper trading journey.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _ModeTabs(
                      mode: _mode,
                      onChanged: (value) => setState(() {
                        _mode = value;
                        _accountError = null;
                      }),
                    ),
                    const SizedBox(height: 22),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      child: Column(
                        children: [
                          if (signUp) ...[
                            TextFormField(
                              controller: _name,
                              onChanged: (_) => _clearAccountError(),
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Full name',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (value) =>
                                  signUp &&
                                      (value == null || value.trim().isEmpty)
                                  ? 'Name is required'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _identifier,
                            onChanged: (_) => _clearAccountError(),
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email or phone number',
                              hintText: 'name@example.com or +91 98765 43210',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            autofillHints: const [
                              AutofillHints.email,
                              AutofillHints.telephoneNumber,
                            ],
                            validator: validateLoginIdentifier,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            onChanged: (_) => _clearAccountError(),
                            obscureText: _obscurePassword,
                            textInputAction: signUp
                                ? TextInputAction.next
                                : TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Password is required'
                                : value.length < 6
                                ? 'Use at least 6 characters'
                                : null,
                          ),
                          if (signUp) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _confirmPassword,
                              onChanged: (_) => _clearAccountError(),
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: 'Confirm password',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              validator: (value) => value != _password.text
                                  ? 'Passwords do not match'
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!signUp)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => context.push('/forgot-password'),
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (_accountError != null) ...[
                      Text(
                        _accountError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(signUp ? 'Create Account' : 'Log In'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'By continuing, you agree to our Terms & Conditions and Privacy Policy.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({required this.mode, required this.onChanged});
  final AuthMode mode;
  final ValueChanged<AuthMode> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: AuthMode.values.map((value) {
      final selected = value == mode;
      return Expanded(
        child: TextButton(
          onPressed: () => onChanged(value),
          style: TextButton.styleFrom(
            foregroundColor: selected
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurfaceVariant,
            shape: const RoundedRectangleBorder(),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(value == AuthMode.login ? 'Log In' : 'Sign Up'),
          ),
        ),
      );
    }).toList(),
  );
}

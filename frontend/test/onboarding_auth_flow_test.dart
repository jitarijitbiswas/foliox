import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nse_paper_trading/features/onboarding/presentation/auth_screen.dart';
import 'package:nse_paper_trading/features/onboarding/presentation/onboarding_screen.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('foliox_auth_test_');
    Hive.init(hiveDirectory.path);
  });

  setUp(() async {
    if (Hive.isBoxOpen('foliox_settings')) {
      await Hive.box<String>('foliox_settings').clear();
    } else {
      await Hive.openBox<String>('foliox_settings');
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('password hashing is deterministic per salt and does not expose password', () {
    final hash = hashLocalPassword('correct horse battery staple', 'test-salt');

    expect(hash, hasLength(64));
    expect(hash, isNot(contains('correct horse')));
    expect(
      hashLocalPassword('correct horse battery staple', 'test-salt'),
      hash,
    );
    expect(hashLocalPassword('wrong password', 'test-salt'), isNot(hash));
  });

  test('email and phone identifiers validate and normalize consistently', () {
    expect(validateLoginIdentifier('test@example.com'), isNull);
    expect(validateLoginIdentifier('+91 98765 43210'), isNull);
    expect(validateLoginIdentifier('98765-43210'), isNull);
    expect(validateLoginIdentifier('invalid'), 'Enter a valid email or phone number');
    expect(normalizeLoginIdentifier(' TEST@EXAMPLE.COM '), 'test@example.com');
    expect(normalizeLoginIdentifier('+91 (98765) 43210'), '+919876543210');
  });

  testWidgets('Page 1 renders both routes and the primary CTA opens sign-up', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_app(router));

    expect(find.text('Practice. Learn. Trade.'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
  });

  testWidgets('Page 2 shows form validation for empty and mismatched sign-up values', (
    tester,
  ) async {
    final router = _router(initialLocation: '/auth?mode=signup');
    await tester.pumpWidget(_app(router));

    await tester.tap(find.text('Create Account'));
    await tester.pump();
    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('Email or phone number is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Test Trader');
    await tester.enterText(fields.at(1), 'test@example.com');
    await tester.enterText(fields.at(2), 'pass123');
    await tester.enterText(fields.at(3), 'pass456');
    await tester.tap(find.text('Create Account'));
    await tester.pump();

    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('valid sign-up stores only a salted password hash and navigates home', (
    tester,
  ) async {
    final router = _router(initialLocation: '/auth?mode=signup');
    await tester.pumpWidget(_app(router));
    final fields = find.byType(TextFormField);

    await tester.enterText(fields.at(0), 'Test Trader');
    await tester.enterText(fields.at(1), 'test@example.com');
    await tester.enterText(fields.at(2), 'pass123');
    await tester.enterText(fields.at(3), 'pass123');
    await tester.tap(find.text('Create Account'));
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    final accounts = jsonDecode(
      Hive.box<String>('foliox_settings').get('local_accounts')!,
    ) as Map<String, dynamic>;
    final account = accounts['test@example.com'] as Map<String, dynamic>;
    expect(account['password_hash'], isNot('pass123'));
    expect(account['password_salt'], hasLength(64));
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('incorrect local password remains on Page 2 and shows a safe error', (
    tester,
  ) async {
    const salt = '0123456789abcdef';
    await Hive.box<String>('foliox_settings').put(
      'local_accounts',
      jsonEncode({
        'test@example.com': {
          'name': 'Test Trader',
          'password_salt': salt,
          'password_hash': hashLocalPassword('pass123', salt),
        },
      }),
    );
    final router = _router(initialLocation: '/auth?mode=login');
    await tester.pumpWidget(_app(router));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'test@example.com');
    await tester.enterText(fields.at(1), 'wrong1');
    await tester.tap(find.text('Log In').last);
    await tester.pump();

    expect(find.text('The email or password is incorrect. Please try again.'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('correct local password activates the matching account', (tester) async {
    const salt = 'fedcba9876543210';
    await Hive.box<String>('foliox_settings').put(
      'local_accounts',
      jsonEncode({
        'test@example.com': {
          'name': 'Test Trader',
          'password_salt': salt,
          'password_hash': hashLocalPassword('pass123', salt),
        },
      }),
    );
    final router = _router(initialLocation: '/auth?mode=login');
    await tester.pumpWidget(_app(router));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'test@example.com');
    await tester.enterText(fields.at(1), 'pass123');
    await tester.tap(find.text('Log In').last);
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    expect(Hive.box<String>('foliox_settings').get('active_account_id'), 'test@example.com');
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('Android back from Page 2 returns to Page 1', (tester) async {
    final router = _router();
    await tester.pumpWidget(_app(router));
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Practice. Learn. Trade.'), findsOneWidget);
  });
}

GoRouter _router({String initialLocation = '/onboarding'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
    GoRoute(
      path: '/auth',
      builder: (_, state) => AuthScreen(
        initialMode: state.uri.queryParameters['mode'] == 'signup'
            ? AuthMode.signUp
            : AuthMode.login,
      ),
    ),
    GoRoute(
      path: '/home',
      builder: (_, _) => const Scaffold(body: Center(child: Text('Home'))),
    ),
  ],
);

Widget _app(GoRouter router) => MaterialApp.router(routerConfig: router);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/analytics/presentation/portfolio_analytics_screens.dart';
import '../features/practice/presentation/practice_screens.dart';
import '../features/onboarding/presentation/auth_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/markets/presentation/market_screens.dart';
import '../features/trading/presentation/trading_workflow_screens.dart';
import '../features/trading/domain/trading_models.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation:
        Hive.box<String>('foliox_settings').containsKey('active_account_id')
        ? '/home'
        : '/onboarding',
    redirect: (context, state) {
      final hasLocalAccount = Hive.box<String>(
        'foliox_settings',
      ).containsKey('active_account_id');
      final publicRoute =
          state.matchedLocation == '/onboarding' ||
          state.matchedLocation == '/auth' ||
          state.matchedLocation == '/forgot-password';

      // A hash/deep link must never bypass local authentication. Market data
      // remains public, but the paper account and its portfolio are private
      // to the profile saved on this browser/device.
      if (!hasLocalAccount && !publicRoute) return '/auth';
      if (hasLocalAccount && publicRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/auth',
        name: 'auth',
        builder: (context, state) => AuthScreen(
          initialMode: state.uri.queryParameters['mode'] == 'signup'
              ? AuthMode.signUp
              : AuthMode.login,
        ),
      ),
      GoRoute(
        path: '/home',
        name: 'dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const _ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/watchlist',
        builder: (context, state) => const WatchlistScreen(),
      ),
      GoRoute(
        path: '/markets',
        builder: (context, state) => const MarketsScreen(),
      ),
      GoRoute(path: '/trade', builder: (context, state) => const TradeScreen()),
      GoRoute(
        path: '/trade/:symbol',
        builder: (context, state) => OrderEntryScreen(
          symbol: state.pathParameters['symbol']!,
          side: state.uri.queryParameters['side'] == 'SELL'
              ? OrderSide.sell
              : OrderSide.buy,
        ),
      ),
      GoRoute(
        path: '/positions',
        builder: (context, state) => const PositionsScreen(),
      ),
      GoRoute(
        path: '/orders',
        builder: (context, state) => const OrdersScreen(),
      ),
      GoRoute(
        path: '/stock/:symbol',
        builder: (context, state) =>
            StockDetailScreen(symbol: state.pathParameters['symbol']!),
      ),
      GoRoute(
        path: '/portfolio',
        builder: (context, state) => const PortfolioScreen(),
      ),
      GoRoute(
        path: '/analytics',
        builder: (context, state) => const AnalyticsScreen(),
      ),
      GoRoute(
        path: '/performance',
        builder: (context, state) => const AnalyticsScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/journal',
        builder: (context, state) => const JournalScreen(),
      ),
      GoRoute(path: '/risk', builder: (context, state) => const RiskScreen()),
      GoRoute(
        path: '/strategies',
        builder: (context, state) => const StrategiesScreen(),
      ),
    ],
  );
});

class _ForgotPasswordScreen extends StatelessWidget {
  const _ForgotPasswordScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Password recovery will be available in a future update.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

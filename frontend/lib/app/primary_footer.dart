import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shared navigation for every top-level workspace screen.
class PrimaryFooter extends StatelessWidget {
  const PrimaryFooter({
    super.key,
    required this.selectedIndex,
    this.isHomeRoute = false,
  });

  final int selectedIndex;
  final bool isHomeRoute;

  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: selectedIndex,
    onDestinationSelected: (index) {
      const routes = ['/home', '/portfolio', '/trade', '/positions', '/profile'];
      if (index != selectedIndex || (index == 0 && !isHomeRoute)) {
        context.go(routes[index]);
      }
    },
    destinations: const [
      NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'Portfolio'),
      NavigationDestination(icon: Icon(Icons.candlestick_chart_outlined), selectedIcon: Icon(Icons.candlestick_chart), label: 'Trade'),
      NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Positions'),
      NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
    ],
  );
}

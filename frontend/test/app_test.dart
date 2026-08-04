import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nse_paper_trading/app/app.dart';
import 'package:nse_paper_trading/features/trading/data/trading_repository.dart';
import 'package:nse_paper_trading/features/trading/presentation/trading_controller.dart';

void main() {
  testWidgets('renders the dashboard shell', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tradingControllerProvider.overrideWith(
            (ref) =>
                TradingController(TradingRepository(Dio()), autoStart: false),
          ),
        ],
        child: const PaperTradingApp(),
      ),
    );

    expect(find.text('PaperTrade Demo'), findsOneWidget);
    expect(find.text('SIMULATED DATA'), findsOneWidget);
  });
}

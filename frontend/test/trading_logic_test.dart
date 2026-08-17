import 'package:flutter_test/flutter_test.dart';
import 'package:nse_paper_trading/features/analytics/domain/trading_analytics.dart';
import 'package:nse_paper_trading/features/practice/domain/practice_engines.dart';
import 'package:nse_paper_trading/features/practice/domain/practice_models.dart';
import 'package:nse_paper_trading/features/trading/domain/trading_models.dart';

TradeOrder order({
  required String id,
  required double pnl,
  String symbol = 'RELIANCE',
}) => TradeOrder(
  id: id,
  symbol: symbol,
  side: 'BUY',
  quantity: 10,
  entryPrice: 100,
  exitPrice: 100 + pnl / 10,
  status: 'CLOSED',
  pnl: pnl,
  createdAt: DateTime(2026, 8, 16, 9),
  closedAt: DateTime(2026, 8, 16, 10),
);

void main() {
  test('analytics uses completed trade outcomes consistently', () {
    final report = TradingAnalyticsEngine.calculate([
      order(id: 'a', pnl: 100),
      order(id: 'b', pnl: -50),
      order(id: 'c', pnl: 200),
    ]);
    expect(report.total, 3);
    expect(report.winners, 2);
    expect(report.losers, 1);
    expect(report.winRate, closeTo(66.67, .01));
    expect(report.profitFactor, 6);
    expect(report.expectancy, closeTo(83.33, .01));
  });

  test('strategy performance only includes journal-linked trades', () {
    final setup = TradingSetup(id: 'breakout', name: 'Breakout', createdAt: DateTime.now());
    final entries = [
      TradeJournalEntry(id: 'j1', symbol: 'RELIANCE', tradeId: 'a', setupId: 'breakout', setupName: 'Breakout', createdAt: DateTime.now(), updatedAt: DateTime.now()),
    ];
    final result = StrategyAnalyticsEngine.calculate([setup], entries, [order(id: 'a', pnl: 100), order(id: 'b', pnl: -80)]).single;
    expect(result.count, 1);
    expect(result.netPnl, 100);
    expect(result.winners, 1);
  });

  test('risk scenario impact is derived from open positions', () {
    const portfolio = Portfolio(cashBalance: 35000, equity: 100000, realizedPnl: 0, unrealizedPnl: 0, totalPnl: 0, positions: [
      Position(symbol: 'RELIANCE', quantity: 10, averagePrice: 2800, ltp: 3000, realizedPnl: 0, unrealizedPnl: 0, netPnl: 0),
      Position(symbol: 'TCS', quantity: 10, averagePrice: 3000, ltp: 3500, realizedPnl: 0, unrealizedPnl: 0, netPnl: 0),
    ]);
    expect(RiskManagementEngine.scenarioImpact(portfolio, -5), -3250);
    final snapshot = RiskManagementEngine.calculate(portfolio, const RiskSettings());
    expect(snapshot.utilization, closeTo(65, .01));
    expect(snapshot.largestPosition, closeTo(35, .01));
  });
}

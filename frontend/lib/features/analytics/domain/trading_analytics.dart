import '../../trading/domain/trading_models.dart';

/// Derived only from the local paper-trading order ledger. No analytics data is
/// persisted separately, so an account reset always resets the whole picture.
class CompletedTrade {
  const CompletedTrade({
    required this.id,
    required this.symbol,
    required this.quantity,
    required this.side,
    required this.entryPrice,
    required this.exitPrice,
    required this.entryTime,
    required this.exitTime,
    required this.realizedPnl,
  });

  final String id;
  final String symbol;
  final double quantity;
  final String side;
  final double entryPrice;
  final double exitPrice;
  final DateTime entryTime;
  final DateTime exitTime;
  final double realizedPnl;
  double get returnPercent =>
      entryPrice == 0 ? 0 : realizedPnl / (entryPrice * quantity) * 100;
  Duration get holdingDuration => exitTime.difference(entryTime);
}

class AnalyticsSummary {
  const AnalyticsSummary({
    required this.trades,
    required this.winners,
    required this.losers,
    required this.averageWin,
    required this.averageLoss,
    required this.grossProfit,
    required this.grossLoss,
    required this.expectancy,
    required this.maxDrawdown,
    required this.score,
  });
  final List<CompletedTrade> trades;
  final int winners;
  final int losers;
  final double averageWin;
  final double averageLoss;
  final double grossProfit;
  final double grossLoss;
  final double expectancy;
  final double maxDrawdown;
  final int score;
  int get total => trades.length;
  double get winRate => total == 0 ? 0 : winners / total * 100;
  double? get profitFactor => grossLoss == 0 ? null : grossProfit / grossLoss;
  double? get riskReward => averageLoss == 0 ? null : averageWin / averageLoss;
  double get totalPnl => trades.fold(0, (sum, trade) => sum + trade.realizedPnl);
}

class TradingAnalyticsEngine {
  static List<CompletedTrade> completedTrades(Iterable<TradeOrder> orders) =>
      orders
          .where((order) => order.status == 'CLOSED' && order.exitPrice != null)
          .map(
            (order) => CompletedTrade(
              id: order.id,
              symbol: order.symbol,
              quantity: order.quantity,
              side: order.side,
              entryPrice: order.entryPrice,
              exitPrice: order.exitPrice!,
              entryTime: order.createdAt,
              exitTime: order.closedAt ?? order.createdAt,
              realizedPnl: order.pnl,
            ),
          )
          .toList()
        ..sort((a, b) => b.exitTime.compareTo(a.exitTime));

  static AnalyticsSummary calculate(Iterable<TradeOrder> orders) {
    final trades = completedTrades(orders);
    final winning = trades.where((trade) => trade.realizedPnl > 0).toList();
    final losing = trades.where((trade) => trade.realizedPnl < 0).toList();
    final grossProfit = winning.fold(0.0, (sum, trade) => sum + trade.realizedPnl);
    final grossLoss = losing.fold(0.0, (sum, trade) => sum + trade.realizedPnl.abs());
    final averageWin = winning.isEmpty ? 0.0 : grossProfit / winning.length;
    final averageLoss = losing.isEmpty ? 0.0 : grossLoss / losing.length;
    final total = trades.length;
    final expectancy = total == 0
        ? 0.0
        : (winning.length / total * averageWin) -
            (losing.length / total * averageLoss);
    var cumulative = 0.0;
    var peak = 0.0;
    var maxDrawdown = 0.0;
    for (final trade in trades.reversed) {
      cumulative += trade.realizedPnl;
      if (cumulative > peak) peak = cumulative;
      maxDrawdown = maxDrawdown > peak - cumulative
          ? maxDrawdown
          : peak - cumulative;
    }
    final profitability = total == 0 ? 0 : (grossProfit - grossLoss > 0 ? 30 : 10);
    final reward = averageLoss == 0 ? 10 : (averageWin / averageLoss * 12).clamp(0, 25).round();
    final consistency = total >= 5 ? (winning.length / total * 20).round() : 5;
    final drawdown = maxDrawdown == 0 ? 15 : (15 - (maxDrawdown / 100000 * 100)).clamp(0, 15).round();
    final discipline = total == 0 ? 0 : (total <= 5 ? 10 : 6);
    return AnalyticsSummary(
      trades: trades,
      winners: winning.length,
      losers: losing.length,
      averageWin: averageWin,
      averageLoss: averageLoss,
      grossProfit: grossProfit,
      grossLoss: grossLoss,
      expectancy: expectancy,
      maxDrawdown: maxDrawdown,
      score: profitability + reward + consistency + drawdown + discipline,
    );
  }
}

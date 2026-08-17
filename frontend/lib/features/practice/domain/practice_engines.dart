import '../../analytics/domain/trading_analytics.dart';
import '../../trading/data/local_account_store.dart';
import '../../trading/domain/trading_models.dart';
import 'practice_models.dart';

class RiskSnapshot {
  const RiskSnapshot({required this.score,required this.utilization,required this.largestPosition,required this.sectorConcentration,required this.dailyPnl,required this.drawdown,required this.alerts});
  final int score; final double utilization,largestPosition,sectorConcentration,dailyPnl,drawdown; final List<String> alerts;
}
class RiskManagementEngine {
  static RiskSnapshot calculate(Portfolio p, RiskSettings settings) {
    final values=p.positions.map((x)=>x.ltp*x.quantity).toList(); final invested=values.fold(0.0,(a,b)=>a+b); final total=p.equity.abs().clamp(1.0,double.infinity).toDouble();
    final largest=values.isEmpty?0.0:values.reduce((a,b)=>a>b?a:b)/total*100;
    final sectors=<String,double>{};for(final x in p.positions){final s=sectorFor(x.symbol);sectors[s]=(sectors[s]??0)+x.ltp*x.quantity;}
    final sector=sectors.isEmpty?0.0:sectors.values.reduce((a,b)=>a>b?a:b)/total*100;
    final utilization=invested/LocalAccountStore.initialBalance*100; final daily=p.totalPnl; final drawdown=p.totalPnl<0?-p.totalPnl/LocalAccountStore.initialBalance*100:0.0;
    final score=(largest/100*25+utilization/100*20+drawdown/100*20+largest/100*20+sector/100*15).clamp(0,100).round();
    final alerts=<String>[]; if(largest>settings.maxPositionSizePercent)alerts.add('A position represents ${largest.toStringAsFixed(0)}% of portfolio value.'); if(sector>settings.maxSectorExposurePercent)alerts.add('One sector represents ${sector.toStringAsFixed(0)}% of portfolio value.'); if(daily<0&&daily.abs()>=settings.maxDailyLoss)alerts.add('Today’s paper loss has reached your configured daily limit.'); if(alerts.isEmpty)alerts.add('Current portfolio exposure is within your configured limits.');
    return RiskSnapshot(score:score,utilization:utilization,largestPosition:largest,sectorConcentration:sector,dailyPnl:daily,drawdown:drawdown,alerts:alerts);
  }
  static double scenarioImpact(Portfolio p,double percent)=>p.positions.fold(0.0,(sum,x)=>sum+x.ltp*x.quantity*percent/100);
}
String sectorFor(String symbol)=>symbol.contains('BANK')?'Banking':symbol.contains('TCS')||symbol.contains('INFY')?'IT':symbol.contains('RELIANCE')?'Energy':symbol.contains('BTC')?'Crypto':'Others';

class SetupPerformance {
  const SetupPerformance({required this.setup,required this.trades,required this.winners,required this.losers,required this.netPnl,required this.averagePnl,required this.profitFactor});
  final TradingSetup setup; final List<CompletedTrade> trades; final int winners,losers; final double netPnl,averagePnl; final double? profitFactor;
  int get count=>trades.length; double get winRate=>count==0?0:winners/count*100;
  String get sample=>count<5?'Building Data':count<20?'Early Sample':'Established Sample';
}
class StrategyAnalyticsEngine {
  static List<SetupPerformance> calculate(List<TradingSetup> setups,List<TradeJournalEntry> entries,List<TradeOrder> orders){final trades={for(final t in TradingAnalyticsEngine.completedTrades(orders))t.id:t};return setups.map((setup){final linked=entries.where((e)=>e.setupId==setup.id&&e.tradeId!=null).map((e)=>trades[e.tradeId]).whereType<CompletedTrade>().toList();final win=linked.where((x)=>x.realizedPnl>0).toList();final loss=linked.where((x)=>x.realizedPnl<0).toList();final gp=win.fold(0.0,(a,x)=>a+x.realizedPnl);final gl=loss.fold(0.0,(a,x)=>a+x.realizedPnl.abs());final net=linked.fold(0.0,(a,x)=>a+x.realizedPnl);return SetupPerformance(setup:setup,trades:linked,winners:win.length,losers:loss.length,netPnl:net,averagePnl:linked.isEmpty?0:net/linked.length,profitFactor:gl==0?null:gp/gl);}).toList()..sort((a,b)=>b.netPnl.compareTo(a.netPnl));}
}

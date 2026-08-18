import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/primary_footer.dart';

import '../../trading/data/local_account_store.dart';
import '../../trading/domain/trading_models.dart';
import '../../trading/presentation/trading_controller.dart';
import '../domain/trading_analytics.dart';

const _green = Color(0xFF28D17C);
const _red = Color(0xFFFF5468);
const _cyan = Color(0xFF36C8E8);

class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({super.key});
  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen> {
  String _period = 'ALL';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tradingControllerProvider);
    final snapshot = state.snapshot;
    if (snapshot == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final portfolio = snapshot.portfolio;
    final positions = portfolio.positions;
    final total = portfolio.equity;
    final positive = portfolio.totalPnl >= 0;
    final pct = portfolio.totalPnl / LocalAccountStore.initialBalance * 100;
    return Scaffold(
      appBar: AppBar(title: const Text('Portfolio'), actions: [PopupMenuButton<String>(
        onSelected: (value) { if (value == 'reset') _reset(context); },
        itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('Reset Portfolio', style: TextStyle(color: _red)))],
      )]),
      bottomNavigationBar: const PrimaryFooter(selectedIndex: 1),
      body: RefreshIndicator(
        onRefresh: () => ref.read(tradingControllerProvider.notifier).refresh(),
        child: positions.isEmpty && snapshot.orders.where((order) => order.status == 'CLOSED').isEmpty ? _empty(context, snapshot) : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          const Text('Portfolio Value', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(_money(total), style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
          Text('${_signed(portfolio.totalPnl)}  ·  ${_signedPct(pct)}', style: TextStyle(fontWeight: FontWeight.w700, color: positive ? _green : _red)),
          const SizedBox(height: 20),
          _tabs(_period, (value) => setState(() => _period = value)),
          const SizedBox(height: 12),
          Semantics(label: 'Portfolio performance chart. Portfolio value is ${_money(total)}. Total return is ${_signedPct(pct)}.', child: _LineChart(values: _equityPoints(portfolio), color: positive ? _green : _red, title: _period == 'ALL' ? 'All time' : _period)),
          _periodPnl(_period, portfolio.totalPnl, pct),
          const SizedBox(height: 20),
          const _SectionTitle('Account Summary'),
          _summaryGrid([['Available Cash', _money(portfolio.cashBalance)], ['Invested', _money(_invested(positions))], ['Realized P&L', _signed(portfolio.realizedPnl)], ['Unrealized P&L', _signed(portfolio.unrealizedPnl)]], [false, false, portfolio.realizedPnl >= 0, portfolio.unrealizedPnl >= 0]),
          const SizedBox(height: 20),
          _todayPnl(portfolio),
          const SizedBox(height: 24),
          _SectionTitle('Your Holdings', action: 'View All →', onAction: () => context.push('/positions')),
          ...positions.take(5).map((position) => _holding(context, position)),
          if (positions.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('No open holdings. Your completed trades remain in portfolio history.', style: TextStyle(color: Colors.white60))),
          if (positions.length > 5) TextButton(onPressed: () => context.push('/positions'), child: const Text('View All Positions →')),
          if (snapshot.orders.any((order) => order.status == 'CLOSED')) ...[
            const SizedBox(height: 20),
            _SectionTitle('Portfolio History', action: 'View analytics →', onAction: () => context.push('/analytics')),
            ...snapshot.orders
                .where((order) => order.status == 'CLOSED')
                .take(5)
                .map(
                  (order) => Card(
                    margin: const EdgeInsets.only(top: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [Icon(order.pnl >= 0 ? Icons.trending_up : Icons.trending_down, color: order.pnl >= 0 ? _green : _red), const SizedBox(width: 8), Expanded(child: Text(order.symbol, style: const TextStyle(fontWeight: FontWeight.w800))), Text(_signed(order.pnl, order.symbol), style: TextStyle(color: order.pnl >= 0 ? _green : _red, fontWeight: FontWeight.w800))]),
                          const SizedBox(height: 10),
                          Text('${order.side} · ${order.quantity} units${order.leverage > 1 ? ' · ${order.leverage}× leverage' : ''}', style: const TextStyle(color: Colors.white70)),
                          const SizedBox(height: 6),
                          Text('Entry ${_money(order.entryPrice, order.symbol)}  ·  ${_date(order.createdAt)}'),
                          Text('Exit ${_money(order.exitPrice ?? order.entryPrice, order.symbol)}  ·  ${_date(order.closedAt ?? order.createdAt)}', style: const TextStyle(color: Colors.white70)),
                          if (order.exitReason != null) Text('Exit reason: ${order.exitReason}', style: const TextStyle(fontSize: 12, color: Colors.white60)),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 20),
          const _SectionTitle('Portfolio Allocation', info: 'Shows each open position and available cash as a share of your portfolio.'),
          _allocation(portfolio, positions),
          const SizedBox(height: 20),
          const _SectionTitle('Sector Exposure'),
          _sectors(positions, total),
          const SizedBox(height: 20),
          _performers(positions),
          const SizedBox(height: 20),
          _risk(portfolio, positions),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () => context.push('/analytics'), icon: const Icon(Icons.insights_outlined), label: const Text('View Trading Analytics')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(onPressed: () => context.push('/journal'), icon: const Icon(Icons.menu_book_outlined), label: const Text('Journal')),
              OutlinedButton.icon(onPressed: () => context.push('/risk'), icon: const Icon(Icons.shield_outlined), label: const Text('Risk')),
              OutlinedButton.icon(onPressed: () => context.push('/strategies'), icon: const Icon(Icons.tune), label: const Text('Strategies')),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _empty(BuildContext context, TradingSnapshot snapshot) => ListView(children: [SizedBox(height: MediaQuery.sizeOf(context).height * .18), Padding(padding: const EdgeInsets.all(32), child: Column(children: [const Icon(Icons.account_balance_wallet_outlined, size: 52, color: _cyan), const SizedBox(height: 18), Text('Your Portfolio Is Empty', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 8), const Text('Start your first paper trade to begin tracking performance.', textAlign: TextAlign.center), const SizedBox(height: 20), FilledButton(onPressed: () => context.push('/trade'), child: const Text('Start Trading'))]))]);

  Future<void> _reset(BuildContext context) async {
    final yes = await showModalBottomSheet<bool>(context: context, builder: (sheetContext) => Padding(padding: const EdgeInsets.fromLTRB(24, 20, 24, 32), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Reset Paper Portfolio?', style: Theme.of(sheetContext).textTheme.titleLarge), const SizedBox(height: 10), const Text('This permanently removes open and closed positions, orders, trading history, and P&L history. Your watchlist stays intact.'), const SizedBox(height: 10), const Text('Virtual balance returns to ₹1,00,000.', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 20), Row(children: [Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheetContext, false), child: const Text('Cancel'))), const SizedBox(width: 12), Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: _red), onPressed: () => Navigator.pop(sheetContext, true), child: const Text('Reset Portfolio')))])])));
    if (yes == true && mounted) { await ref.read(tradingControllerProvider.notifier).reset(); }
  }
}

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  String _period = 'All';
  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(tradingControllerProvider).snapshot;
    if (snapshot == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final report = TradingAnalyticsEngine.calculate(_filtered(snapshot.orders));
    if (report.total == 0) return Scaffold(appBar: AppBar(title: const Text('Trading Analytics')), bottomNavigationBar: const PrimaryFooter(selectedIndex: 4), body: _analyticsEmpty(context));
    final hasData = report.total >= 5;
    final best = [...report.trades]..sort((a,b) => b.realizedPnl.compareTo(a.realizedPnl));
    final worst = [...report.trades]..sort((a,b) => a.realizedPnl.compareTo(b.realizedPnl));
    return Scaffold(appBar: AppBar(title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Trading Analytics'), Text('Your paper trading performance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white60))]), actions: [IconButton(onPressed: _showFilter, icon: const Icon(Icons.tune))]), bottomNavigationBar: const PrimaryFooter(selectedIndex: 4), body: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
      _analyticsTabs(), const SizedBox(height: 18), _score(report), const SizedBox(height: 20),
      const _SectionTitle('Key Trading Metrics'),
      if (!hasData) const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Building data — advanced metrics appear after 5 completed trades.', style: TextStyle(color: Colors.white60))),
      _summaryGrid([['Total Trades', '${report.total}'], ['Winning Trades', '${report.winners}'], ['Losing Trades', '${report.losers}'], ['Win Rate', '${report.winRate.toStringAsFixed(1)}%'], ['Average Win', hasData ? _money(report.averageWin) : '—'], ['Average Loss', hasData ? _money(report.averageLoss) : '—'], ['Profit Factor', hasData ? (report.profitFactor?.toStringAsFixed(2) ?? 'N/A') : '—'], ['Expectancy', hasData ? _signed(report.expectancy) : '—']], [false, true, false, true, true, false, true, report.expectancy >= 0]),
      const SizedBox(height: 20), _winRate(report), const SizedBox(height: 20),
      _metricExplain('Risk / Reward', hasData && report.riskReward != null ? '1 : ${report.riskReward!.toStringAsFixed(2)}' : 'Not enough trades', 'Average win divided by average loss.'),
      const SizedBox(height: 20), const _SectionTitle('Daily P&L'), _BarChart(values: _daily(report.trades)), const SizedBox(height: 20), const _SectionTitle('Cumulative P&L'), _LineChart(values: _cumulative(report.trades), color: _green, title: 'Completed trades'), const SizedBox(height: 20),
      _metricExplain('Maximum Drawdown', report.maxDrawdown == 0 ? '₹0.00' : '-${_money(report.maxDrawdown)}', 'The largest decline from a previous portfolio peak.'), const SizedBox(height: 20),
      _tradeList(context, 'Best Trades', best.take(3)), const SizedBox(height: 20), _tradeList(context, 'Trades to Review', worst.take(3)), const SizedBox(height: 20),
      _activity(report), const SizedBox(height: 20), _symbolPerformance(report.trades), const SizedBox(height: 20), _tradeList(context, 'Trade History', report.trades),
    ]));
  }
  List<TradeOrder> _filtered(List<TradeOrder> orders) { final now=DateTime.now(); final days={'Today':1,'7D':7,'30D':30,'3M':90}[_period]; return days == null ? orders : orders.where((o) => now.difference(o.closedAt ?? o.createdAt).inDays < days).toList(); }
  void _showFilter() => showModalBottomSheet(context: context, builder: (c) => Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Analytics filter', style: Theme.of(c).textTheme.titleLarge), const SizedBox(height: 12), const Text('Period is controlled above. Analytics are based on completed paper trades only.'), const SizedBox(height: 20), FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))])));
  Widget _analyticsTabs() => _tabs(_period, (v) => setState(() => _period = v), options: const ['Today','7D','30D','3M','All']);
}

Widget _tabs(String selected, ValueChanged<String> onSelected, {List<String> options = const ['1D','1W','1M','3M','6M','1Y','ALL']}) => SingleChildScrollView(scrollDirection: Axis.horizontal, child: SegmentedButton<String>(showSelectedIcon: false, segments: options.map((x) => ButtonSegment(value:x,label:Text(x))).toList(), selected: {selected}, onSelectionChanged: (set) => onSelected(set.first)));
class _SectionTitle extends StatelessWidget { const _SectionTitle(this.text,{this.action,this.onAction,this.info}); final String text; final String? action,info; final VoidCallback? onAction; @override Widget build(BuildContext c) => Row(children:[Expanded(child: Text(text, style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))), if(info!=null) Tooltip(message: info!, child: const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.info_outline,size:17))), if(action!=null) TextButton(onPressed:onAction,child:Text(action!))]); }
Widget _summaryGrid(List<List<String>> values, List<bool> green) => GridView.count(
  crossAxisCount: 2,
  shrinkWrap: true,
  physics: const NeverScrollableScrollPhysics(),
  childAspectRatio: 2.25,
  mainAxisSpacing: 8,
  crossAxisSpacing: 8,
  children: List.generate(
    values.length,
    (i) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101722),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF263244)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(values[i][0], style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 4),
          Text(values[i][1], style: TextStyle(fontWeight: FontWeight.w800, color: green[i] ? _green : null)),
        ],
      ),
    ),
  ),
);
Widget _periodPnl(String period,double pnl,double pct) => Padding(padding: const EdgeInsets.only(top:10), child: Row(children:[Text(period == 'ALL' ? 'All Time' : period,style:const TextStyle(color:Colors.white60)),const Spacer(),Text('${_signed(pnl)}  ${_signedPct(pct)}',style:TextStyle(color:pnl>=0?_green:_red,fontWeight:FontWeight.w700))]));
Widget _todayPnl(Portfolio p) => Container(padding:const EdgeInsets.all(16), decoration:BoxDecoration(color:const Color(0xFF101722),borderRadius:BorderRadius.circular(14)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text("Today's P&L",style:TextStyle(color:Colors.white70)),const SizedBox(height:5),Text(_signed(p.totalPnl),style:TextStyle(fontWeight:FontWeight.w800,fontSize:23,color:p.totalPnl>=0?_green:_red)),const SizedBox(height:9),Text('Realized ${_signed(p.realizedPnl)}   ·   Unrealized ${_signed(p.unrealizedPnl)}',style:const TextStyle(fontSize:12,color:Colors.white60))]));
Widget _holding(BuildContext c,Position p) => Card(margin:const EdgeInsets.only(top:8),child:ListTile(onTap:()=>c.push('/stock/${Uri.encodeComponent(p.symbol)}'),title:Text(p.symbol,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text('${p.quantity} shares · Avg ${_money(p.averagePrice,p.symbol)}'),trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[Text(_money(p.ltp*p.quantity,p.symbol)),Text(_signed(p.netPnl,p.symbol),style:TextStyle(color:p.netPnl>=0?_green:_red,fontWeight:FontWeight.w700))])));
Widget _allocation(Portfolio p,List<Position> ps) { final total=p.equity.abs().clamp(1,double.infinity); final slices=[...ps.map((x)=>(x.symbol,x.ltp*x.quantity)),('Cash',p.cashBalance)]; return Row(children:[SizedBox(width:128,height:128,child:CustomPaint(painter:_Donut(slices.map((x)=>x.$2/total).toList()))),const SizedBox(width:18),Expanded(child:Column(children:slices.take(5).map((x)=>Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(children:[Expanded(child:Text(x.$1,overflow:TextOverflow.ellipsis)),Text('${(x.$2/total*100).toStringAsFixed(0)}%',style:const TextStyle(fontWeight:FontWeight.w700))]))).toList()))]); }
Widget _sectors(List<Position> ps,double total) { final m=<String,double>{};for(final p in ps){final sector=_sector(p.symbol);m[sector]=(m[sector]??0)+p.ltp*p.quantity;} return Column(children:m.entries.map((e)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Text(e.key),const Spacer(),Text('${(e.value/total*100).toStringAsFixed(0)}%')]),const SizedBox(height:5),LinearProgressIndicator(value:(e.value/total).clamp(0,1),minHeight:7,borderRadius:BorderRadius.circular(4))]))).toList()); }
Widget _performers(List<Position> ps) { final up=[...ps]..sort((a,b)=>b.netPnl.compareTo(a.netPnl));final down=[...ps]..sort((a,b)=>a.netPnl.compareTo(b.netPnl)); return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const _SectionTitle('Top Performers'),...up.where((p)=>p.netPnl>=0).take(3).map((p)=>_simpleRow(p.symbol,_signed(p.netPnl,p.symbol),true)),const SizedBox(height:14),const _SectionTitle('Needs Attention'),...down.where((p)=>p.netPnl<0).take(3).map((p)=>_simpleRow(p.symbol,_signed(p.netPnl,p.symbol),false))]); }
Widget _risk(Portfolio p,List<Position> ps) {final total=p.equity.abs().clamp(1,double.infinity);final biggest=ps.isEmpty?0:ps.map((x)=>x.ltp*x.quantity).reduce(math.max)/total*100;return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const _SectionTitle('Portfolio Risk'),_summaryGrid([['Positions','${ps.length}'],['Largest Position','${biggest.toStringAsFixed(0)}%'],['Cash','${(p.cashBalance/total*100).toStringAsFixed(0)}%'],['Concentration',biggest>50?'High':biggest>30?'Moderate':'Low']],[false,false,false,biggest<=30])]);}
Widget _simpleRow(String a,String b,bool good)=>Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Row(children:[Text(a),const Spacer(),Text(b,style:TextStyle(fontWeight:FontWeight.w700,color:good?_green:_red))]));
Widget _analyticsEmpty(BuildContext c)=>Center(child:Padding(padding:const EdgeInsets.all(32),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[const Icon(Icons.insights_outlined,size:52,color:_cyan),const SizedBox(height:16),Text('Build Your Trading Record',style:Theme.of(c).textTheme.headlineSmall),const SizedBox(height:8),const Text('Your analytics will appear after you complete a few paper trades.',textAlign:TextAlign.center),const SizedBox(height:20),FilledButton(onPressed:()=>c.go('/trade'),child:const Text('Start with your first trade'))])));
Widget _score(AnalyticsSummary s)=>Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xFF101722),borderRadius:BorderRadius.circular(16),border:Border.all(color:const Color(0xFF263244))),child:Row(children:[SizedBox(width:82,height:82,child:Stack(fit:StackFit.expand,children:[CircularProgressIndicator(value:s.score/100,strokeWidth:8,color:_cyan,backgroundColor:const Color(0xFF263244)),Center(child:Text('${s.score}',style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800)))])),const SizedBox(width:18),const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Trading Performance',style:TextStyle(fontWeight:FontWeight.w800,fontSize:16)),Text('Learning score based on profitability, risk/reward, consistency, drawdown and frequency.',style:TextStyle(color:Colors.white60,fontSize:12))]))]));
Widget _winRate(AnalyticsSummary s)=>Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:const Color(0xFF101722),borderRadius:BorderRadius.circular(14)),child:Row(children:[SizedBox(width:72,height:72,child:Stack(fit:StackFit.expand,children:[CircularProgressIndicator(value:s.winRate/100,strokeWidth:7,color:_green,backgroundColor:const Color(0xFF263244)),Center(child:Text('${s.winRate.round()}%',style:const TextStyle(fontSize:13,fontWeight:FontWeight.w800)))])),const SizedBox(width:16),Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Win Rate',style:TextStyle(fontWeight:FontWeight.w800)),Text('${s.winners} winners · ${s.losers} losers',style:const TextStyle(color:Colors.white60))]) ]));
Widget _metricExplain(String t,String v,String info)=>Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:const Color(0xFF101722),borderRadius:BorderRadius.circular(14)),child:Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Text(t,style:const TextStyle(fontWeight:FontWeight.w700)),Tooltip(message:info,child:const Padding(padding:EdgeInsets.only(left:5),child:Icon(Icons.info_outline,size:16)))]),Text(info,style:const TextStyle(fontSize:12,color:Colors.white60))])),Text(v,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:17))]));
Widget _tradeList(BuildContext c, String title, Iterable<CompletedTrade> ts) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title),
        ...ts.map(
          (t) => Card(
            margin: const EdgeInsets.only(top: 8),
            child: ListTile(
              onTap: () => _tradeDetail(c, t),
              title: Text(t.symbol, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${t.side} · ${t.quantity} shares · ${_date(t.exitTime)}'),
              trailing: Text(
                _signed(t.realizedPnl, t.symbol),
                style: TextStyle(color: t.realizedPnl >= 0 ? _green : _red, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
void _tradeDetail(BuildContext c,CompletedTrade t)=>showModalBottomSheet(context:c,builder:(x)=>Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Trade Details',style:Theme.of(x).textTheme.titleLarge),const SizedBox(height:14),Text('${t.symbol} · ${t.quantity} shares'),const SizedBox(height:10),Text('Entry  ${_money(t.entryPrice,t.symbol)}  ·  ${_date(t.entryTime)}'),Text('Exit    ${_money(t.exitPrice,t.symbol)}  ·  ${_date(t.exitTime)}'),const SizedBox(height:10),Text('P&L ${_signed(t.realizedPnl,t.symbol)}  (${_signedPct(t.returnPercent)})',style:TextStyle(color:t.realizedPnl>=0?_green:_red,fontWeight:FontWeight.w800)),Text('Holding time ${_duration(t.holdingDuration)}'),const SizedBox(height:16),Text('Order ${t.id}',style:const TextStyle(fontSize:12,color:Colors.white60))])));
Widget _activity(AnalyticsSummary s){final days=s.trades.map((x)=>'${x.exitTime.year}-${x.exitTime.month}-${x.exitTime.day}').toSet().length;return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const _SectionTitle('Trading Activity'),_summaryGrid([['Trades','${s.total}'],['Trading Days','$days'],['Trades / Day',days==0?'—':'${(s.total/days).toStringAsFixed(1)}'],['Frequency',days==0?'—':s.total/days>5?'High':s.total/days>2?'Moderate':'Low']],[false,false,false,true])]);}
Widget _symbolPerformance(List<CompletedTrade> ts){final m=<String,double>{};for(final t in ts)m[t.symbol]=(m[t.symbol]??0)+t.realizedPnl;final e=m.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const _SectionTitle('Performance by Stock'),...e.map((x)=>_simpleRow(x.key,_signed(x.value),x.value>=0))]);}
List<double> _equityPoints(Portfolio p)=>[LocalAccountStore.initialBalance,LocalAccountStore.initialBalance+p.realizedPnl*.25,LocalAccountStore.initialBalance+p.realizedPnl*.65,p.equity];
List<double> _daily(List<CompletedTrade> ts){final m=<String,double>{};for(final t in ts){final k='${t.exitTime.day}/${t.exitTime.month}';m[k]=(m[k]??0)+t.realizedPnl;}return m.values.toList().reversed.take(7).toList().reversed.toList();}
List<double> _cumulative(List<CompletedTrade> ts){var s=0.0;return ts.reversed.map((t){s+=t.realizedPnl;return s;}).toList();}
double _invested(List<Position> ps)=>ps.fold(0,(s,p)=>s+p.averagePrice*p.quantity);
String _sector(String s)=>s.contains('BANK')?'Banking':s.contains('TCS')||s.contains('INFY')?'IT':s.contains('RELIANCE')?'Energy':s.contains('BTC')?'Crypto':'Others';
String _money(num v,[String symbol='']){final p=(symbol=='BTCUSD'||symbol=='XAUUSD'||symbol=='XUDUSD')?r'$':'₹';return '$p${v.abs().toStringAsFixed(2)}';}
String _signed(num v,[String symbol=''])=>'${v>=0?'+':'-'}${_money(v,symbol)}'; String _signedPct(num v)=>'${v>=0?'+':''}${v.toStringAsFixed(2)}%'; String _date(DateTime d)=>'${d.day}/${d.month} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}'; String _duration(Duration d)=>d.inHours>0?'${d.inHours}h ${d.inMinutes.remainder(60)}m':'${d.inMinutes}m';
class _LineChart extends StatelessWidget {const _LineChart({required this.values,required this.color,required this.title});final List<double> values;final Color color;final String title;@override Widget build(BuildContext c)=>Container(height:185,padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFF101722),borderRadius:BorderRadius.circular(14)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(color:Colors.white60,fontSize:12)),const SizedBox(height:8),Expanded(child:CustomPaint(size:Size.infinite,painter:_Line(values,color)))]));}
class _BarChart extends StatelessWidget {const _BarChart({required this.values});final List<double> values;@override Widget build(BuildContext c)=>Container(height:160,padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFF101722),borderRadius:BorderRadius.circular(14)),child:CustomPaint(size:Size.infinite,painter:_Bars(values)));}
class _Line extends CustomPainter {const _Line(this.v,this.color);final List<double> v;final Color color;@override void paint(Canvas c,Size s){if(v.isEmpty)return;final min=v.reduce(math.min),max=v.reduce(math.max),range=(max-min).abs().clamp(1,double.infinity);final p=Path();for(var i=0;i<v.length;i++){final x=i*s.width/(v.length-1==0?1:v.length-1);final y=s.height-(v[i]-min)/range*s.height*.8-s.height*.1;i==0?p.moveTo(x,y):p.lineTo(x,y);}c.drawPath(p,Paint()..color=color..strokeWidth=2.5..style=PaintingStyle.stroke);}@override bool shouldRepaint(_Line o)=>o.v!=v||o.color!=color;}
class _Bars extends CustomPainter {const _Bars(this.v);final List<double> v;@override void paint(Canvas c,Size s){if(v.isEmpty)return;final max=v.map((x)=>x.abs()).reduce(math.max).clamp(1,double.infinity),zero=s.height/2;for(var i=0;i<v.length;i++){final h=v[i].abs()/max*(s.height*.42);final x=i*s.width/v.length+s.width/v.length*.18;c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x,v[i]>=0?zero-h:zero,s.width/v.length*.64,h),const Radius.circular(3)),Paint()..color=v[i]>=0?_green:_red);}}@override bool shouldRepaint(_Bars o)=>o.v!=v;}
class _Donut extends CustomPainter {const _Donut(this.v);final List<double> v;@override void paint(Canvas c,Size s){const cs=[_cyan,Color(0xFF715BFF),_green,Color(0xFFFFB347),Color(0xFF637083)];var start=-math.pi/2;for(var i=0;i<v.length;i++){final sweep=v[i]*math.pi*2;c.drawArc(Offset(s.width/2,s.height/2)&Size.square(math.min(s.width,s.height)*.78),start,sweep,false,Paint()..color=cs[i%cs.length]..style=PaintingStyle.stroke..strokeWidth=18);start+=sweep;}}@override bool shouldRepaint(_Donut o)=>o.v!=v;}

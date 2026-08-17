import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/primary_footer.dart';

import '../domain/trading_models.dart';
import 'trading_controller.dart';

class TradeScreen extends ConsumerWidget {
  const TradeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tradingControllerProvider);
    final controller = ref.read(tradingControllerProvider.notifier);
    final quotes = state.snapshot?.quotes ?? const <Quote>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Trade')),
      bottomNavigationBar: const PrimaryFooter(selectedIndex: 2),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search a symbol to trade'), onChanged: controller.search),
        const SizedBox(height: 12),
        if (state.searchResults.isNotEmpty) ...state.searchResults.map((quote) => _TradeRow(quote: quote)),
        if (state.searchResults.isEmpty) ...quotes.map((quote) => _TradeRow(quote: quote)),
      ]),
    );
  }
}

class _TradeRow extends StatelessWidget {
  const _TradeRow({required this.quote}); final Quote quote;
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
    title: Text(quote.symbol), subtitle: Text(quote.name, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: Text(_priceFor(quote.ltp, quote.symbol), style: const TextStyle(fontWeight: FontWeight.w700)),
    onTap: () => context.push('/trade/${Uri.encodeComponent(quote.symbol)}?side=BUY'),
  ));
}

class OrderEntryScreen extends ConsumerStatefulWidget {
  const OrderEntryScreen({super.key, required this.symbol, required this.side});
  final String symbol; final OrderSide side;
  @override ConsumerState<OrderEntryScreen> createState() => _OrderEntryScreenState();
}

class _OrderEntryScreenState extends ConsumerState<OrderEntryScreen> {
  var _quantity = 1.0; var _leverage = 1; var _type = EntryOrderType.market; final _price = TextEditingController();
  @override void dispose() { _price.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final quote = _quote(ref.watch(tradingControllerProvider).snapshot?.quotes ?? const [], widget.symbol);
    if (quote == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Quote unavailable.')));
    final buy = widget.side == OrderSide.buy; final current = buy ? quote.ask : quote.bid;
    final orderPrice = double.tryParse(_price.text) ?? current;
    final total = orderPrice * _quantity;
    final leveraged = quote.instrumentType == 'CRYPTO' || quote.instrumentType == 'METAL';
    final fundsUsed = total / _leverage;
    final cash = ref.watch(tradingControllerProvider).snapshot?.portfolio.cashBalance ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text('${buy ? 'Buy' : 'Sell'} Order')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(quote.symbol, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), Text('${quote.instrumentType} · ${_priceFor(quote.ltp, quote.symbol)}'), const SizedBox(height: 22),
        SegmentedButton<EntryOrderType>(segments: const [ButtonSegment(value: EntryOrderType.market, label: Text('Market')), ButtonSegment(value: EntryOrderType.limit, label: Text('Limit')), ButtonSegment(value: EntryOrderType.stopLoss, label: Text('Stop loss'))], selected: {_type}, onSelectionChanged: (value) => setState(() => _type = value.first)),
        const SizedBox(height: 18), Text(leveraged ? 'Lots' : 'Quantity', style: Theme.of(context).textTheme.labelLarge),
        if (leveraged) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [1.0, 0.1, 0.001].map((lots) => ChoiceChip(label: Text(_lotsLabel(lots)), selected: _quantity == lots, onSelected: (_) => setState(() => _quantity = lots))).toList()),
          const SizedBox(height: 18), Text('Leverage', style: Theme.of(context).textTheme.labelLarge), const SizedBox(height: 8),
          SegmentedButton<int>(segments: const [ButtonSegment(value: 1, label: Text('1×')), ButtonSegment(value: 10, label: Text('10×')), ButtonSegment(value: 20, label: Text('20×')), ButtonSegment(value: 50, label: Text('50×')), ButtonSegment(value: 100, label: Text('100×'))], selected: {_leverage}, onSelectionChanged: (value) => setState(() => _leverage = value.first)),
        ] else Row(children: [IconButton(onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null, icon: const Icon(Icons.remove_circle_outline)), Expanded(child: Center(child: Text(_lotsLabel(_quantity), style: Theme.of(context).textTheme.headlineSmall))), IconButton(onPressed: () => setState(() => _quantity++), icon: const Icon(Icons.add_circle_outline))]),
        if (_type != EntryOrderType.market) TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: _type == EntryOrderType.limit ? 'Limit price' : 'Trigger price', prefixText: _prefix(quote.symbol))),
        const SizedBox(height: 22), _OrderSummary(label: 'Estimated market value', value: _priceFor(total, quote.symbol)), if (leveraged) _OrderSummary(label: 'Estimated funds used ($_leverage× leverage)', value: _priceFor(fundsUsed, quote.symbol)), _OrderSummary(label: 'Available cash', value: _priceFor(cash, '')),
        if (buy && fundsUsed > cash) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Insufficient virtual funds', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 26), SizedBox(height: 54, child: FilledButton(onPressed: buy && fundsUsed > cash ? null : () => _review(context, quote), child: Text('Review ${buy ? 'Buy' : 'Sell'} Order'))),
      ]),
    );
  }
  Future<void> _review(BuildContext context, Quote quote) async {
    final buy = widget.side == OrderSide.buy; final current = buy ? quote.ask : quote.bid; final price = double.tryParse(_price.text) ?? current;
    final leveraged = quote.instrumentType == 'CRYPTO' || quote.instrumentType == 'METAL';
    final notional = price * _quantity;
    final approve = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Confirm paper order'), content: Text('${buy ? 'Buy' : 'Sell'} ${_lotsLabel(_quantity)} lot(s) × ${quote.symbol}\nMarket value: ${_priceFor(notional, quote.symbol)}${leveraged ? '\nFunds used: ${_priceFor(notional / _leverage, quote.symbol)} ($_leverage× leverage)' : ''}'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Place order'))]));
    if (approve != true || !mounted) return;
    final success = await ref.read(tradingControllerProvider.notifier).placeOrder(quote, widget.side, _quantity, orderType: _type, orderPrice: _type == EntryOrderType.market ? null : price, leverage: leveraged ? _leverage : 1);
    if (success && mounted) context.go('/positions');
  }
}

class PositionsScreen extends ConsumerStatefulWidget {
  const PositionsScreen({super.key});

  @override
  ConsumerState<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends ConsumerState<PositionsScreen> {
  var _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(tradingControllerProvider).snapshot;
    final positions = snapshot?.portfolio.positions ?? const <Position>[];
    final history = (snapshot?.orders ?? const <TradeOrder>[])
        .where((order) => order.status == 'CLOSED')
        .toList()
      ..sort((a, b) => (b.closedAt ?? b.createdAt).compareTo(a.closedAt ?? a.createdAt));
    return Scaffold(
      appBar: AppBar(title: const Text('Positions')),
      bottomNavigationBar: const PrimaryFooter(selectedIndex: 3),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Open')),
              ButtonSegment(value: true, label: Text('History')),
            ],
            selected: {_showHistory},
            onSelectionChanged: (value) => setState(() => _showHistory = value.first),
          ),
          const SizedBox(height: 16),
          if (!_showHistory && positions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 56),
              child: Center(child: Text('No open positions')),
            )
          else if (!_showHistory)
            ...positions.map(
              (item) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(item.symbol),
                  subtitle: Text('${item.side} · ${item.quantity} @ ${_priceFor(item.averagePrice, item.symbol)}'),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_priceFor(item.netPnl, item.symbol), style: TextStyle(color: item.netPnl >= 0 ? Colors.greenAccent : Colors.redAccent)),
                    TextButton(onPressed: () => ref.read(tradingControllerProvider.notifier).closeTrade(item.orderId), child: const Text('Exit')),
                  ]),
                ),
              ),
            )
          else if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 56),
              child: Center(child: Text('No closed-position history yet')),
            )
          else
            ...history.map(
              (item) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(item.pnl >= 0 ? Icons.trending_up : Icons.trending_down, color: item.pnl >= 0 ? Colors.greenAccent : Colors.redAccent),
                  title: Text(item.symbol),
                  subtitle: Text('${item.side} · ${item.quantity} · Closed ${_historyDate(item.closedAt ?? item.createdAt)}'),
                  trailing: Text(_priceFor(item.pnl, item.symbol), style: TextStyle(fontWeight: FontWeight.w700, color: item.pnl >= 0 ? Colors.greenAccent : Colors.redAccent)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(tradingControllerProvider).snapshot;
    final pending = snapshot?.pendingOrders ?? const <PendingOrder>[];
    final history = snapshot?.orders ?? const <TradeOrder>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      bottomNavigationBar: const PrimaryFooter(selectedIndex: 3),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Open Orders', style: Theme.of(context).textTheme.titleMedium),
        if (pending.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No open orders')),
        ...pending.map((item) => Card(child: ListTile(title: Text(item.symbol), subtitle: Text('${item.side} · ${item.orderType} · ${item.quantity}'), trailing: TextButton(onPressed: () => ref.read(tradingControllerProvider.notifier).cancelPendingOrder(item.id), child: const Text('Cancel'))))),
        const SizedBox(height: 20),
        Text('Order History', style: Theme.of(context).textTheme.titleMedium),
        ...history.map((item) => Card(child: ListTile(title: Text(item.symbol), subtitle: Text('${item.side} · ${item.status}'), trailing: Text(_priceFor(item.pnl, item.symbol))))),
      ]),
    );
  }
}

class _OrderSummary extends StatelessWidget { const _OrderSummary({required this.label, required this.value}); final String label; final String value; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [Text(label), const Spacer(), Text(value, style: const TextStyle(fontWeight: FontWeight.w700))])); }

Quote? _quote(List<Quote> quotes, String symbol) { for (final quote in quotes) { if (quote.symbol == symbol) return quote; } return null; }
String _prefix(String symbol) => symbol == 'BTCUSD' || symbol == 'XAUUSD' ? r'$ ' : '₹ ';
String _priceFor(num value, String symbol) => '${_prefix(symbol)}${value.toStringAsFixed(2)}';
String _historyDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
String _lotsLabel(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

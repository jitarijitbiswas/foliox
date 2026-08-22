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
    final recentTrades = (state.snapshot?.orders ?? const <TradeOrder>[])
        .where((order) => order.status == 'CLOSED')
        .toList()
      ..sort((a, b) => (b.closedAt ?? b.createdAt).compareTo(a.closedAt ?? a.createdAt));
    return Scaffold(
      appBar: AppBar(title: const Text('Trade')),
      bottomNavigationBar: const PrimaryFooter(selectedIndex: 2),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search a symbol to trade'), onChanged: controller.search),
        const SizedBox(height: 12),
        if (state.searchResults.isNotEmpty) ...state.searchResults.map((quote) => _TradeRow(quote: quote)),
        if (state.searchResults.isEmpty) ...quotes.map((quote) => _TradeRow(quote: quote)),
        if (recentTrades.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Recent completed trades', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...recentTrades.take(5).map((order) => _CompletedTradeRow(order: order)),
        ],
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
  var _quantity = 1.0;
  var _leverage = 1;
  var _type = EntryOrderType.market;
  final _price = TextEditingController();
  final _quantityInput = TextEditingController(text: '1');
  final _target = TextEditingController();
  final _stopLoss = TextEditingController();

  @override
  void dispose() {
    _price.dispose();
    _quantityInput.dispose();
    _target.dispose();
    _stopLoss.dispose();
    super.dispose();
  }

  void _setQuantity(double value) {
    setState(() {
      _quantity = value;
      _quantityInput.text = _lotsLabel(value);
    });
  }

  void _setOrderType(EntryOrderType type, double capturedPrice) {
    setState(() {
      _type = type;
      if (type != EntryOrderType.market && _price.text.trim().isEmpty) {
        _price.text = _inputPrice(capturedPrice);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote(ref.watch(tradingControllerProvider).snapshot?.quotes ?? const [], widget.symbol);
    if (quote == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Quote unavailable.')));
    final buy = widget.side == OrderSide.buy; final current = buy ? quote.ask : quote.bid;
    final orderPrice = double.tryParse(_price.text) ?? current;
    final total = orderPrice * _quantity * quote.lotSize;
    final leveraged = quote.instrumentType == 'CRYPTO' || quote.instrumentType == 'METAL';
    final fundsUsed = total / _leverage;
    final cash = ref.watch(tradingControllerProvider).snapshot?.portfolio.cashBalance ?? 0;
    final minimumLot = leveraged ? .001 : 1.0;
    final quantityValid = _quantity >= minimumLot &&
        (!leveraged || ((_quantity * 1000).roundToDouble() - _quantity * 1000).abs() < .000001);
    return Scaffold(
      appBar: AppBar(title: Text('${buy ? 'Buy' : 'Sell'} Order')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(quote.symbol, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), Text('${quote.instrumentType} · ${_priceFor(quote.ltp, quote.symbol)}'), const SizedBox(height: 22),
        SegmentedButton<EntryOrderType>(segments: const [ButtonSegment(value: EntryOrderType.market, label: Text('Market')), ButtonSegment(value: EntryOrderType.limit, label: Text('Limit')), ButtonSegment(value: EntryOrderType.stopLoss, label: Text('Stop loss'))], selected: {_type}, onSelectionChanged: (value) => _setOrderType(value.first, current)),
        const SizedBox(height: 18), Text(leveraged ? 'Lots' : 'Quantity', style: Theme.of(context).textTheme.labelLarge),
        if (leveraged) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [1.0, 0.1, 0.001].map((lots) => ChoiceChip(label: Text(_lotsLabel(lots)), selected: _quantity == lots, onSelected: (_) => _setQuantity(lots))).toList()),
          const SizedBox(height: 18), Text('Leverage', style: Theme.of(context).textTheme.labelLarge), const SizedBox(height: 8),
          SegmentedButton<int>(segments: const [ButtonSegment(value: 1, label: Text('1×')), ButtonSegment(value: 10, label: Text('10×')), ButtonSegment(value: 20, label: Text('20×')), ButtonSegment(value: 50, label: Text('50×')), ButtonSegment(value: 100, label: Text('100×'))], selected: {_leverage}, onSelectionChanged: (value) => setState(() => _leverage = value.first)),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _quantityInput,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) => setState(() => _quantity = double.tryParse(value) ?? 0),
          decoration: InputDecoration(
            labelText: leveraged ? 'Lots (minimum 0.001)' : 'Quantity (whole units)',
            helperText: leveraged ? 'Any multiple of 0.001 is supported.' : null,
            errorText: quantityValid ? null : leveraged ? 'Enter a multiple of 0.001.' : 'Enter at least 1 unit.',
          ),
        ),
        if (_type != EntryOrderType.market) TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: _type == EntryOrderType.limit ? 'Limit price' : 'Trigger price', prefixText: _prefix(quote.symbol), helperText: _type == EntryOrderType.limit ? 'Captured ${buy ? 'ask' : 'bid'}: ${_priceFor(current, quote.symbol)}. Adjust slightly to keep it pending.' : 'Captured ${buy ? 'ask' : 'bid'}: ${_priceFor(current, quote.symbol)}')),
        const SizedBox(height: 22), _OrderSummary(label: 'Estimated market value', value: _priceFor(total, quote.symbol)), if (leveraged) _OrderSummary(label: 'Estimated funds used ($_leverage× leverage)', value: _priceFor(fundsUsed, quote.symbol)), _OrderSummary(label: 'Available cash', value: _priceFor(cash, '')),
        if (_type == EntryOrderType.limit) Padding(padding: const EdgeInsets.only(top: 4), child: Text(buy ? 'To remain pending, set the buy limit below the current ask.' : 'To remain pending, set the sell limit above the current bid.', style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(height: 10),
        TextField(controller: _target, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Target price (optional)', prefixText: _prefix(quote.symbol))),
        const SizedBox(height: 10),
        TextField(controller: _stopLoss, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Stop-loss price (optional)', prefixText: _prefix(quote.symbol))),
        if (buy && fundsUsed > cash) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Insufficient virtual funds', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 26), SizedBox(height: 54, child: FilledButton(onPressed: !quantityValid || (buy && fundsUsed > cash) ? null : () => _review(context, quote), child: Text('Review ${buy ? 'Buy' : 'Sell'} Order'))),
      ]),
    );
  }
  Future<void> _review(BuildContext context, Quote quote) async {
    final buy = widget.side == OrderSide.buy; final current = buy ? quote.ask : quote.bid; final price = double.tryParse(_price.text) ?? current;
    final leveraged = quote.instrumentType == 'CRYPTO' || quote.instrumentType == 'METAL';
    final notional = price * _quantity * quote.lotSize;
    final approve = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Confirm paper order'), content: Text('${buy ? 'Buy' : 'Sell'} ${_lotsLabel(_quantity)} lot(s) × ${quote.symbol}\nMarket value: ${_priceFor(notional, quote.symbol)}${leveraged ? '\nFunds used: ${_priceFor(notional / _leverage, quote.symbol)} ($_leverage× leverage)' : ''}'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Place order'))]));
    if (approve != true || !mounted) return;
    final success = await ref.read(tradingControllerProvider.notifier).placeOrder(quote, widget.side, _quantity, orderType: _type, orderPrice: _type == EntryOrderType.market ? null : price, targetPrice: double.tryParse(_target.text), stopLoss: double.tryParse(_stopLoss.text), leverage: leveraged ? _leverage : 1);
    if (success && mounted) context.go(_type == EntryOrderType.market ? '/positions' : '/orders');
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
                  onTap: () => _showTradeDetails(context, item),
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
        ...pending.map((item) => _PendingOrderRow(order: item)),
        const SizedBox(height: 20),
        Text('Order History', style: Theme.of(context).textTheme.titleMedium),
        ...history.map((item) => Card(child: ListTile(onTap: item.status == 'CLOSED' ? () => _showTradeDetails(context, item) : null, title: Text(item.symbol), subtitle: Text('${item.side} · ${item.status}'), trailing: Text(_priceFor(item.pnl, item.symbol))))),
      ]),
    );
  }
}

class _PendingOrderRow extends ConsumerWidget {
  const _PendingOrderRow({required this.order});
  final PendingOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: ListTile(
      title: Text(order.symbol),
      subtitle: Text(
        '${order.side} · ${order.orderType} · ${_lotsLabel(order.quantity)}\n'
        'Price ${_priceFor(order.orderPrice, order.symbol)}'
        '${order.targetPrice == null ? '' : ' · Target ${_priceFor(order.targetPrice!, order.symbol)}'}'
        '${order.stopLoss == null ? '' : ' · Stop ${_priceFor(order.stopLoss!, order.symbol)}'}',
      ),
      isThreeLine: order.targetPrice != null || order.stopLoss != null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => _editPendingOrder(context, ref, order),
            child: const Text('Edit'),
          ),
          TextButton(
            onPressed: () => ref
                .read(tradingControllerProvider.notifier)
                .cancelPendingOrder(order.id),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _editPendingOrder(
  BuildContext context,
  WidgetRef ref,
  PendingOrder order,
) async {
  final quantity = TextEditingController(text: _lotsLabel(order.quantity));
  final price = TextEditingController(text: _inputPrice(order.orderPrice));
  final target = TextEditingController(
    text: order.targetPrice == null ? '' : _inputPrice(order.targetPrice!),
  );
  final stop = TextEditingController(
    text: order.stopLoss == null ? '' : _inputPrice(order.stopLoss!),
  );
  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit ${order.symbol} ${order.orderType}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: quantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: order.orderType == 'LIMIT'
                      ? 'Limit price'
                      : 'Trigger price',
                  prefixText: _prefix(order.symbol),
                ),
              ),
              TextField(
                controller: target,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Target price (optional)',
                  prefixText: _prefix(order.symbol),
                ),
              ),
              TextField(
                controller: stop,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Stop-loss price (optional)',
                  prefixText: _prefix(order.symbol),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () async {
              final parsedQuantity = double.tryParse(quantity.text);
              final parsedPrice = double.tryParse(price.text);
              if (parsedQuantity == null || parsedPrice == null) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Enter a valid quantity and price.')),
                );
                return;
              }
              final saved = await ref
                  .read(tradingControllerProvider.notifier)
                  .updatePendingOrder(
                    order.id,
                    quantity: parsedQuantity,
                    orderPrice: parsedPrice,
                    targetPrice: _optionalNumber(target.text),
                    stopLoss: _optionalNumber(stop.text),
                  );
              if (saved && dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save changes'),
          ),
        ],
      ),
    );
  } finally {
    quantity.dispose();
    price.dispose();
    target.dispose();
    stop.dispose();
  }
}

class _OrderSummary extends StatelessWidget { const _OrderSummary({required this.label, required this.value}); final String label; final String value; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [Text(label), const Spacer(), Text(value, style: const TextStyle(fontWeight: FontWeight.w700))])); }

class _CompletedTradeRow extends StatelessWidget {
  const _CompletedTradeRow({required this.order});
  final TradeOrder order;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      onTap: () => _showTradeDetails(context, order),
      leading: Icon(order.pnl >= 0 ? Icons.trending_up : Icons.trending_down, color: order.pnl >= 0 ? Colors.greenAccent : Colors.redAccent),
      title: Text(order.symbol),
      subtitle: Text('${order.side} · ${_historyDate(order.closedAt ?? order.createdAt)}'),
      trailing: Text(_priceFor(order.pnl, order.symbol), style: TextStyle(fontWeight: FontWeight.w700, color: order.pnl >= 0 ? Colors.greenAccent : Colors.redAccent)),
    ),
  );
}

Future<void> _showTradeDetails(BuildContext context, TradeOrder order) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (sheetContext) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trade Details', style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Text('${order.symbol} · ${order.side} · ${_lotsLabel(order.quantity)} units${order.leverage > 1 ? ' · ${order.leverage}× leverage' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          _OrderSummary(label: 'Entry price', value: _priceFor(order.entryPrice, order.symbol)),
          _OrderSummary(label: 'Entry time', value: _tradeDateTime(order.createdAt)),
          _OrderSummary(label: 'Exit price', value: order.exitPrice == null ? 'Open' : _priceFor(order.exitPrice!, order.symbol)),
          _OrderSummary(label: 'Exit time', value: order.closedAt == null ? '—' : _tradeDateTime(order.closedAt!)),
          if (order.exitReason != null) _OrderSummary(label: 'Exit reason', value: order.exitReason!),
          const Divider(height: 26),
          _OrderSummary(label: 'Realized P&L', value: _priceFor(order.pnl, order.symbol)),
        ],
      ),
    ),
  ),
);

Quote? _quote(List<Quote> quotes, String symbol) { for (final quote in quotes) { if (quote.symbol == symbol) return quote; } return null; }
String _prefix(String symbol) => symbol == 'BTCUSD' || symbol == 'XAUUSD' ? r'$ ' : '₹ ';
String _priceFor(num value, String symbol) => '${_prefix(symbol)}${value.toStringAsFixed(2)}';
String _inputPrice(double value) => value.toStringAsFixed(2);
double? _optionalNumber(String value) =>
    value.trim().isEmpty ? null : double.tryParse(value);
String _historyDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
String _tradeDateTime(DateTime date) => '${_historyDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String _lotsLabel(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

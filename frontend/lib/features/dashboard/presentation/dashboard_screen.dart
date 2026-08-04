import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../trading/domain/trading_models.dart';
import '../../trading/presentation/trading_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tradingControllerProvider);
    final controller = ref.read(tradingControllerProvider.notifier);
    final portfolio = state.snapshot?.portfolio;

    ref.listen(tradingControllerProvider, (previous, next) {
      final text = next.error ?? next.message;
      if (text != null &&
          text != previous?.error &&
          text != previous?.message) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('PaperTrade Demo'),
        actions: [
          const Chip(
            avatar: Icon(Icons.wifi_tethering, size: 16),
            label: Text('NSE LIVE'),
          ),
          IconButton(
            tooltip: 'Reset demo account',
            onPressed: state.isSubmitting ? null : controller.reset,
            icon: const Icon(Icons.restart_alt),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: state.isLoading && state.snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: controller.refresh,
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverToBoxAdapter(
                      child: SearchBar(
                        hintText: 'Search NIFTY, BANKNIFTY, options or stocks',
                        leading: const Icon(Icons.search),
                        onChanged: controller.search,
                      ),
                    ),
                  ),
                  if (state.isSearching)
                    const SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (state.searchResults.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver: SliverToBoxAdapter(
                        child: _SearchResults(
                          quotes: state.searchResults,
                          onAdd: controller.addToWatchlist,
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverToBoxAdapter(
                      child: _Metrics(portfolio: portfolio),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Open positions',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverToBoxAdapter(
                      child: _Positions(
                        positions: portfolio?.positions ?? const [],
                        onEdit: (position) =>
                            _showRiskEditor(context, ref, position),
                        onClose: (position) =>
                            _confirmClose(context, ref, position),
                        onRefresh: (_) => controller.refresh(silent: true),
                        checkedAt: state.snapshot?.refreshedAt,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Watchlist',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'NIFTY ${_money(state.snapshot?.underlying ?? 0)} · NSE ${state.snapshot?.timestamp ?? '—'} · Checked ${_clock(state.snapshot?.refreshedAt)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.separated(
                      itemCount: state.visibleQuotes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final quote = state.visibleQuotes[index];
                        return _QuoteTile(
                          quote: quote,
                          onRemove: () =>
                              controller.removeFromWatchlist(quote.symbol),
                          onTrade: quote.isTradable
                              ? (side) =>
                                    _showOrderTicket(context, ref, quote, side)
                              : null,
                        );
                      },
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Pending orders',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverToBoxAdapter(
                      child: _PendingOrders(
                        orders: state.snapshot?.pendingOrders ?? const [],
                        onCancel: controller.cancelPendingOrder,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Trade history',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverToBoxAdapter(
                      child: _TradeHistory(
                        orders: state.snapshot?.orders ?? const [],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _showOrderTicket(
    BuildContext context,
    WidgetRef ref,
    Quote quote,
    OrderSide side,
  ) async {
    var lots = 1;
    var target = '';
    var stopLoss = '';
    var orderPrice = '';
    var orderType = EntryOrderType.market;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final price = side == OrderSide.buy ? quote.ask : quote.bid;
          return AlertDialog(
            title: Text(
              '${side == OrderSide.buy ? 'Buy' : 'Sell'} ${quote.symbol}',
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${quote.name} · ${orderType.name.toUpperCase()} order'),
                  const SizedBox(height: 20),
                  SegmentedButton<EntryOrderType>(
                    segments: const [
                      ButtonSegment(
                        value: EntryOrderType.market,
                        label: Text('Market'),
                      ),
                      ButtonSegment(
                        value: EntryOrderType.limit,
                        label: Text('Limit'),
                      ),
                      ButtonSegment(
                        value: EntryOrderType.stopLoss,
                        label: Text('Stop-loss'),
                      ),
                    ],
                    selected: {orderType},
                    onSelectionChanged: (selection) =>
                        setState(() => orderType = selection.first),
                  ),
                  if (orderType != EntryOrderType.market) ...[
                    const SizedBox(height: 12),
                    TextField(
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: orderType == EntryOrderType.limit
                            ? 'Limit price'
                            : 'Trigger price',
                        prefixText: '₹ ',
                      ),
                      onChanged: (value) => orderPrice = value,
                    ),
                  ],
                  Row(
                    children: [
                      IconButton(
                        onPressed: lots > 1
                            ? () => setState(() => lots--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        '$lots lot${lots == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      IconButton(
                        onPressed: () => setState(() => lots++),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  Text(
                    'Quantity: ${lots * quote.lotSize} · Lot size: ${quote.lotSize}',
                  ),
                  const SizedBox(height: 8),
                  Text('Estimated fill: ${_money(price)}'),
                  Text(
                    'Estimated value: ${_money(price * lots * quote.lotSize)}',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Target price (optional)',
                      prefixText: '₹ ',
                    ),
                    onChanged: (value) => target = value,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Stop-loss price (optional)',
                      prefixText: '₹ ',
                    ),
                    onChanged: (value) => stopLoss = value,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: side == OrderSide.buy
                      ? Colors.teal
                      : Colors.red.shade700,
                ),
                onPressed: () async {
                  final succeeded = await ref
                      .read(tradingControllerProvider.notifier)
                      .placeOrder(
                        quote,
                        side,
                        lots,
                        orderType: orderType,
                        orderPrice: double.tryParse(orderPrice),
                        targetPrice: double.tryParse(target),
                        stopLoss: double.tryParse(stopLoss),
                      );
                  if (succeeded && dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                child: Text(
                  'Confirm ${side == OrderSide.buy ? 'buy' : 'sell'}',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showRiskEditor(
    BuildContext context,
    WidgetRef ref,
    Position position,
  ) async {
    var target = position.targetPrice?.toString() ?? '';
    var stopLoss = position.stopLoss?.toString() ?? '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit ${position.symbol}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Entry ${_money(position.averagePrice)} · ${position.side}'),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: target,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Target price',
                  prefixText: '₹ ',
                ),
                onChanged: (value) => target = value,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: stopLoss,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Stop-loss price',
                  prefixText: '₹ ',
                ),
                onChanged: (value) => stopLoss = value,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final updated = await ref
                  .read(tradingControllerProvider.notifier)
                  .updateRisk(
                    position.orderId,
                    targetPrice: double.tryParse(target),
                    stopLoss: double.tryParse(stopLoss),
                  );
              if (updated && dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Save changes'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClose(
    BuildContext context,
    WidgetRef ref,
    Position position,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Exit ${position.symbol}?'),
        content: Text(
          'The ${position.side} position will close at the current live '
          '${position.side == 'BUY' ? 'bid' : 'ask'} price. Current P&L: '
          '${_money(position.netPnl)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Exit trade'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(tradingControllerProvider.notifier)
          .closeTrade(position.orderId);
    }
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.quotes, required this.onAdd});
  final List<Quote> quotes;
  final ValueChanged<Quote> onAdd;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        const ListTile(title: Text('Search results')),
        ...quotes.map(
          (quote) => ListTile(
            title: Text(quote.symbol),
            subtitle: Text(quote.name),
            trailing: IconButton(
              tooltip: 'Add to watchlist',
              onPressed: () => onAdd(quote),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.portfolio});
  final Portfolio? portfolio;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('Virtual cash', _money(portfolio?.cashBalance ?? 0)),
      ('Account equity', _money(portfolio?.equity ?? 0)),
      ('Total P&L', _money(portfolio?.totalPnl ?? 0)),
      ('Open positions', '${portfolio?.positions.length ?? 0}'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 900
            ? (constraints.maxWidth - 36) / 4
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: metrics
              .map(
                (item) => SizedBox(
                  width: width,
                  child: _MetricCard(label: item.$1, value: item.$2),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    ),
  );
}

class _QuoteTile extends StatelessWidget {
  const _QuoteTile({required this.quote, this.onTrade, this.onRemove});
  final Quote quote;
  final ValueChanged<OrderSide>? onTrade;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quote.symbol,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(quote.name),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _money(quote.ltp),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '${quote.changePercent >= 0 ? '+' : ''}${quote.changePercent.toStringAsFixed(2)}%',
              ),
            ],
          ),
          const SizedBox(width: 16),
          OutlinedButton(
            onPressed: onTrade == null ? null : () => onTrade!(OrderSide.buy),
            child: const Text('BUY'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onTrade == null ? null : () => onTrade!(OrderSide.sell),
            child: const Text('SELL'),
          ),
          IconButton(
            tooltip: 'Remove from watchlist',
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    ),
  );
}

class _Positions extends StatelessWidget {
  const _Positions({
    required this.positions,
    required this.onEdit,
    required this.onClose,
    required this.onRefresh,
    required this.checkedAt,
  });
  final List<Position> positions;
  final ValueChanged<Position> onEdit;
  final ValueChanged<Position> onClose;
  final ValueChanged<Position> onRefresh;
  final DateTime? checkedAt;

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text('No open positions. Use BUY or SELL above.'),
          ),
        ),
      );
    }
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Symbol')),
            DataColumn(label: Text('Side')),
            DataColumn(label: Text('Qty')),
            DataColumn(label: Text('Average')),
            DataColumn(label: Text('LTP')),
            DataColumn(label: Text('Target')),
            DataColumn(label: Text('Stop-loss')),
            DataColumn(label: Text('P&L')),
            DataColumn(label: Text('NSE tick / checked')),
            DataColumn(label: Text('Actions')),
          ],
          rows: positions
              .map(
                (position) => DataRow(
                  cells: [
                    DataCell(Text(position.symbol)),
                    DataCell(Text(position.side)),
                    DataCell(Text('${position.quantity}')),
                    DataCell(Text(_money(position.averagePrice))),
                    DataCell(Text(_money(position.ltp))),
                    DataCell(Text(_optionalMoney(position.targetPrice))),
                    DataCell(Text(_optionalMoney(position.stopLoss))),
                    DataCell(Text(_money(position.netPnl))),
                    DataCell(
                      Text(
                        '${position.timestamp.isEmpty ? '—' : position.timestamp}\nChecked ${_clock(checkedAt)}',
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit target / stop-loss',
                            onPressed: () => onEdit(position),
                            icon: const Icon(Icons.edit_note),
                          ),
                          IconButton(
                            tooltip: 'Exit / Close trade',
                            onPressed: () => onClose(position),
                            color: Colors.red,
                            icon: const Icon(Icons.exit_to_app),
                          ),
                          IconButton(
                            tooltip: 'Refresh this trade LTP and P&L',
                            onPressed: () => onRefresh(position),
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _PendingOrders extends StatelessWidget {
  const _PendingOrders({required this.orders, required this.onCancel});
  final List<PendingOrder> orders;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    final pending = orders.where((order) => order.status == 'PENDING').toList();
    if (pending.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No pending limit or stop-loss orders.')),
        ),
      );
    }
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Symbol')),
            DataColumn(label: Text('Side')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Qty')),
            DataColumn(label: Text('Price / Trigger')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Action')),
          ],
          rows: pending
              .map(
                (order) => DataRow(
                  cells: [
                    DataCell(Text(order.symbol)),
                    DataCell(Text(order.side)),
                    DataCell(Text(order.orderType.replaceAll('_', ' '))),
                    DataCell(Text('${order.quantity}')),
                    DataCell(Text(_money(order.orderPrice))),
                    DataCell(Text(order.status)),
                    DataCell(
                      TextButton(
                        onPressed: () => onCancel(order.id),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _TradeHistory extends StatelessWidget {
  const _TradeHistory({required this.orders});
  final List<TradeOrder> orders;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No trades recorded yet.')),
        ),
      );
    }
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Time')),
            DataColumn(label: Text('Symbol')),
            DataColumn(label: Text('Side')),
            DataColumn(label: Text('Qty')),
            DataColumn(label: Text('Entry')),
            DataColumn(label: Text('Target')),
            DataColumn(label: Text('Stop-loss')),
            DataColumn(label: Text('Exit')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('P&L')),
          ],
          rows: orders
              .map(
                (order) => DataRow(
                  cells: [
                    DataCell(
                      Text(
                        order.createdAt.toLocal().toString().substring(0, 16),
                      ),
                    ),
                    DataCell(Text(order.symbol)),
                    DataCell(Text(order.side)),
                    DataCell(Text('${order.quantity}')),
                    DataCell(Text(_money(order.entryPrice))),
                    DataCell(Text(_optionalMoney(order.targetPrice))),
                    DataCell(Text(_optionalMoney(order.stopLoss))),
                    DataCell(Text(_optionalMoney(order.exitPrice))),
                    DataCell(Text(order.exitReason ?? order.status)),
                    DataCell(Text(_money(order.pnl))),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

String _money(num value) => '₹${value.toStringAsFixed(2)}';
String _optionalMoney(num? value) => value == null ? '—' : _money(value);
String _clock(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

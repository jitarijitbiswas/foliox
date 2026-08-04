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
            avatar: Icon(Icons.science_outlined, size: 16),
            label: Text('SIMULATED DATA'),
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
                        'Market watch',
                        style: Theme.of(context).textTheme.titleLarge,
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
                  Text('${quote.name} · Market order'),
                  const SizedBox(height: 20),
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
                      .placeOrder(quote, side, lots);
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
  const _QuoteTile({required this.quote, this.onTrade});
  final Quote quote;
  final ValueChanged<OrderSide>? onTrade;

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
        ],
      ),
    ),
  );
}

class _Positions extends StatelessWidget {
  const _Positions({required this.positions});
  final List<Position> positions;

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
            DataColumn(label: Text('Qty')),
            DataColumn(label: Text('Average')),
            DataColumn(label: Text('LTP')),
            DataColumn(label: Text('P&L')),
          ],
          rows: positions
              .map(
                (position) => DataRow(
                  cells: [
                    DataCell(Text(position.symbol)),
                    DataCell(Text('${position.quantity}')),
                    DataCell(Text(_money(position.averagePrice))),
                    DataCell(Text(_money(position.ltp))),
                    DataCell(Text(_money(position.netPnl))),
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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../app/primary_footer.dart';
import '../../trading/domain/trading_models.dart';
import '../../trading/presentation/trading_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    final pagePadding = isMobile ? 10.0 : 16.0;
    final state = ref.watch(tradingControllerProvider);
    final controller = ref.read(tradingControllerProvider.notifier);
    final portfolio = state.snapshot?.portfolio;
    final profileName = Hive.box<String>('foliox_settings')
        .get('local_account_name', defaultValue: 'Trader')!
        .trim();
    final accountId = Hive.box<String>('foliox_settings')
        .get('active_account_id', defaultValue: '')!;
    final profilePhoto = _profilePhoto(
      Hive.box<String>('foliox_settings').get('profile_image:$accountId'),
    );

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/trade'),
        icon: const Icon(Icons.add),
        label: const Text('Trade'),
      ),
      bottomNavigationBar: const PrimaryFooter(selectedIndex: 0, isHomeRoute: true),
      body: state.isLoading && state.snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: controller.refresh,
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      pagePadding,
                      18,
                      pagePadding,
                      12,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _DashboardHeader(
                        name: profileName.isEmpty ? 'Trader' : profileName,
                        photo: profilePhoto,
                        onProfile: () => context.push('/profile'),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: pagePadding),
                    sliver: SliverToBoxAdapter(
                      child: _Metrics(portfolio: portfolio),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      pagePadding,
                      14,
                      pagePadding,
                      16,
                    ),
                    sliver: SliverToBoxAdapter(child: _QuickActions()),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      pagePadding,
                      0,
                      pagePadding,
                      16,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _PerformanceSnapshot(
                        totalPnl: portfolio?.totalPnl ?? 0,
                        orders: state.snapshot?.orders ?? const [],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.all(pagePadding),
                    sliver: SliverToBoxAdapter(
                      child: SearchBar(
                        hintText: 'Search stocks, options, BTCUSD or XAUUSD',
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
                      padding: EdgeInsets.fromLTRB(
                        pagePadding,
                        0,
                        pagePadding,
                        16,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _SearchResults(
                          quotes: state.searchResults,
                          onAdd: controller.addToWatchlist,
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      pagePadding,
                      0,
                      pagePadding,
                      12,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Open positions',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      pagePadding,
                      0,
                      pagePadding,
                      24,
                    ),
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
                    padding: EdgeInsets.fromLTRB(
                      pagePadding,
                      0,
                      pagePadding,
                      12,
                    ),
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
                            'NIFTY ${_money(state.snapshot?.underlying ?? 0)} · Live quotes · Updated ${_clock(state.snapshot?.refreshedAt)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: pagePadding),
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
                    padding: EdgeInsets.fromLTRB(
                      pagePadding,
                      24,
                      pagePadding,
                      12,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Pending orders',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      pagePadding,
                      0,
                      pagePadding,
                      24,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _PendingOrders(
                        orders: state.snapshot?.pendingOrders ?? const [],
                        onCancel: controller.cancelPendingOrder,
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
    var lots = 1.0;
    var leverage = 1;
    var target = '';
    var stopLoss = '';
    var orderPrice = '';
    var orderType = EntryOrderType.market;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final price = side == OrderSide.buy ? quote.ask : quote.bid;
          final leveragedAsset =
              quote.instrumentType == 'CRYPTO' || quote.instrumentType == 'METAL';
          final effectivePrice = orderType == EntryOrderType.market
              ? price
              : (double.tryParse(orderPrice) ?? price);
          final notional = effectivePrice * lots * quote.lotSize;
          final fundsUsed = notional / leverage;
          final availableCash = ref
              .read(tradingControllerProvider)
              .snapshot
              ?.portfolio
              .cashBalance ?? 0;
          final insufficientFunds = side == OrderSide.buy && fundsUsed > availableCash;
          return AlertDialog(
            title: Text(
              '${side == OrderSide.buy ? 'Buy' : 'Sell'} ${quote.symbol}',
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${quote.name} · ${orderType.name.toUpperCase()} order',
                    ),
                    const SizedBox(height: 20),
                    SegmentedButton<EntryOrderType>(
                      showSelectedIcon: false,
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
                          prefixText: '${_currencyPrefix(quote.symbol)} ',
                        ),
                        onChanged: (value) => orderPrice = value,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(leveragedAsset ? 'Lots' : 'Lots', style: Theme.of(context).textTheme.labelLarge),
                    if (leveragedAsset)
                      Wrap(
                        spacing: 8,
                        children: [1.0, 0.1, 0.001]
                            .map((value) => ChoiceChip(
                                  label: Text(_lotLabel(value)),
                                  selected: lots == value,
                                  onSelected: (_) => setState(() => lots = value),
                                ))
                            .toList(),
                      )
                    else
                      Row(
                        children: [
                          IconButton(
                            onPressed: lots > 1
                                ? () => setState(() => lots--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '${_lotLabel(lots)} lot${lots == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          IconButton(
                            onPressed: () => setState(() => lots++),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    if (leveragedAsset) ...[
                      const SizedBox(height: 14),
                      Text('Leverage', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 1, label: Text('1×')),
                          ButtonSegment(value: 10, label: Text('10×')),
                          ButtonSegment(value: 20, label: Text('20×')),
                          ButtonSegment(value: 50, label: Text('50×')),
                          ButtonSegment(value: 100, label: Text('100×')),
                        ],
                        selected: {leverage},
                        onSelectionChanged: (selection) =>
                            setState(() => leverage = selection.first),
                      ),
                    ],
                    Text(
                      'Quantity: ${_lotLabel(lots * quote.lotSize)} · Lot size: ${quote.lotSize}',
                    ),
                    const SizedBox(height: 8),
                    Text('Estimated fill: ${_money(effectivePrice, quote.symbol)}'),
                    Text(
                      'Estimated market value: ${_money(notional, quote.symbol)}',
                    ),
                    if (leveragedAsset)
                      Text('Estimated funds used ($leverage×): ${_money(fundsUsed, quote.symbol)}'),
                    Text('Available cash: ${_money(availableCash)}'),
                    if (insufficientFunds)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Insufficient virtual funds', style: TextStyle(color: Colors.redAccent)),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Target price (optional)',
                        prefixText: '${_currencyPrefix(quote.symbol)} ',
                      ),
                      onChanged: (value) => target = value,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Stop-loss price (optional)',
                        prefixText: '${_currencyPrefix(quote.symbol)} ',
                      ),
                      onChanged: (value) => stopLoss = value,
                    ),
                  ],
                ),
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
                onPressed: insufficientFunds
                    ? null
                    : () async {
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
                        leverage: leveragedAsset ? leverage : 1,
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
              Text(
                'Entry ${_money(position.averagePrice, position.symbol)} · ${position.side}',
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: target,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Target price',
                  prefixText: '${_currencyPrefix(position.symbol)} ',
                ),
                onChanged: (value) => target = value,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: stopLoss,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Stop-loss price',
                  prefixText: '${_currencyPrefix(position.symbol)} ',
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
          '${_money(position.netPnl, position.symbol)}.',
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

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.name,
    required this.photo,
    required this.onProfile,
  });
  final String name;
  final MemoryImage? photo;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hi, $name! 👋',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              'Ready to conquer the markets?',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      InkWell(
        onTap: onProfile,
        borderRadius: BorderRadius.circular(24),
        child: CircleAvatar(
          radius: 21,
          backgroundImage: photo,
          child: photo == null ? Text(name.substring(0, 1).toUpperCase()) : null,
        ),
      ),
    ],
  );
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const actions = [
      (Icons.star_outline, 'Watchlist', '/watchlist'),
      (Icons.query_stats_outlined, 'Markets', '/markets'),
      (Icons.account_balance_wallet_outlined, 'Positions', '/positions'),
      (Icons.receipt_long_outlined, 'Orders', '/orders'),
    ];
    return Row(
      children: actions
          .map(
            (action) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: action.$3 == '/orders' ? 0 : 10,
                ),
                child: InkWell(
                  onTap: () => context.push(action.$3),
                  borderRadius: BorderRadius.circular(14),
                  child: Ink(
                    height: 72,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(action.$1, size: 21),
                        const SizedBox(height: 6),
                        Text(
                          action.$2,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _PerformanceSnapshot extends StatelessWidget {
  const _PerformanceSnapshot({required this.totalPnl, required this.orders});
  final double totalPnl;
  final List<TradeOrder> orders;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionTitle(
        title: 'Your Performance',
        action: 'View all',
        onTap: () => context.push('/analytics'),
      ),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Portfolio P&L',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                _money(totalPnl),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: totalPnl >= 0 ? Colors.greenAccent : Colors.redAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 62,
                child: _PnlSparkline(values: _performancePoints(orders, totalPnl)),
              ),
              const SizedBox(height: 8),
              Text(
                orders.where((order) => order.status == 'CLOSED').isEmpty
                    ? 'Current mark-to-market P&L. Complete trades to build a history.'
                    : 'Cumulative realized P&L, ending with current portfolio P&L.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _PnlSparkline extends StatelessWidget {
  const _PnlSparkline({required this.values});
  final List<double> values;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SparklinePainter(
      color: values.last >= 0 ? Colors.greenAccent : Colors.redAccent,
      values: values,
    ),
    child: const SizedBox.expand(),
  );
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.color, required this.values});
  final Color color;
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs().clamp(1, double.infinity);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        size.width * i / (values.length - 1),
        size.height - ((values[i] - min) / range * (size.height - 8)) - 4,
      );
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.values != values;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.action,
    required this.onTap,
  });
  final String title;
  final String action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      TextButton(onPressed: onTap, child: Text('$action →')),
    ],
  );
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
            leading: CircleAvatar(
              child: Icon(_instrumentIcon(quote.instrumentType), size: 18),
            ),
            title: Text(quote.symbol),
            subtitle: Text('${quote.name} · ${_currencyCode(quote.symbol)}'),
            trailing: TextButton.icon(
              onPressed: () => onAdd(quote),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Watch'),
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
    final currentPnl = portfolio?.unrealizedPnl ?? 0;
    final totalPnl = portfolio?.totalPnl ?? 0;
    if (MediaQuery.sizeOf(context).width < 700) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Portfolio',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text(
                    '${portfolio?.positions.length ?? 0} open',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account equity',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _money(portfolio?.equity ?? 0),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _PnlSummary(
                          label: 'Usable funds',
                          value: portfolio?.cashBalance ?? 0,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PnlSummary(label: 'Current P&L', value: currentPnl),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final metrics = [
      ('Account equity', _money(portfolio?.equity ?? 0)),
      ('Usable funds', _money(portfolio?.cashBalance ?? 0)),
      ('Current P&L', _money(currentPnl)),
      ('Total P&L', _money(totalPnl)),
      ('Open positions', '${portfolio?.positions.length ?? 0}'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100 ? 5 : 2;
        final width = (constraints.maxWidth - (12 * (columns - 1))) / columns;
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

class _PnlSummary extends StatelessWidget {
  const _PnlSummary({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final color = value >= 0
        ? Colors.tealAccent.shade400
        : Colors.redAccent.shade100;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            _money(value),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
        ],
      ),
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 620;
      final identity = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(quote.symbol, style: Theme.of(context).textTheme.titleMedium),
          Text(quote.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      );
      final price = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _money(quote.ltp, quote.symbol),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '${quote.changePercent >= 0 ? '+' : ''}${quote.changePercent.toStringAsFixed(2)}%',
            style: TextStyle(
              color: quote.changePercent >= 0
                  ? Colors.tealAccent
                  : Colors.redAccent,
            ),
          ),
        ],
      );
      final actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
      );
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: compact
              ? Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: 8),
                        price,
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    price,
                    const SizedBox(width: 16),
                    actions,
                  ],
                ),
        ),
      );
    },
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
    if (MediaQuery.sizeOf(context).width < 700) {
      return Column(
        children: positions
            .map(
              (position) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              position.symbol,
                              style: Theme.of(context).textTheme.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            position.side,
                            style: TextStyle(
                              color: position.side == 'BUY'
                                  ? Colors.tealAccent
                                  : Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _MobileFields(
                        fields: [
                          ('Qty', '${position.quantity}'),
                          (
                            'Average',
                            _money(position.averagePrice, position.symbol),
                          ),
                          ('LTP', _money(position.ltp, position.symbol)),
                          (
                            'Current P&L',
                            _money(position.netPnl, position.symbol),
                          ),
                          (
                            'Target',
                            _optionalMoney(
                              position.targetPrice,
                              position.symbol,
                            ),
                          ),
                          (
                            'Stop-loss',
                            _optionalMoney(position.stopLoss, position.symbol),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Market data: ${_marketTime(position.timestamp)}\nApp refreshed: ${_clock(checkedAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () => onEdit(position),
                            icon: const Icon(Icons.edit_note),
                            label: const Text('Edit'),
                          ),
                          TextButton.icon(
                            onPressed: () => onClose(position),
                            icon: const Icon(Icons.exit_to_app),
                            label: const Text('Exit'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Refresh LTP and P&L',
                            onPressed: () => onRefresh(position),
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
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
            DataColumn(label: Text('Market data / refresh')),
            DataColumn(label: Text('Actions')),
          ],
          rows: positions
              .map(
                (position) => DataRow(
                  cells: [
                    DataCell(Text(position.symbol)),
                    DataCell(Text(position.side)),
                    DataCell(Text('${position.quantity}')),
                    DataCell(
                      Text(_money(position.averagePrice, position.symbol)),
                    ),
                    DataCell(Text(_money(position.ltp, position.symbol))),
                    DataCell(
                      Text(
                        _optionalMoney(position.targetPrice, position.symbol),
                      ),
                    ),
                    DataCell(
                      Text(_optionalMoney(position.stopLoss, position.symbol)),
                    ),
                    DataCell(Text(_money(position.netPnl, position.symbol))),
                    DataCell(
                      Text(
                        'Market: ${_marketTime(position.timestamp)}\nApp: ${_clock(checkedAt)}',
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
    if (MediaQuery.sizeOf(context).width < 700) {
      return Column(
        children: pending
            .map(
              (order) => Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  title: Text(
                    order.symbol,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${order.side} · ${order.orderType.replaceAll('_', ' ')} · Qty ${order.quantity}\nPrice / trigger ${_money(order.orderPrice, order.symbol)}',
                  ),
                  trailing: TextButton(
                    onPressed: () => onCancel(order.id),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
            )
            .toList(),
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
                    DataCell(Text(_money(order.orderPrice, order.symbol))),
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

class _MobileFields extends StatelessWidget {
  const _MobileFields({required this.fields});
  final List<(String, String)> fields;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 8,
      runSpacing: 12,
      children: fields
          .map(
            (field) => SizedBox(
              width: (constraints.maxWidth - 8) / 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(field.$1, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Text(field.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          )
          .toList(),
    ),
  );
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
    if (MediaQuery.sizeOf(context).width < 700) {
      return Column(
        children: orders
            .map(
              (order) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              order.symbol,
                              style: Theme.of(context).textTheme.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(order.exitReason ?? order.status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _MobileFields(
                        fields: [
                          ('Side / Qty', '${order.side} / ${order.quantity}'),
                          ('Entry', _money(order.entryPrice, order.symbol)),
                          (
                            'Exit',
                            _optionalMoney(order.exitPrice, order.symbol),
                          ),
                          ('P&L', _money(order.pnl, order.symbol)),
                          (
                            'Target',
                            _optionalMoney(order.targetPrice, order.symbol),
                          ),
                          (
                            'Stop-loss',
                            _optionalMoney(order.stopLoss, order.symbol),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        order.createdAt.toLocal().toString().substring(0, 16),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
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
                    DataCell(Text(_money(order.entryPrice, order.symbol))),
                    DataCell(
                      Text(_optionalMoney(order.targetPrice, order.symbol)),
                    ),
                    DataCell(
                      Text(_optionalMoney(order.stopLoss, order.symbol)),
                    ),
                    DataCell(
                      Text(_optionalMoney(order.exitPrice, order.symbol)),
                    ),
                    DataCell(Text(order.exitReason ?? order.status)),
                    DataCell(Text(_money(order.pnl, order.symbol))),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

bool _usesUsd(String? symbol) =>
    symbol?.toUpperCase() == 'BTCUSD' || symbol?.toUpperCase() == 'XAUUSD';

String _currencyPrefix(String? symbol) => _usesUsd(symbol) ? r'$' : '₹';
String _currencyCode(String? symbol) => _usesUsd(symbol) ? 'USD' : 'INR';
String _money(num value, [String? symbol]) =>
    '${_currencyPrefix(symbol)}${value.toStringAsFixed(2)}';
String _optionalMoney(num? value, [String? symbol]) =>
    value == null ? '—' : _money(value, symbol);
String _lotLabel(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
IconData _instrumentIcon(String type) => switch (type) {
  'CRYPTO' => Icons.currency_bitcoin_rounded,
  'METAL' => Icons.workspace_premium_outlined,
  'OPTION' => Icons.candlestick_chart_rounded,
  'EQUITY' => Icons.business_center_outlined,
  _ => Icons.show_chart_rounded,
};
String _clock(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _marketTime(String value) => value.trim().isEmpty ? 'not supplied' : value;

MemoryImage? _profilePhoto(String? encoded) {
  if (encoded == null || encoded.isEmpty) return null;
  try {
    return MemoryImage(base64Decode(encoded));
  } on FormatException {
    return null;
  }
}

List<double> _performancePoints(List<TradeOrder> orders, double currentPnl) {
  final closed = orders.where((order) => order.status == 'CLOSED').toList()
    ..sort((a, b) => (a.closedAt ?? a.createdAt).compareTo(b.closedAt ?? b.createdAt));
  var cumulative = 0.0;
  final points = <double>[0];
  for (final trade in closed) {
    cumulative += trade.pnl;
    points.add(cumulative);
  }
  if (points.length == 1 || points.last != currentPnl) points.add(currentPnl);
  return points;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/primary_footer.dart';

import '../../trading/domain/trading_models.dart';
import '../../trading/presentation/trading_controller.dart';

class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});
  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  var _searching = false;
  var _sort = 'Default';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tradingControllerProvider);
    final controller = ref.read(tradingControllerProvider.notifier);
    var quotes = [...(state.snapshot?.quotes ?? const <Quote>[])];
    if (_sort == 'Price') quotes.sort((a, b) => b.ltp.compareTo(a.ltp));
    if (_sort == '% Change')
      quotes.sort((a, b) => b.changePercent.compareTo(a.changePercent));
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search stocks, indices...',
                ),
                onChanged: controller.search,
              )
            : const Text('Watchlist'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) controller.search('');
            }),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => setState(() => _searching = true),
          ),
        ],
      ),
      bottomNavigationBar: const PrimaryFooter(selectedIndex: 0),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Chip(label: Text('My Watchlist')),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${quotes.length} instruments',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const Spacer(),
                DropdownButton<String>(
                  value: _sort,
                  items: const ['Default', '% Change', 'Price']
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('Sort: $value'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _sort = value!),
                ),
              ],
            ),
            if (_searching && state.searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Search results',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              ...state.searchResults.map(
                (quote) => InstrumentRow(
                  quote: quote,
                  favorite: false,
                  onFavorite: () async {
                    await controller.addToWatchlist(quote);
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${quote.symbol} added to watchlist'),
                        ),
                      );
                  },
                ),
              ),
              const Divider(height: 28),
            ],
            if (quotes.isEmpty && !_searching)
              _EmptyWatchlist(onAdd: () => setState(() => _searching = true))
            else
              ...quotes.map(
                (quote) => Dismissible(
                  key: ValueKey(quote.symbol),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Theme.of(context).colorScheme.error,
                    child: const Icon(Icons.delete_outline),
                  ),
                  onDismissed: (_) =>
                      controller.removeFromWatchlist(quote.symbol),
                  child: InstrumentRow(
                    quote: quote,
                    favorite: true,
                    onFavorite: () =>
                        controller.removeFromWatchlist(quote.symbol),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MarketsScreen extends ConsumerWidget {
  const MarketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(tradingControllerProvider).snapshot;
    final quotes = snapshot?.quotes ?? const <Quote>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Markets')),
      bottomNavigationBar: const PrimaryFooter(selectedIndex: 0),
      body: RefreshIndicator(
        onRefresh: () => ref.read(tradingControllerProvider.notifier).refresh(),
        child: quotes.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: Text('No live market instruments are available.')),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Live instruments',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pull down to refresh current prices.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  ...quotes.map(
                    (quote) => InstrumentRow(
                      quote: quote,
                      favorite: false,
                      onFavorite: () => ref
                          .read(tradingControllerProvider.notifier)
                          .addToWatchlist(quote),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class StockDetailScreen extends ConsumerWidget {
  const StockDetailScreen({super.key, required this.symbol});
  final String symbol;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quote = ref
        .watch(tradingControllerProvider)
        .snapshot
        ?.quotes
        .where((item) => item.symbol == symbol)
        .firstOrNull;
    if (quote == null)
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Live quote for $symbol is unavailable.')),
      );
    final positive = quote.changePercent >= 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(quote.symbol),
        actions: [
          IconButton(
            icon: const Icon(Icons.star_border),
            onPressed: () => ref
                .read(tradingControllerProvider.notifier)
                .addToWatchlist(quote),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: () => _trade(context, ref, quote, OrderSide.sell),
                child: const Text('Sell'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => _trade(context, ref, quote, OrderSide.buy),
                child: const Text('Buy'),
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(quote.name, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text(
            _price(quote.ltp, quote.symbol),
            style: Theme.of(
              context,
            ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            '${positive ? '+' : ''}${quote.changePercent.toStringAsFixed(2)}%',
            style: TextStyle(
              color: positive ? Colors.greenAccent : Colors.redAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Today\'s Stats',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _StatsGrid(quote: quote),
          const SizedBox(height: 18),
          Text(
            'About',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text('${quote.name} · ${quote.instrumentType} · Live market data'),
        ],
      ),
    );
  }

  Future<void> _trade(
    BuildContext context,
    WidgetRef ref,
    Quote quote,
    OrderSide side,
  ) async => context.push(
    '/trade/${Uri.encodeComponent(quote.symbol)}?side=${side == OrderSide.buy ? 'BUY' : 'SELL'}',
  );
}

class InstrumentRow extends StatelessWidget {
  const InstrumentRow({
    super.key,
    required this.quote,
    required this.favorite,
    required this.onFavorite,
  });
  final Quote quote;
  final bool favorite;
  final VoidCallback onFavorite;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.push('/stock/${Uri.encodeComponent(quote.symbol)}'),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            child: Text(
              quote.symbol.length > 1
                  ? quote.symbol.substring(0, 2)
                  : quote.symbol,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quote.symbol,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  quote.instrumentType == 'CRYPTO' ? 'CRYPTO' : 'NSE',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _price(quote.ltp, quote.symbol),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${quote.changePercent >= 0 ? '+' : ''}${quote.changePercent.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: quote.changePercent >= 0
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: onFavorite,
            icon: Icon(
              favorite ? Icons.star : Icons.star_border,
              color: favorite ? Colors.amber : null,
            ),
          ),
        ],
      ),
    ),
  );
}

/* class _MarketBanner extends StatelessWidget {
  const _MarketBanner({
    required this.underlying,
    required this.isLive,
    required this.source,
  });
  final double underlying;
  final bool isLive;
  final String source;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            color: isLive ? Colors.greenAccent : Colors.orangeAccent,
            size: 10,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: source.isEmpty ? 'NSE market-data status' : source,
              child: Text(
                isLive ? 'Market Open' : 'Market Closed · Last available data',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            underlying > 0 ? 'NIFTY 50  ${_price(underlying, '')}' : 'NIFTY unavailable',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

/// A compact, truthful quote-range visual: bid → last traded price → ask.
/// It is intentionally not presented as historical price data.
class _QuoteRangeGraph extends StatelessWidget {
  const _QuoteRangeGraph({required this.quote});
  final Quote quote;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Current quote range. Bid ${_price(quote.bid, quote.symbol)}, last ${_price(quote.ltp, quote.symbol)}, ask ${_price(quote.ask, quote.symbol)}.',
    child: SizedBox(
      width: 54,
      height: 30,
      child: CustomPaint(
        painter: _QuoteRangePainter(
          values: [quote.bid, quote.ltp, quote.ask],
          color: quote.changePercent >= 0
              ? Colors.greenAccent
              : Colors.redAccent,
        ),
      ),
    ),
  );
}

class _QuoteRangePainter extends CustomPainter {
  const _QuoteRangePainter({required this.values, required this.color});
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs().clamp(.01, double.infinity);
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      points.add(
        Offset(
          index * size.width / (values.length - 1),
          size.height - 4 - (values[index] - min) / range * (size.height - 8),
        ),
      );
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) path.lineTo(point.dx, point.dy);
    canvas.drawPath(path, paint);
    canvas.drawCircle(points[1], 2.8, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _QuoteRangePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

} */

class _EmptyWatchlist extends StatelessWidget {
  const _EmptyWatchlist({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 52),
    child: Column(
      children: [
        const Icon(Icons.star_outline, size: 44),
        const SizedBox(height: 12),
        Text(
          'Your watchlist is empty',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        const Text(
          'Add stocks you\'re interested in to track their prices.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add Your First Stock'),
        ),
      ],
    ),
  );
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.quote});
  final Quote quote;
  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    childAspectRatio: 3,
    children:
        [
              ('Open', _price(quote.ltp, quote.symbol)),
              ('High', _price(quote.ask, quote.symbol)),
              ('Low', _price(quote.bid, quote.symbol)),
              ('Lot size', '${quote.lotSize}'),
            ]
            .map(
              (item) => Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$1,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      item.$2,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
  );
}

String _price(num value, String symbol) =>
    (symbol == 'BTCUSD' || symbol == 'XAUUSD' ? r'$' : '₹') +
    value.toStringAsFixed(2);

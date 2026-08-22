import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/trading_models.dart';
import 'local_account_store.dart';

final tradingRepositoryProvider = Provider<TradingRepository>(
  (ref) => TradingRepository(ref.watch(apiClientProvider).dio, LocalAccountStore()),
);

/// Market data is fetched from the cloud; account data is stored in Hive only.
class TradingRepository {
  TradingRepository(this._dio, this._store);
  final Dio _dio;
  final LocalAccountStore _store;

  Future<TradingSnapshot> snapshot() async {
    await _refreshSavedExternalQuotes();
    final market = await _marketSnapshot();
    await _processLocalOrders(market);
    return _store.buildSnapshot(market);
  }

  Future<List<Quote>> search(String query) async {
    try {
      final response = await _dio.get<List<dynamic>>('/market/search', queryParameters: {'q': query});
      return response.data!
          .map((item) => Quote.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } on DioException {
      final needle = query.trim().toUpperCase();
      final cached = <Quote>[
        ...((_store.marketCache?['quotes'] as List<dynamic>?) ?? const [])
            .map((item) => Quote.fromJson(Map<String, dynamic>.from(item as Map))),
        ..._store.watchlist.map(Quote.fromJson),
      ];
      final unique = <String, Quote>{};
      for (final quote in cached) {
        if (quote.symbol.contains(needle) || quote.name.toUpperCase().contains(needle)) {
          unique[quote.symbol] = quote;
        }
      }
      return unique.values.toList();
    }
  }

  Future<void> addToWatchlist(String symbol) async {
    final quote = await _quote(symbol);
    final list = _store.watchlist;
    if (list.every((item) => item['symbol'] != quote.symbol)) {
      list.add(_quoteJson(quote));
      await _store.saveWatchlist(list);
    }
  }

  Future<void> removeFromWatchlist(String symbol) async =>
      _store.saveWatchlist(_store.watchlist.where((item) => item['symbol'] != symbol).toList());

  Future<void> placeOrder({
    required String symbol, required OrderSide side, required double quantity,
    EntryOrderType orderType = EntryOrderType.market, double? orderPrice,
    double? targetPrice, double? stopLoss, int leverage = 1,
  }) async {
    final quote = await _quote(symbol);
    final entry = side == OrderSide.buy ? quote.ask : quote.bid;
    final price = orderType == EntryOrderType.market ? entry : orderPrice;
    if (price == null || price <= 0) throw StateError('Enter a valid limit or trigger price.');
    if (orderType == EntryOrderType.limit &&
        ((side == OrderSide.buy && price >= entry) ||
            (side == OrderSide.sell && price <= entry))) {
      throw StateError(
        side == OrderSide.buy
            ? 'Buy limit must be below the current ask to remain pending.'
            : 'Sell limit must be above the current bid to remain pending.',
      );
    }
    _validateRisk(side, price, targetPrice, stopLoss);
    final margin = entry * quantity / leverage.clamp(1, 100);
    if (side == OrderSide.buy && orderType == EntryOrderType.market &&
        _store.buildSnapshot(await _marketSnapshot()).portfolio.cashBalance < margin) {
      throw StateError('Insufficient virtual cash.');
    }
    final now = DateTime.now().toIso8601String();
    final base = <String, dynamic>{
      'id': '${DateTime.now().microsecondsSinceEpoch}-${symbol.hashCode}', 'symbol': quote.symbol,
      'side': side == OrderSide.buy ? 'BUY' : 'SELL', 'quantity': quantity, 'leverage': leverage.clamp(1, 100),
      'target_price': targetPrice, 'stop_loss': stopLoss, 'created_at': now, 'quote': _quoteJson(quote),
    };
    if (orderType == EntryOrderType.market) {
      final orders = _store.orders..insert(0, {...base, 'entry_price': entry, 'status': 'OPEN', 'pnl': 0});
      await _store.saveOrders(orders);
    } else {
      final pending = _store.pendingOrders..insert(0, {
        ...base, 'order_type': orderType == EntryOrderType.limit ? 'LIMIT' : 'STOP_LOSS',
        'order_price': price, 'status': 'PENDING',
      });
      await _store.savePendingOrders(pending);
    }
  }

  Future<void> updateRisk({required String orderId, double? targetPrice, double? stopLoss}) async {
    final orders = _store.orders;
    final index = orders.indexWhere((order) => order['id'] == orderId && order['status'] == 'OPEN');
    if (index < 0) throw StateError('Open trade not found.');
    final order = orders[index];
    _validateRisk(order['side'] == 'BUY' ? OrderSide.buy : OrderSide.sell, _number(order['entry_price']), targetPrice, stopLoss);
    orders[index] = {...order, 'target_price': targetPrice, 'stop_loss': stopLoss};
    await _store.saveOrders(orders);
  }

  Future<void> closeTrade(String orderId) async {
    final orders = _store.orders;
    final index = orders.indexWhere((order) => order['id'] == orderId && order['status'] == 'OPEN');
    if (index < 0) throw StateError('Open trade not found.');
    final order = orders[index];
    final quote = await _quote(order['symbol'].toString());
    orders[index] = _closed(order, order['side'] == 'BUY' ? quote.bid : quote.ask, 'MANUAL');
    await _store.saveOrders(orders);
  }

  Future<void> cancelPendingOrder(String orderId) async {
    final pending = _store.pendingOrders;
    final index = pending.indexWhere((order) => order['id'] == orderId && order['status'] == 'PENDING');
    if (index < 0) throw StateError('Pending order not found.');
    pending[index] = {...pending[index], 'status': 'CANCELLED'};
    await _store.savePendingOrders(pending);
  }

  Future<void> updatePendingOrder({
    required String orderId,
    required double quantity,
    required double orderPrice,
    double? targetPrice,
    double? stopLoss,
  }) async {
    if (quantity <= 0 || orderPrice <= 0) {
      throw StateError('Quantity and order price must be greater than zero.');
    }
    final pending = _store.pendingOrders;
    final index = pending.indexWhere(
      (order) => order['id'] == orderId && order['status'] == 'PENDING',
    );
    if (index < 0) throw StateError('Pending order not found.');
    final order = pending[index];
    final side = order['side'] == 'BUY' ? OrderSide.buy : OrderSide.sell;
    _validateRisk(side, orderPrice, targetPrice, stopLoss);
    pending[index] = {
      ...order,
      'quantity': quantity,
      'order_price': orderPrice,
      'target_price': targetPrice,
      'stop_loss': stopLoss,
      'updated_at': DateTime.now().toIso8601String(),
    };
    await _store.savePendingOrders(pending);
  }

  Future<void> reset() => _store.reset();

  Future<Map<String, dynamic>> _marketSnapshot() async {
    try {
      final response = await _dio
          .get<Map<String, dynamic>>('/market/nifty')
          .timeout(const Duration(seconds: 6));
      final market = Map<String, dynamic>.from(response.data!);
      await _store.saveMarketCache(market);
      return market;
    } catch (_) {
      final cached = _store.marketCache;
      if (cached != null) return cached;
      // The first launch can still show saved instruments while NSE is down.
      return {
        'quotes': const <dynamic>[],
        'underlying': 0,
        'expiry': '',
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  Future<Quote> _quote(String symbol) async {
    final normalized = symbol.toUpperCase().replaceAll('-', '');
    if (normalized == 'BTCUSD' || normalized == 'XAUUSD' || normalized == 'XUDUSD') {
      final response = await _dio.get<Map<String, dynamic>>(
        '/market/quote',
        queryParameters: {'symbol': normalized == 'XUDUSD' ? 'XAUUSD' : normalized},
      );
      return Quote.fromJson(Map<String, dynamic>.from(response.data!));
    }
    final market = await _marketSnapshot();
    final option = _findQuote(market, symbol);
    if (option != null) return option;
    final response = await _dio.get<Map<String, dynamic>>('/market/quote', queryParameters: {'symbol': symbol});
    return Quote.fromJson(Map<String, dynamic>.from(response.data!));
  }

  Future<void> _refreshSavedExternalQuotes() async {
    final saved = <Map>[
      ..._store.watchlist.where((item) => _usesQuoteEndpoint(item['instrument_type'])),
      ..._store.orders
          .where((item) => item['quote'] is Map && _usesQuoteEndpoint((item['quote'] as Map)['instrument_type']))
          .map((item) => item['quote'] as Map),
      ..._store.pendingOrders
          .where((item) => item['quote'] is Map && _usesQuoteEndpoint((item['quote'] as Map)['instrument_type']))
          .map((item) => item['quote'] as Map),
    ];
    if (saved.isEmpty) return;
    final latest = <String, Map<String, dynamic>>{};
    for (final item in saved) {
      final symbol = item['symbol'].toString();
      try {
        final response = await _dio.get<Map<String, dynamic>>('/market/quote', queryParameters: {'symbol': symbol});
        latest[symbol] = Map<String, dynamic>.from(response.data!);
      } on DioException {
        // A saved quote remains visible if NSE temporarily rejects a request.
      }
    }
    if (latest.isEmpty) return;
    final watchlist = _store.watchlist.map((item) => latest[item['symbol']] ?? item).toList();
    final orders = _store.orders.map((item) => latest[item['symbol']] == null
        ? item : {...item, 'quote': latest[item['symbol']]}).toList();
    final pending = _store.pendingOrders.map((item) => latest[item['symbol']] == null
        ? item : {...item, 'quote': latest[item['symbol']]}).toList();
    await _store.saveWatchlist(watchlist);
    await _store.saveOrders(orders);
    await _store.savePendingOrders(pending);
  }

  Quote? _findQuote(Map<String, dynamic> market, String symbol) {
    for (final item in (market['quotes'] as List<dynamic>? ?? const [])) {
      final quote = Quote.fromJson(Map<String, dynamic>.from(item as Map));
      if (quote.symbol == symbol) return quote;
    }
    return null;
  }

  Future<void> _processLocalOrders(Map<String, dynamic> market) async {
    var orders = _store.orders;
    final pending = _store.pendingOrders;
    var changed = false;
    final now = DateTime.now().toIso8601String();
    for (var i = 0; i < pending.length; i++) {
      final item = pending[i];
      if (item['status'] != 'PENDING') continue;
      final quote = _findQuote(market, item['symbol'].toString()) ?? Quote.fromJson(Map<String, dynamic>.from(item['quote'] as Map));
      final execution = item['side'] == 'BUY' ? quote.ask : quote.bid;
      final buy = item['side'] == 'BUY';
      final limit = item['order_type'] == 'LIMIT';
      final trigger = _number(item['order_price']);
      final filled = limit ? (buy ? execution <= trigger : execution >= trigger) : (buy ? execution >= trigger : execution <= trigger);
      if (!filled) continue;
      final quantity = _number(item['quantity']);
      final leverage = _number(item['leverage'] ?? 1).clamp(1, 100);
      if (buy && _store.buildSnapshot(market).portfolio.cashBalance < execution * quantity / leverage) continue;
      orders = [{...item, 'id': '${DateTime.now().microsecondsSinceEpoch}-${item['symbol'].hashCode}', 'entry_price': execution, 'status': 'OPEN', 'pnl': 0, 'created_at': now}, ...orders];
      pending[i] = {...item, 'status': 'FILLED'};
      changed = true;
    }
    for (var i = 0; i < orders.length; i++) {
      final item = orders[i];
      if (item['status'] != 'OPEN') continue;
      final quote = _findQuote(market, item['symbol'].toString()) ?? Quote.fromJson(Map<String, dynamic>.from(item['quote'] as Map));
      final buy = item['side'] == 'BUY';
      // Use the actual close-side price, rather than a display-only LTP.
      final execution = buy ? quote.bid : quote.ask;
      final target = _nullable(item['target_price']);
      final stop = _nullable(item['stop_loss']);
      final targetHit = target != null && (buy ? execution >= target : execution <= target);
      final stopHit = stop != null && (buy ? execution <= stop : execution >= stop);
      if (targetHit || stopHit) {
        orders[i] = _closed(item, execution, targetHit ? 'TARGET' : 'STOP_LOSS');
        changed = true;
      }
    }
    if (changed) { await _store.saveOrders(orders); await _store.savePendingOrders(pending); }
  }

  Map<String, dynamic> _closed(Map<String, dynamic> order, double exit, String reason) {
    final pnl = (exit - _number(order['entry_price'])) * _number(order['quantity']) * (order['side'] == 'BUY' ? 1 : -1);
    return {...order, 'status': 'CLOSED', 'exit_price': exit, 'exit_reason': reason, 'pnl': pnl, 'closed_at': DateTime.now().toIso8601String()};
  }

  void _validateRisk(OrderSide side, double reference, double? target, double? stop) {
    if (target != null && (side == OrderSide.buy ? target <= reference : target >= reference)) throw StateError('Target must be on the profitable side of the entry price.');
    if (stop != null && (side == OrderSide.buy ? stop >= reference : stop <= reference)) throw StateError('Stop-loss must be on the losing side of the entry price.');
  }

  Map<String, dynamic> _quoteJson(Quote quote) => {'symbol': quote.symbol, 'name': quote.name, 'instrument_type': quote.instrumentType, 'lot_size': quote.lotSize, 'ltp': quote.ltp, 'bid': quote.bid, 'ask': quote.ask, 'change_percent': quote.changePercent, 'expiry': quote.expiry, 'strike': quote.strike, 'option_type': quote.optionType, 'timestamp': quote.timestamp, 'source': quote.source};
  static double _number(dynamic value) => double.parse(value.toString());
  static double? _nullable(dynamic value) => value == null ? null : _number(value);
  static bool _usesQuoteEndpoint(dynamic type) =>
      type == 'EQUITY' || type == 'CRYPTO' || type == 'METAL';
}

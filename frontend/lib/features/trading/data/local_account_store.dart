import 'package:hive_flutter/hive_flutter.dart';

import '../domain/trading_models.dart';

/// Persistent, device-only data for the paper-trading account.
///
/// Keeping this as JSON-compatible maps makes upgrades safe: Hive does not
/// need generated adapters and no portfolio information leaves the device.
class LocalAccountStore {
  static const double initialBalance = 100000;

  Box<dynamic> get _box => Hive.box<dynamic>('foliox_account');
  String get _accountId => Hive.box<String>(
    'foliox_settings',
  ).get('active_account_id', defaultValue: 'legacy-device-account')!;
  String _key(String name) => 'account:$_accountId:$name';

  List<Map<String, dynamic>> get orders => _maps('orders');
  List<Map<String, dynamic>> get pendingOrders => _maps('pending_orders');
  List<Map<String, dynamic>> get watchlist => _maps('watchlist');
  List<Map<String, dynamic>> get journals => _maps('journals');
  List<Map<String, dynamic>> get setups => _maps('setups');
  Map<String, dynamic>? get riskSettings {
    final raw = _box.get(_key('risk_settings'));
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }
  Map<String, dynamic>? get marketCache {
    final raw = _box.get(_key('market_cache'));
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  List<Map<String, dynamic>> _maps(String key) {
    final raw = _box.get(_key(key), defaultValue: <dynamic>[]);
    return (raw as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> saveOrders(List<Map<String, dynamic>> value) =>
      _box.put(_key('orders'), value);
  Future<void> savePendingOrders(List<Map<String, dynamic>> value) =>
      _box.put(_key('pending_orders'), value);
  Future<void> saveWatchlist(List<Map<String, dynamic>> value) =>
      _box.put(_key('watchlist'), value);
  Future<void> saveJournals(List<Map<String, dynamic>> value) => _box.put(_key('journals'), value);
  Future<void> saveSetups(List<Map<String, dynamic>> value) => _box.put(_key('setups'), value);
  Future<void> saveRiskSettings(Map<String, dynamic> value) => _box.put(_key('risk_settings'), value);
  Future<void> saveMarketCache(Map<String, dynamic> value) =>
      _box.put(_key('market_cache'), value);

  /// Reset only the currently signed-in paper account, never another local user.
  Future<void> reset() async {
    await Future.wait([
      _box.delete(_key('orders')),
      _box.delete(_key('pending_orders')),
      _box.delete(_key('journals')),
    ]);
  }

  TradingSnapshot buildSnapshot(Map<String, dynamic> market) {
    final marketQuotes = ((market['quotes'] as List<dynamic>?) ?? const [])
        .map((item) => Quote.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final quoteBySymbol = {
      for (final quote in marketQuotes) quote.symbol: quote,
    };
    final selected = <Quote>[];
    for (final saved in watchlist) {
      final symbol = saved['symbol'].toString();
      final live = quoteBySymbol[symbol];
      selected.add(live ?? Quote.fromJson(saved));
    }
    for (final open in orders.where((item) => item['status'] == 'OPEN')) {
      final symbol = open['symbol'].toString();
      final live = quoteBySymbol[symbol];
      if (live != null && selected.every((quote) => quote.symbol != symbol)) {
        selected.add(live);
      }
    }
    final quotes = {for (final quote in selected) quote.symbol: quote};
    final openOrders = orders
        .where((item) => item['status'] == 'OPEN')
        .toList();
    final positions = openOrders.map((order) {
      final quote =
          quotes[order['symbol']] ??
          Quote.fromJson(order['quote'] as Map<String, dynamic>);
      final side = order['side'].toString();
      final entry = _number(order['entry_price']);
      final qty = _number(order['quantity']);
      final pnl = (quote.ltp - entry) * qty * (side == 'BUY' ? 1 : -1);
      return Position(
        symbol: order['symbol'].toString(),
        quantity: qty,
        averagePrice: entry,
        ltp: quote.ltp,
        realizedPnl: 0,
        unrealizedPnl: pnl,
        netPnl: pnl,
        side: side,
        targetPrice: _nullable(order['target_price']),
        stopLoss: _nullable(order['stop_loss']),
        orderId: order['id'].toString(),
        timestamp: quote.timestamp.isNotEmpty
            ? quote.timestamp
            : market['timestamp']?.toString() ?? '',
        source: quote.source.isNotEmpty
            ? quote.source
            : market['source']?.toString() ?? '',
      );
    }).toList();
    final completed = orders.where((item) => item['status'] == 'CLOSED');
    final realized = completed.fold<double>(
      0,
      (sum, item) => sum + _number(item['pnl']),
    );
    final unrealized = positions.fold<double>(
      0,
      (sum, item) => sum + item.unrealizedPnl,
    );
    final cash = _cashBalance(orders);
    return TradingSnapshot(
      quotes: selected,
      portfolio: Portfolio(
        cashBalance: cash,
        equity: initialBalance + realized + unrealized,
        realizedPnl: realized,
        unrealizedPnl: unrealized,
        totalPnl: realized + unrealized,
        positions: positions,
      ),
      orders: orders.map(TradeOrder.fromJson).toList(),
      pendingOrders: pendingOrders.map(PendingOrder.fromJson).toList(),
      marketIsLive: market['is_live'] == true,
      marketSource: market['source']?.toString() ?? '',
      underlying: _number(market['underlying'] ?? 0),
      expiry: market['expiry']?.toString() ?? '',
      timestamp: market['timestamp']?.toString() ?? '',
      refreshedAt: DateTime.now(),
    );
  }

  double _cashBalance(Iterable<Map<String, dynamic>> allOrders) =>
      allOrders.fold<double>(initialBalance, (cash, order) {
        final qty = _number(order['quantity']);
        final entry = _number(order['entry_price']);
        final side = order['side'].toString();
        final leverage = _number(order['leverage'] ?? 1).clamp(1, 100).toDouble();
        final margin = entry * qty / leverage;
        // A position locks its margin on entry; on close that margin and its P&L
        // return to cash. This also keeps a short sale from inflating cash.
        final entryCash = -margin;
        final exit = _nullable(order['exit_price']);
        final pnl = exit == null ? 0 : (exit - entry) * qty * (side == 'BUY' ? 1 : -1);
        final exitCash = exit == null ? 0 : margin + pnl;
        return cash + entryCash + exitCash;
      });

  static double _number(dynamic value) => double.parse(value.toString());
  static double? _nullable(dynamic value) =>
      value == null ? null : _number(value);
}

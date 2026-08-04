import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/trading_models.dart';

final tradingRepositoryProvider = Provider<TradingRepository>(
  (ref) => TradingRepository(ref.watch(apiClientProvider).dio),
);

class TradingRepository {
  TradingRepository(this._dio);

  final Dio _dio;
  bool _useSimulation = false;
  double _cash = 1000000;
  final Map<String, Position> _positions = {};
  late final List<Quote> _simulatedQuotes = _buildNiftyChain();

  Future<TradingSnapshot> snapshot() async {
    if (_useSimulation) return _simulatedSnapshot();
    try {
      final response = await _dio.get<Map<String, dynamic>>('/demo/snapshot');
      return TradingSnapshot.fromJson(response.data!);
    } on DioException {
      _useSimulation = true;
      return _simulatedSnapshot();
    }
  }

  Future<void> placeOrder({
    required String symbol,
    required OrderSide side,
    required int quantity,
  }) async {
    if (_useSimulation) {
      _placeSimulatedOrder(symbol, side, quantity);
      return;
    }
    await _dio.post<Map<String, dynamic>>(
      '/demo/orders',
      data: {
        'symbol': symbol,
        'side': side == OrderSide.buy ? 'BUY' : 'SELL',
        'quantity': quantity,
      },
    );
  }

  Future<void> reset() async {
    if (_useSimulation) {
      _cash = 1000000;
      _positions.clear();
      return;
    }
    await _dio.post<void>('/demo/reset');
  }

  TradingSnapshot _simulatedSnapshot() {
    final positions = _positions.values.where((item) => item.quantity != 0).toList();
    final marketValue = positions.fold<double>(
      0,
      (total, item) => total + item.ltp * item.quantity,
    );
    final unrealized = positions.fold<double>(0, (total, item) => total + item.netPnl);
    final equity = _cash + marketValue;
    return TradingSnapshot(
      quotes: _simulatedQuotes,
      portfolio: Portfolio(
        cashBalance: _cash,
        equity: equity,
        realizedPnl: 0,
        unrealizedPnl: unrealized,
        totalPnl: equity - 1000000,
        positions: positions,
      ),
    );
  }

  void _placeSimulatedOrder(String symbol, OrderSide side, int quantity) {
    final quote = _simulatedQuotes.firstWhere((item) => item.symbol == symbol);
    final signedQuantity = side == OrderSide.buy ? quantity : -quantity;
    final price = side == OrderSide.buy ? quote.ask : quote.bid;
    final old = _positions[symbol];
    final newQuantity = (old?.quantity ?? 0) + signedQuantity;
    final average = old == null || old.quantity == 0 || old.quantity.sign != signedQuantity.sign
        ? price
        : ((old.averagePrice * old.quantity.abs()) + (price * quantity)) /
              (old.quantity.abs() + quantity);
    _cash -= price * signedQuantity;
    _positions[symbol] = Position(
      symbol: symbol,
      quantity: newQuantity,
      averagePrice: average,
      ltp: quote.ltp,
      realizedPnl: 0,
      unrealizedPnl: (quote.ltp - average) * newQuantity,
      netPnl: (quote.ltp - average) * newQuantity,
    );
  }

  static List<Quote> _buildNiftyChain() {
    const spot = 25000.0;
    final quotes = <Quote>[
      const Quote(
        symbol: 'NIFTY',
        name: 'Nifty 50 Index',
        instrumentType: 'INDEX',
        lotSize: 1,
        ltp: spot,
        bid: 24999.9,
        ask: 25000.1,
        changePercent: 0.42,
      ),
    ];
    for (var strike = 24500; strike <= 25500; strike += 100) {
      final distance = (strike - spot).abs();
      final timeValue = (180 - distance * .22).clamp(42, 180).toDouble();
      final call =
          ((spot - strike).clamp(0, double.infinity) + timeValue).toDouble();
      final put =
          ((strike - spot).clamp(0, double.infinity) + timeValue).toDouble();
      for (final contract in [('CE', call), ('PE', put)]) {
        final price = contract.$2;
        quotes.add(
          Quote(
            symbol: 'NIFTY11AUG26$strike${contract.$1}',
            name: 'NIFTY 11 AUG $strike ${contract.$1}',
            instrumentType: 'OPTION',
            lotSize: 65,
            ltp: price,
            bid: price - .05,
            ask: price + .05,
            changePercent: strike == 25000 ? 1.25 : -.35,
          ),
        );
      }
    }
    return quotes;
  }
}

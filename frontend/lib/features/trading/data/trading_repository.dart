import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/trading_models.dart';

final tradingRepositoryProvider = Provider<TradingRepository>(
  (ref) => TradingRepository(ref.watch(apiClientProvider).dio),
);

class TradingRepository {
  const TradingRepository(this._dio);

  final Dio _dio;

  Future<TradingSnapshot> snapshot() async {
    final response = await _dio.get<Map<String, dynamic>>('/trading/snapshot');
    return TradingSnapshot.fromJson(response.data!);
  }

  Future<List<Quote>> search(String query) async {
    final response = await _dio.get<List<dynamic>>(
      '/market/search',
      queryParameters: {'q': query},
    );
    return response.data!
        .map((item) => Quote.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> addToWatchlist(String symbol) =>
      _dio.post<void>('/watchlist', data: {'symbol': symbol});

  Future<void> removeFromWatchlist(String symbol) =>
      _dio.delete<void>('/watchlist/${Uri.encodeComponent(symbol)}');

  Future<void> placeOrder({
    required String symbol,
    required OrderSide side,
    required int quantity,
    EntryOrderType orderType = EntryOrderType.market,
    double? orderPrice,
    double? targetPrice,
    double? stopLoss,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/trading/orders',
      data: {
        'symbol': symbol,
        'side': side == OrderSide.buy ? 'BUY' : 'SELL',
        'quantity': quantity,
        'order_type': switch (orderType) {
          EntryOrderType.market => 'MARKET',
          EntryOrderType.limit => 'LIMIT',
          EntryOrderType.stopLoss => 'STOP_LOSS',
        },
        'order_price': orderPrice,
        'target_price': targetPrice,
        'stop_loss': stopLoss,
      },
    );
  }

  Future<void> reset() => _dio.post<void>('/trading/reset');

  Future<void> updateRisk({
    required String orderId,
    double? targetPrice,
    double? stopLoss,
  }) => _dio.patch<void>(
    '/trading/orders/$orderId',
    data: {'target_price': targetPrice, 'stop_loss': stopLoss},
  );

  Future<void> closeTrade(String orderId) =>
      _dio.post<void>('/trading/orders/$orderId/close');

  Future<void> cancelPendingOrder(String orderId) =>
      _dio.delete<void>('/trading/pending-orders/$orderId');
}

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

  Future<void> placeOrder({
    required String symbol,
    required OrderSide side,
    required int quantity,
    double? targetPrice,
    double? stopLoss,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/trading/orders',
      data: {
        'symbol': symbol,
        'side': side == OrderSide.buy ? 'BUY' : 'SELL',
        'quantity': quantity,
        'target_price': targetPrice,
        'stop_loss': stopLoss,
      },
    );
  }

  Future<void> reset() => _dio.post<void>('/trading/reset');
}

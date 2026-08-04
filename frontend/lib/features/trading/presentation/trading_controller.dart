import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/trading_repository.dart';
import '../domain/trading_models.dart';

final tradingControllerProvider =
    StateNotifierProvider.autoDispose<TradingController, TradingState>((ref) {
      return TradingController(ref.watch(tradingRepositoryProvider));
    });

class TradingState {
  const TradingState({
    this.snapshot,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.message,
    this.query = '',
  });

  final TradingSnapshot? snapshot;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  final String? message;
  final String query;

  List<Quote> get visibleQuotes {
    final all = snapshot?.quotes ?? const <Quote>[];
    final search = query.trim().toUpperCase();
    if (search.isEmpty) return all;
    return all
        .where(
          (quote) =>
              quote.symbol.contains(search) ||
              quote.name.toUpperCase().contains(search),
        )
        .toList();
  }

  TradingState copyWith({
    TradingSnapshot? snapshot,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    String? message,
    String? query,
    bool clearFeedback = false,
  }) => TradingState(
    snapshot: snapshot ?? this.snapshot,
    isLoading: isLoading ?? this.isLoading,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    error: clearFeedback ? null : error ?? this.error,
    message: clearFeedback ? null : message ?? this.message,
    query: query ?? this.query,
  );
}

class TradingController extends StateNotifier<TradingState> {
  TradingController(this._repository, {bool autoStart = true})
    : super(const TradingState(isLoading: true)) {
    if (autoStart) {
      refresh();
      _timer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => refresh(silent: true),
      );
    }
  }

  final TradingRepository _repository;
  Timer? _timer;
  bool _refreshing = false;

  Future<void> refresh({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent) state = state.copyWith(isLoading: true, clearFeedback: true);
    try {
      final snapshot = await _repository.snapshot();
      state = state.copyWith(snapshot: snapshot, isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: _messageFor(error));
    } finally {
      _refreshing = false;
    }
  }

  void search(String value) => state = state.copyWith(query: value);

  Future<bool> placeOrder(Quote quote, OrderSide side, int lots) async {
    state = state.copyWith(isSubmitting: true, clearFeedback: true);
    try {
      await _repository.placeOrder(
        symbol: quote.symbol,
        side: side,
        quantity: lots * quote.lotSize,
      );
      final snapshot = await _repository.snapshot();
      state = state.copyWith(
        snapshot: snapshot,
        isSubmitting: false,
        message:
            '${side == OrderSide.buy ? 'Bought' : 'Sold'} $lots lot(s) of ${quote.symbol}',
      );
      return true;
    } catch (error) {
      state = state.copyWith(isSubmitting: false, error: _messageFor(error));
      return false;
    }
  }

  Future<void> reset() async {
    await _repository.reset();
    await refresh();
    state = state.copyWith(message: 'Demo account reset');
  }

  static String _messageFor(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['detail'] != null) {
        return data['detail'].toString();
      }
      return 'Cannot reach the trading API. Start FastAPI on port 8000.';
    }
    return error.toString();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

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
    this.searchResults = const [],
    this.isSearching = false,
  });

  final TradingSnapshot? snapshot;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  final String? message;
  final String query;
  final List<Quote> searchResults;
  final bool isSearching;

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
    List<Quote>? searchResults,
    bool? isSearching,
  }) => TradingState(
    snapshot: snapshot ?? this.snapshot,
    isLoading: isLoading ?? this.isLoading,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    error: clearFeedback ? null : error ?? this.error,
    message: clearFeedback ? null : message ?? this.message,
    query: query ?? this.query,
    searchResults: searchResults ?? this.searchResults,
    isSearching: isSearching ?? this.isSearching,
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
  Timer? _searchDebounce;
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

  void search(String value) {
    state = state.copyWith(
      query: value,
      searchResults: value.trim().length < 2 ? const [] : null,
    );
    _searchDebounce?.cancel();
    if (value.trim().length < 2) return;
    _searchDebounce = Timer(const Duration(milliseconds: 450), () async {
      state = state.copyWith(isSearching: true, clearFeedback: true);
      try {
        final results = await _repository.search(value);
        state = state.copyWith(searchResults: results, isSearching: false);
      } catch (error) {
        state = state.copyWith(isSearching: false, error: _messageFor(error));
      }
    });
  }

  Future<void> addToWatchlist(Quote quote) async {
    await _repository.addToWatchlist(quote.symbol);
    state = state.copyWith(query: '', searchResults: const []);
    await refresh(silent: true);
    state = state.copyWith(message: '${quote.symbol} added to watchlist');
  }

  Future<void> removeFromWatchlist(String symbol) async {
    await _repository.removeFromWatchlist(symbol);
    await refresh(silent: true);
    state = state.copyWith(message: '$symbol removed from watchlist');
  }

  Future<bool> updateRisk(
    String orderId, {
    double? targetPrice,
    double? stopLoss,
  }) async {
    state = state.copyWith(isSubmitting: true, clearFeedback: true);
    try {
      await _repository.updateRisk(
        orderId: orderId,
        targetPrice: targetPrice,
        stopLoss: stopLoss,
      );
      await refresh(silent: true);
      state = state.copyWith(
        isSubmitting: false,
        message: 'Target and stop-loss updated',
      );
      return true;
    } catch (error) {
      state = state.copyWith(isSubmitting: false, error: _messageFor(error));
      return false;
    }
  }

  Future<bool> placeOrder(
    Quote quote,
    OrderSide side,
    int lots, {
    double? targetPrice,
    double? stopLoss,
  }) async {
    state = state.copyWith(isSubmitting: true, clearFeedback: true);
    try {
      await _repository.placeOrder(
        symbol: quote.symbol,
        side: side,
        quantity: lots * quote.lotSize,
        targetPrice: targetPrice,
        stopLoss: stopLoss,
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
      return 'Cannot reach live NSE trading service. Please try again.';
    }
    return error.toString();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
    bool clearError = false,
    List<Quote>? searchResults,
    bool? isSearching,
  }) => TradingState(
    snapshot: snapshot ?? this.snapshot,
    isLoading: isLoading ?? this.isLoading,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    error: clearFeedback || clearError ? null : error ?? this.error,
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
  bool _refreshQueued = false;
  WebSocketChannel? _niftyStream;
  StreamSubscription<dynamic>? _niftySubscription;
  Timer? _streamReconnect;
  String? _streamExpiry;
  final Map<String, DateTime> _streamTickTimes = {};

  Future<void> refresh({bool silent = false}) async {
    if (_refreshing) {
      _refreshQueued = true;
      return;
    }
    _refreshing = true;
    if (!silent) state = state.copyWith(isLoading: true, clearFeedback: true);
    try {
      final snapshot = _mergeFreshStreamPrices(await _repository.snapshot());
      state = state.copyWith(
        snapshot: snapshot,
        isLoading: false,
        clearError: true,
      );
      _connectNiftyStream(snapshot.expiry);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: _messageFor(error));
    } finally {
      _refreshing = false;
      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(refresh(silent: true));
      }
    }
  }

  void _connectNiftyStream(String expiry) {
    if (expiry.isEmpty || (_streamExpiry == expiry && _niftyStream != null)) {
      return;
    }
    _closeNiftyStream();
    _streamExpiry = expiry;
    final uri = Uri.https('streamer.nseindia.com', '/streams/fo/mbp', {
      'symbol': 'NIFTY',
      'expiry': expiry,
    }).replace(scheme: 'wss');
    try {
      final channel = WebSocketChannel.connect(uri);
      _niftyStream = channel;
      _niftySubscription = channel.stream.listen(
        _applyNiftyTick,
        onError: (_) => _scheduleStreamReconnect(),
        onDone: _scheduleStreamReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleStreamReconnect();
    }
  }

  void _scheduleStreamReconnect() {
    _niftySubscription?.cancel();
    _niftySubscription = null;
    _niftyStream = null;
    _streamReconnect?.cancel();
    _streamReconnect = Timer(const Duration(seconds: 2), () {
      final expiry = _streamExpiry;
      _streamExpiry = null;
      if (expiry != null) _connectNiftyStream(expiry);
    });
  }

  void _closeNiftyStream() {
    _streamReconnect?.cancel();
    _niftySubscription?.cancel();
    _niftyStream?.sink.close();
    _niftySubscription = null;
    _niftyStream = null;
  }

  void _applyNiftyTick(dynamic rawMessage) {
    final current = state.snapshot;
    if (current == null || rawMessage is! String) return;
    final decoded = jsonDecode(rawMessage);
    if (decoded is! Map<String, dynamic> || decoded['flag'] == 'HEARTBEAT') {
      return;
    }
    final strike = _number(decoded['strikePrice']);
    final tickTimestamp = decoded['timestamp']?.toString() ?? '';
    var changed = false;
    final quotes = current.quotes.map((quote) {
      if (quote.instrumentType != 'OPTION' || quote.strike != strike) {
        return quote;
      }
      final payload = decoded[quote.optionType];
      if (payload is! Map<String, dynamic>) return quote;
      changed = true;
      _streamTickTimes[quote.symbol] = DateTime.now();
      return quote.copyWith(
        ltp: _number(payload['lastPrice']) ?? quote.ltp,
        bid: _number(payload['buyPrice1']) ?? quote.bid,
        ask: _number(payload['sellPrice1']) ?? quote.ask,
        changePercent: _number(payload['pChange']) ?? quote.changePercent,
      );
    }).toList();
    if (!changed) return;
    final quoteMap = {for (final quote in quotes) quote.symbol: quote};
    final positions = current.portfolio.positions.map((position) {
      final quote = quoteMap[position.symbol];
      if (quote == null || !_streamTickTimes.containsKey(position.symbol)) {
        return position;
      }
      final direction = position.side == 'SELL' ? -1 : 1;
      final pnl =
          (quote.ltp - position.averagePrice) * position.quantity * direction;
      return position.copyWith(
        ltp: quote.ltp,
        unrealizedPnl: pnl,
        netPnl: position.realizedPnl + pnl,
        timestamp: tickTimestamp,
      );
    }).toList();
    final unrealized = positions.fold<double>(
      0,
      (total, position) => total + position.unrealizedPnl,
    );
    final portfolio = current.portfolio.copyWith(
      equity:
          current.portfolio.equity +
          (unrealized - current.portfolio.unrealizedPnl),
      unrealizedPnl: unrealized,
      totalPnl: current.portfolio.realizedPnl + unrealized,
      positions: positions,
    );
    state = state.copyWith(
      snapshot: current.copyWith(
        quotes: quotes,
        portfolio: portfolio,
        timestamp: tickTimestamp,
      ),
    );
  }

  TradingSnapshot _mergeFreshStreamPrices(TradingSnapshot incoming) {
    final current = state.snapshot;
    if (current == null) return incoming;
    final now = DateTime.now();
    final currentQuotes = {
      for (final quote in current.quotes) quote.symbol: quote,
    };
    final quotes = incoming.quotes.map((quote) {
      final tickTime = _streamTickTimes[quote.symbol];
      if (tickTime != null &&
          now.difference(tickTime) < const Duration(seconds: 15)) {
        return currentQuotes[quote.symbol] ?? quote;
      }
      return quote;
    }).toList();
    final quoteMap = {for (final quote in quotes) quote.symbol: quote};
    final positions = incoming.portfolio.positions.map((position) {
      final tickTime = _streamTickTimes[position.symbol];
      final quote = quoteMap[position.symbol];
      if (tickTime == null ||
          quote == null ||
          now.difference(tickTime) >= const Duration(seconds: 15)) {
        return position;
      }
      final direction = position.side == 'SELL' ? -1 : 1;
      final pnl =
          (quote.ltp - position.averagePrice) * position.quantity * direction;
      return position.copyWith(
        ltp: quote.ltp,
        unrealizedPnl: pnl,
        netPnl: position.realizedPnl + pnl,
        timestamp: current.timestamp,
      );
    }).toList();
    final unrealized = positions.fold<double>(
      0,
      (total, position) => total + position.unrealizedPnl,
    );
    return incoming.copyWith(
      quotes: quotes,
      portfolio: incoming.portfolio.copyWith(
        equity:
            incoming.portfolio.equity +
            (unrealized - incoming.portfolio.unrealizedPnl),
        unrealizedPnl: unrealized,
        totalPnl: incoming.portfolio.realizedPnl + unrealized,
        positions: positions,
      ),
    );
  }

  static double? _number(dynamic value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
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

  Future<bool> closeTrade(String orderId) async {
    state = state.copyWith(isSubmitting: true, clearFeedback: true);
    try {
      await _repository.closeTrade(orderId);
      await refresh(silent: true);
      state = state.copyWith(
        isSubmitting: false,
        message: 'Trade closed at live market price',
      );
      return true;
    } catch (error) {
      state = state.copyWith(isSubmitting: false, error: _messageFor(error));
      return false;
    }
  }

  Future<void> cancelPendingOrder(String orderId) async {
    try {
      await _repository.cancelPendingOrder(orderId);
      await refresh(silent: true);
      state = state.copyWith(message: 'Pending order cancelled');
    } catch (error) {
      state = state.copyWith(error: _messageFor(error));
    }
  }

  Future<bool> updatePendingOrder(
    String orderId, {
    required double quantity,
    required double orderPrice,
    double? targetPrice,
    double? stopLoss,
  }) async {
    state = state.copyWith(isSubmitting: true, clearFeedback: true);
    try {
      await _repository.updatePendingOrder(
        orderId: orderId,
        quantity: quantity,
        orderPrice: orderPrice,
        targetPrice: targetPrice,
        stopLoss: stopLoss,
      );
      await refresh(silent: true);
      state = state.copyWith(
        isSubmitting: false,
        message: 'Pending order updated',
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
    double lots, {
    EntryOrderType orderType = EntryOrderType.market,
    double? orderPrice,
    double? targetPrice,
    double? stopLoss,
    int leverage = 1,
  }) async {
    state = state.copyWith(isSubmitting: true, clearFeedback: true);
    try {
      await _repository.placeOrder(
        symbol: quote.symbol,
        side: side,
        quantity: lots * quote.lotSize,
        orderType: orderType,
        orderPrice: orderPrice,
        targetPrice: targetPrice,
        stopLoss: stopLoss,
        leverage: leverage,
      );
      final snapshot = await _repository.snapshot();
      state = state.copyWith(
        snapshot: snapshot,
        isSubmitting: false,
        message: orderType == EntryOrderType.market
            ? '${side == OrderSide.buy ? 'Bought' : 'Sold'} ${_lotsLabel(lots)} lot(s) of ${quote.symbol}'
            : '${orderType == EntryOrderType.limit ? 'Limit' : 'Stop-loss'} order placed for ${quote.symbol}',
      );
      return true;
    } catch (error) {
      state = state.copyWith(isSubmitting: false, error: _messageFor(error));
      return false;
    }
  }

  String _lotsLabel(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

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
    _closeNiftyStream();
    super.dispose();
  }
}

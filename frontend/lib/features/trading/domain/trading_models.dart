enum OrderSide { buy, sell }

enum EntryOrderType { market, limit, stopLoss }

class Quote {
  const Quote({
    required this.symbol,
    required this.name,
    required this.instrumentType,
    required this.lotSize,
    required this.ltp,
    required this.bid,
    required this.ask,
    required this.changePercent,
    this.expiry = '',
    this.strike = 0,
    this.optionType = '',
    this.timestamp = '',
    this.source = '',
  });

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
    symbol: json['symbol'] as String,
    name: json['name'] as String,
    instrumentType: json['instrument_type'] as String,
    lotSize: json['lot_size'] as int,
    ltp: _number(json['ltp']),
    bid: _number(json['bid']),
    ask: _number(json['ask']),
    changePercent: _number(json['change_percent']),
    expiry: json['expiry']?.toString() ?? '',
    strike: _number(json['strike'] ?? 0),
    optionType: json['option_type']?.toString() ?? '',
    timestamp: json['timestamp']?.toString() ?? '',
    source: json['source']?.toString() ?? '',
  );

  final String symbol;
  final String name;
  final String instrumentType;
  final int lotSize;
  final double ltp;
  final double bid;
  final double ask;
  final double changePercent;
  final String expiry;
  final double strike;
  final String optionType;
  final String timestamp;
  final String source;

  bool get isTradable => instrumentType != 'INDEX';

  Quote copyWith({
    double? ltp,
    double? bid,
    double? ask,
    double? changePercent,
  }) => Quote(
    symbol: symbol,
    name: name,
    instrumentType: instrumentType,
    lotSize: lotSize,
    ltp: ltp ?? this.ltp,
    bid: bid ?? this.bid,
    ask: ask ?? this.ask,
    changePercent: changePercent ?? this.changePercent,
    expiry: expiry,
    strike: strike,
    optionType: optionType,
    timestamp: timestamp,
    source: source,
  );
}

class Position {
  const Position({
    required this.symbol,
    required this.quantity,
    required this.averagePrice,
    required this.ltp,
    required this.realizedPnl,
    required this.unrealizedPnl,
    required this.netPnl,
    this.side = '',
    this.targetPrice,
    this.stopLoss,
    this.orderId = '',
    this.timestamp = '',
    this.source = '',
  });

  factory Position.fromJson(Map<String, dynamic> json) => Position(
    symbol: json['symbol'] as String,
    quantity: _number(json['quantity']),
    averagePrice: _number(json['average_price']),
    ltp: _number(json['ltp']),
    realizedPnl: _number(json['realized_pnl']),
    unrealizedPnl: _number(json['unrealized_pnl']),
    netPnl: _number(json['net_pnl']),
    side: json['side']?.toString() ?? '',
    targetPrice: _nullableNumber(json['target_price']),
    stopLoss: _nullableNumber(json['stop_loss']),
    orderId: json['order_id']?.toString() ?? '',
    timestamp: json['timestamp']?.toString() ?? '',
    source: json['source']?.toString() ?? '',
  );

  final String symbol;
  final double quantity;
  final double averagePrice;
  final double ltp;
  final double realizedPnl;
  final double unrealizedPnl;
  final double netPnl;
  final String side;
  final double? targetPrice;
  final double? stopLoss;
  final String orderId;
  final String timestamp;
  final String source;

  Position copyWith({
    double? ltp,
    double? unrealizedPnl,
    double? netPnl,
    String? timestamp,
    String? source,
  }) => Position(
    symbol: symbol,
    quantity: quantity,
    averagePrice: averagePrice,
    ltp: ltp ?? this.ltp,
    realizedPnl: realizedPnl,
    unrealizedPnl: unrealizedPnl ?? this.unrealizedPnl,
    netPnl: netPnl ?? this.netPnl,
    side: side,
    targetPrice: targetPrice,
    stopLoss: stopLoss,
    orderId: orderId,
    timestamp: timestamp ?? this.timestamp,
    source: source ?? this.source,
  );
}

class Portfolio {
  const Portfolio({
    required this.cashBalance,
    required this.equity,
    required this.realizedPnl,
    required this.unrealizedPnl,
    required this.totalPnl,
    required this.positions,
  });

  factory Portfolio.fromJson(Map<String, dynamic> json) => Portfolio(
    cashBalance: _number(json['cash_balance']),
    equity: _number(json['equity']),
    realizedPnl: _number(json['realized_pnl']),
    unrealizedPnl: _number(json['unrealized_pnl']),
    totalPnl: _number(json['total_pnl']),
    positions: (json['positions'] as List<dynamic>)
        .map((item) => Position.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  final double cashBalance;
  final double equity;
  final double realizedPnl;
  final double unrealizedPnl;
  final double totalPnl;
  final List<Position> positions;

  Portfolio copyWith({
    double? equity,
    double? unrealizedPnl,
    double? totalPnl,
    List<Position>? positions,
  }) => Portfolio(
    cashBalance: cashBalance,
    equity: equity ?? this.equity,
    realizedPnl: realizedPnl,
    unrealizedPnl: unrealizedPnl ?? this.unrealizedPnl,
    totalPnl: totalPnl ?? this.totalPnl,
    positions: positions ?? this.positions,
  );
}

class TradeOrder {
  const TradeOrder({
    required this.id,
    required this.symbol,
    required this.side,
    required this.quantity,
    required this.entryPrice,
    required this.status,
    required this.pnl,
    required this.createdAt,
    this.leverage = 1,
    this.closedAt,
    this.exitPrice,
    this.exitReason,
    this.targetPrice,
    this.stopLoss,
  });

  factory TradeOrder.fromJson(Map<String, dynamic> json) => TradeOrder(
    id: json['id'].toString(),
    symbol: json['symbol'].toString(),
    side: json['side'].toString(),
    quantity: _number(json['quantity']),
    entryPrice: _number(json['entry_price']),
    exitPrice: _nullableNumber(json['exit_price']),
    targetPrice: _nullableNumber(json['target_price']),
    stopLoss: _nullableNumber(json['stop_loss']),
    status: json['status'].toString(),
    exitReason: json['exit_reason']?.toString(),
    pnl: _number(json['pnl'] ?? 0),
    leverage: int.tryParse(json['leverage']?.toString() ?? '') ?? 1,
    createdAt: DateTime.parse(json['created_at'].toString()),
    closedAt: json['closed_at'] == null
        ? null
        : DateTime.tryParse(json['closed_at'].toString()),
  );

  final String id;
  final String symbol;
  final String side;
  final double quantity;
  final int leverage;
  final double entryPrice;
  final double? exitPrice;
  final double? targetPrice;
  final double? stopLoss;
  final String status;
  final String? exitReason;
  final double pnl;
  final DateTime createdAt;
  final DateTime? closedAt;
}

class PendingOrder {
  const PendingOrder({
    required this.id,
    required this.symbol,
    required this.side,
    required this.quantity,
    required this.orderType,
    required this.orderPrice,
    required this.status,
    required this.createdAt,
    this.leverage = 1,
  });

  factory PendingOrder.fromJson(Map<String, dynamic> json) => PendingOrder(
    id: json['id'].toString(),
    symbol: json['symbol'].toString(),
    side: json['side'].toString(),
    quantity: _number(json['quantity']),
    orderType: json['order_type'].toString(),
    orderPrice: _number(json['order_price']),
    status: json['status'].toString(),
    createdAt: DateTime.parse(json['created_at'].toString()),
    leverage: int.tryParse(json['leverage']?.toString() ?? '') ?? 1,
  );

  final String id;
  final String symbol;
  final String side;
  final double quantity;
  final int leverage;
  final String orderType;
  final double orderPrice;
  final String status;
  final DateTime createdAt;
}

class TradingSnapshot {
  const TradingSnapshot({
    required this.quotes,
    required this.portfolio,
    this.orders = const [],
    this.underlying = 0,
    this.expiry = '',
    this.timestamp = '',
    this.refreshedAt,
    this.pendingOrders = const [],
    this.marketIsLive = false,
    this.marketSource = '',
  });

  factory TradingSnapshot.fromJson(Map<String, dynamic> json) =>
      TradingSnapshot(
        quotes: (json['quotes'] as List<dynamic>)
            .map((item) => Quote.fromJson(item as Map<String, dynamic>))
            .toList(),
        portfolio: Portfolio.fromJson(
          json['portfolio'] as Map<String, dynamic>,
        ),
        orders: (json['orders'] as List<dynamic>? ?? const [])
            .map((item) => TradeOrder.fromJson(item as Map<String, dynamic>))
            .toList(),
        underlying: _number(json['underlying'] ?? 0),
        expiry: json['expiry']?.toString() ?? '',
        timestamp: json['timestamp']?.toString() ?? '',
        refreshedAt: json['refreshed_at'] == null
            ? null
            : DateTime.parse(json['refreshed_at'].toString()),
        pendingOrders: (json['pending_orders'] as List<dynamic>? ?? const [])
            .map((item) => PendingOrder.fromJson(item as Map<String, dynamic>))
            .toList(),
        marketIsLive: json['is_live'] == true,
        marketSource: json['source']?.toString() ?? '',
      );

  final List<Quote> quotes;
  final Portfolio portfolio;
  final List<TradeOrder> orders;
  final double underlying;
  final String expiry;
  final String timestamp;
  final DateTime? refreshedAt;
  final List<PendingOrder> pendingOrders;
  final bool marketIsLive;
  final String marketSource;

  TradingSnapshot copyWith({
    List<Quote>? quotes,
    Portfolio? portfolio,
    String? timestamp,
  }) => TradingSnapshot(
    quotes: quotes ?? this.quotes,
    portfolio: portfolio ?? this.portfolio,
    orders: orders,
    underlying: underlying,
    expiry: expiry,
    timestamp: timestamp ?? this.timestamp,
    refreshedAt: refreshedAt,
    pendingOrders: pendingOrders,
    marketIsLive: marketIsLive,
    marketSource: marketSource,
  );
}

double _number(dynamic value) => double.parse(value.toString());
double? _nullableNumber(dynamic value) =>
    value == null ? null : double.parse(value.toString());

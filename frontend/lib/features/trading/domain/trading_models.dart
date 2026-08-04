enum OrderSide { buy, sell }

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

  bool get isTradable => instrumentType != 'INDEX';
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
  });

  factory Position.fromJson(Map<String, dynamic> json) => Position(
    symbol: json['symbol'] as String,
    quantity: json['quantity'] as int,
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
  );

  final String symbol;
  final int quantity;
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
    this.exitPrice,
    this.exitReason,
    this.targetPrice,
    this.stopLoss,
  });

  factory TradeOrder.fromJson(Map<String, dynamic> json) => TradeOrder(
    id: json['id'].toString(),
    symbol: json['symbol'].toString(),
    side: json['side'].toString(),
    quantity: json['quantity'] as int,
    entryPrice: _number(json['entry_price']),
    exitPrice: _nullableNumber(json['exit_price']),
    targetPrice: _nullableNumber(json['target_price']),
    stopLoss: _nullableNumber(json['stop_loss']),
    status: json['status'].toString(),
    exitReason: json['exit_reason']?.toString(),
    pnl: _number(json['pnl'] ?? 0),
    createdAt: DateTime.parse(json['created_at'].toString()),
  );

  final String id;
  final String symbol;
  final String side;
  final int quantity;
  final double entryPrice;
  final double? exitPrice;
  final double? targetPrice;
  final double? stopLoss;
  final String status;
  final String? exitReason;
  final double pnl;
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
      );

  final List<Quote> quotes;
  final Portfolio portfolio;
  final List<TradeOrder> orders;
  final double underlying;
  final String expiry;
  final String timestamp;
  final DateTime? refreshedAt;
}

double _number(dynamic value) => double.parse(value.toString());
double? _nullableNumber(dynamic value) =>
    value == null ? null : double.parse(value.toString());

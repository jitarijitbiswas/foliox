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
  );

  final String symbol;
  final String name;
  final String instrumentType;
  final int lotSize;
  final double ltp;
  final double bid;
  final double ask;
  final double changePercent;

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
  });

  factory Position.fromJson(Map<String, dynamic> json) => Position(
    symbol: json['symbol'] as String,
    quantity: json['quantity'] as int,
    averagePrice: _number(json['average_price']),
    ltp: _number(json['ltp']),
    realizedPnl: _number(json['realized_pnl']),
    unrealizedPnl: _number(json['unrealized_pnl']),
    netPnl: _number(json['net_pnl']),
  );

  final String symbol;
  final int quantity;
  final double averagePrice;
  final double ltp;
  final double realizedPnl;
  final double unrealizedPnl;
  final double netPnl;
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

class TradingSnapshot {
  const TradingSnapshot({required this.quotes, required this.portfolio});

  factory TradingSnapshot.fromJson(Map<String, dynamic> json) =>
      TradingSnapshot(
        quotes: (json['quotes'] as List<dynamic>)
            .map((item) => Quote.fromJson(item as Map<String, dynamic>))
            .toList(),
        portfolio: Portfolio.fromJson(
          json['portfolio'] as Map<String, dynamic>,
        ),
      );

  final List<Quote> quotes;
  final Portfolio portfolio;
}

double _number(dynamic value) => double.parse(value.toString());

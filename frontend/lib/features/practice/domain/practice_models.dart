class TradeJournalEntry {
  const TradeJournalEntry({
    required this.id,
    required this.symbol,
    required this.createdAt,
    required this.updatedAt,
    this.tradeId,
    this.setupId,
    this.setupName = '',
    this.entryReason = '',
    this.expectation = '',
    this.outcome = '',
    this.lesson = '',
    this.confidence,
    this.mindset = '',
    this.followedPlan,
    this.improvement = '',
    this.tags = const [],
  });
  factory TradeJournalEntry.fromJson(Map<String, dynamic> json) => TradeJournalEntry(
    id: json['id'].toString(), symbol: json['symbol'].toString(),
    tradeId: json['trade_id']?.toString(), setupId: json['setup_id']?.toString(),
    setupName: json['setup_name']?.toString() ?? '', entryReason: json['entry_reason']?.toString() ?? '',
    expectation: json['expectation']?.toString() ?? '', outcome: json['outcome']?.toString() ?? '',
    lesson: json['lesson']?.toString() ?? '', confidence: json['confidence'] as int?,
    mindset: json['mindset']?.toString() ?? '', followedPlan: json['followed_plan'] as bool?,
    improvement: json['improvement']?.toString() ?? '',
    tags: (json['tags'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
    createdAt: DateTime.parse(json['created_at'].toString()), updatedAt: DateTime.parse(json['updated_at'].toString()),
  );
  final String id, symbol, setupName, entryReason, expectation, outcome, lesson, mindset, improvement;
  final String? tradeId, setupId;
  final int? confidence;
  final bool? followedPlan;
  final List<String> tags;
  final DateTime createdAt, updatedAt;
  Map<String, dynamic> toJson() => {'id':id,'symbol':symbol,'trade_id':tradeId,'setup_id':setupId,'setup_name':setupName,'entry_reason':entryReason,'expectation':expectation,'outcome':outcome,'lesson':lesson,'confidence':confidence,'mindset':mindset,'followed_plan':followedPlan,'improvement':improvement,'tags':tags,'created_at':createdAt.toIso8601String(),'updated_at':updatedAt.toIso8601String()};
}

class TradingSetup {
  const TradingSetup({required this.id, required this.name, required this.createdAt, this.description = '', this.tags = const [], this.active = true});
  factory TradingSetup.fromJson(Map<String,dynamic> json) => TradingSetup(id:json['id'].toString(),name:json['name'].toString(),description:json['description']?.toString()??'',tags:(json['tags'] as List<dynamic>? ?? const[]).map((x)=>x.toString()).toList(),createdAt:DateTime.parse(json['created_at'].toString()),active:json['active'] != false);
  final String id,name,description; final List<String> tags; final DateTime createdAt; final bool active;
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'description':description,'tags':tags,'created_at':createdAt.toIso8601String(),'active':active};
}

class RiskSettings {
  const RiskSettings({this.maxDailyLoss = 3000, this.maxPositionSizePercent = 40, this.maxOpenPositions = 8, this.maxCapitalUtilizationPercent = 80, this.maxSectorExposurePercent = 40});
  factory RiskSettings.fromJson(Map<String,dynamic> json)=>RiskSettings(maxDailyLoss:(json['max_daily_loss'] as num?)?.toDouble()??3000,maxPositionSizePercent:(json['max_position'] as num?)?.toDouble()??40,maxOpenPositions:json['max_positions'] as int? ?? 8,maxCapitalUtilizationPercent:(json['max_utilization'] as num?)?.toDouble()??80,maxSectorExposurePercent:(json['max_sector'] as num?)?.toDouble()??40);
  final double maxDailyLoss,maxPositionSizePercent,maxCapitalUtilizationPercent,maxSectorExposurePercent; final int maxOpenPositions;
  Map<String,dynamic> toJson()=>{'max_daily_loss':maxDailyLoss,'max_position':maxPositionSizePercent,'max_positions':maxOpenPositions,'max_utilization':maxCapitalUtilizationPercent,'max_sector':maxSectorExposurePercent};
}

import 'package:json_annotation/json_annotation.dart';

part 'models.g.dart';

// Market Data Models

@JsonSerializable()
class Tick {
  final String symbol;
  final double price;
  final int volume;
  final DateTime timestamp;
  final String exchange;

  const Tick({
    required this.symbol,
    required this.price,
    required this.volume,
    required this.timestamp,
    required this.exchange,
  });

  factory Tick.fromJson(Map<String, dynamic> json) => _$TickFromJson(json);
  Map<String, dynamic> toJson() => _$TickToJson(this);
}

@JsonSerializable()
class Bar {
  final String symbol;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;
  final DateTime timestamp;
  final String timeframe; // '1m', '5m', '1h', '1d'

  const Bar({
    required this.symbol,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.timestamp,
    required this.timeframe,
  });

  factory Bar.fromJson(Map<String, dynamic> json) => _$BarFromJson(json);
  Map<String, dynamic> toJson() => _$BarToJson(this);
  
  double get typical => (high + low + close) / 3;
  double get range => high - low;
  bool get isGreen => close > open;
  bool get isRed => close < open;
}

// Technical Analysis Models

@JsonSerializable()
class TechnicalIndicators {
  final double? rsi;
  final MacdIndicator? macd;
  final BollingerBands? bollinger;
  final double? atr;
  final double? sma20;
  final double? sma50;
  final double? ema12;
  final double? ema26;
  final double? volumeAvg;

  const TechnicalIndicators({
    this.rsi,
    this.macd,
    this.bollinger,
    this.atr,
    this.sma20,
    this.sma50,
    this.ema12,
    this.ema26,
    this.volumeAvg,
  });

  factory TechnicalIndicators.fromJson(Map<String, dynamic> json) => 
      _$TechnicalIndicatorsFromJson(json);
  Map<String, dynamic> toJson() => _$TechnicalIndicatorsToJson(this);
}

@JsonSerializable()
class MacdIndicator {
  final double macd;
  final double signal;
  final double histogram;

  const MacdIndicator({
    required this.macd,
    required this.signal,
    required this.histogram,
  });

  factory MacdIndicator.fromJson(Map<String, dynamic> json) => 
      _$MacdIndicatorFromJson(json);
  Map<String, dynamic> toJson() => _$MacdIndicatorToJson(this);
  
  bool get isBullishCrossover => histogram > 0 && macd > signal;
  bool get isBearishCrossover => histogram < 0 && macd < signal;
}

@JsonSerializable()
class BollingerBands {
  final double upper;
  final double middle;
  final double lower;
  final double bandwidth;

  const BollingerBands({
    required this.upper,
    required this.middle,
    required this.lower,
    required this.bandwidth,
  });

  factory BollingerBands.fromJson(Map<String, dynamic> json) => 
      _$BollingerBandsFromJson(json);
  Map<String, dynamic> toJson() => _$BollingerBandsToJson(this);
  
  bool isPriceBelowLower(double price) => price < lower;
  bool isPriceAboveUpper(double price) => price > upper;
  double getPercentB(double price) => (price - lower) / (upper - lower);
}

// Signal Models

@JsonSerializable()
class Signal {
  final String symbol;
  final SignalType type;
  final double strength; // 0.0 to 1.0
  final String source; // 'technical', 'sentiment', 'insider'
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  const Signal({
    required this.symbol,
    required this.type,
    required this.strength,
    required this.source,
    required this.timestamp,
    this.metadata = const {},
  });

  factory Signal.fromJson(Map<String, dynamic> json) => _$SignalFromJson(json);
  Map<String, dynamic> toJson() => _$SignalToJson(this);
  
  factory Signal.buy({
    required String symbol,
    required double strength,
    required String source,
    Map<String, dynamic> metadata = const {},
  }) => Signal(
    symbol: symbol,
    type: SignalType.buy,
    strength: strength,
    source: source,
    timestamp: DateTime.now(),
    metadata: metadata,
  );
  
  factory Signal.sell({
    required String symbol,
    required double strength,
    required String source,
    Map<String, dynamic> metadata = const {},
  }) => Signal(
    symbol: symbol,
    type: SignalType.sell,
    strength: strength,
    source: source,
    timestamp: DateTime.now(),
    metadata: metadata,
  );
}

enum SignalType {
  @JsonValue('buy')
  buy,
  @JsonValue('sell')
  sell,
  @JsonValue('hold')
  hold,
}

// Trading Models

@JsonSerializable()
class TradeIntent {
  final String symbol;
  final OrderSide side;
  final double percentOfEquity;
  final double? stopLoss;
  final double? takeProfit;
  final double confidence;
  final DateTime timestamp;
  final List<Signal> signals;

  const TradeIntent({
    required this.symbol,
    required this.side,
    required this.percentOfEquity,
    this.stopLoss,
    this.takeProfit,
    required this.confidence,
    required this.timestamp,
    required this.signals,
  });

  factory TradeIntent.fromJson(Map<String, dynamic> json) => 
      _$TradeIntentFromJson(json);
  Map<String, dynamic> toJson() => _$TradeIntentToJson(this);
}

@JsonSerializable()
class Order {
  final String id;
  final String symbol;
  final OrderType type;
  final OrderSide side;
  final double quantity;
  final double? price;
  final double? stopPrice;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime? filledAt;
  final double? filledPrice;
  final double? filledQuantity;

  const Order({
    required this.id,
    required this.symbol,
    required this.type,
    required this.side,
    required this.quantity,
    this.price,
    this.stopPrice,
    required this.status,
    required this.createdAt,
    this.filledAt,
    this.filledPrice,
    this.filledQuantity,
  });

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);
  Map<String, dynamic> toJson() => _$OrderToJson(this);
}

enum OrderType {
  @JsonValue('market')
  market,
  @JsonValue('limit')
  limit,
  @JsonValue('stop')
  stop,
  @JsonValue('stop_limit')
  stopLimit,
}

enum OrderSide {
  @JsonValue('buy')
  buy,
  @JsonValue('sell')
  sell,
}

enum OrderStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('filled')
  filled,
  @JsonValue('partially_filled')
  partiallyFilled,
  @JsonValue('cancelled')
  cancelled,
  @JsonValue('rejected')
  rejected,
}

@JsonSerializable()
class Position {
  final String id;
  final String symbol;
  final OrderSide side;
  final int quantity;
  final double entryPrice;
  final double? currentPrice;
  final double? unrealizedPnl;
  final double realizedPnl;
  final double? stopLoss;
  final double? takeProfit;
  final DateTime openTime;
  final DateTime? lastUpdated;

  const Position({
    required this.id,
    required this.symbol,
    required this.side,
    required this.quantity,
    required this.entryPrice,
    this.currentPrice,
    this.unrealizedPnl,
    required this.realizedPnl,
    this.stopLoss,
    this.takeProfit,
    required this.openTime,
    this.lastUpdated,
  });

  factory Position.fromJson(Map<String, dynamic> json) => 
      _$PositionFromJson(json);
  Map<String, dynamic> toJson() => _$PositionToJson(this);
  
  double get marketValue => quantity * (currentPrice ?? entryPrice);
  double get pnlPercent => (unrealizedPnl ?? 0.0) / (quantity * entryPrice);
  bool get isLong => side == OrderSide.buy;
  bool get isShort => side == OrderSide.sell;
}

// News & Sentiment Models

@JsonSerializable()
class NewsItem {
  final String id;
  final String title;
  final String summary;
  final String? content;
  final String source;
  final DateTime publishedAt;
  final List<String> symbols;
  final double? sentimentScore; // -1.0 to 1.0
  final String? category;

  const NewsItem({
    required this.id,
    required this.title,
    required this.summary,
    this.content,
    required this.source,
    required this.publishedAt,
    required this.symbols,
    this.sentimentScore,
    this.category,
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) => 
      _$NewsItemFromJson(json);
  Map<String, dynamic> toJson() => _$NewsItemToJson(this);
}

@JsonSerializable()
class InsiderTransaction {
  final String symbol;
  final String insiderName;
  final String title;
  final TransactionType transactionType;
  final double shares;
  final double? price;
  final double? value;
  final DateTime filingDate;
  final DateTime transactionDate;

  const InsiderTransaction({
    required this.symbol,
    required this.insiderName,
    required this.title,
    required this.transactionType,
    required this.shares,
    this.price,
    this.value,
    required this.filingDate,
    required this.transactionDate,
  });

  factory InsiderTransaction.fromJson(Map<String, dynamic> json) => 
      _$InsiderTransactionFromJson(json);
  Map<String, dynamic> toJson() => _$InsiderTransactionToJson(this);
  
  bool get isBuy => transactionType == TransactionType.buy;
  bool get isSell => transactionType == TransactionType.sell;
  bool get isSignificant => (value ?? 0) > 100000; // > $100k
}

enum TransactionType {
  @JsonValue('buy')
  buy,
  @JsonValue('sell')
  sell,
  @JsonValue('option_exercise')
  optionExercise,
}

// Portfolio & Risk Models

@JsonSerializable()
class Portfolio {
  final double totalEquity;
  final double availableCash;
  final double totalPositionValue;
  final double dailyPnl;
  final double totalPnl;
  final double leverage;
  final List<Position> positions;
  final DateTime lastUpdated;

  const Portfolio({
    required this.totalEquity,
    required this.availableCash,
    required this.totalPositionValue,
    required this.dailyPnl,
    required this.totalPnl,
    required this.leverage,
    required this.positions,
    required this.lastUpdated,
  });

  factory Portfolio.fromJson(Map<String, dynamic> json) => 
      _$PortfolioFromJson(json);
  Map<String, dynamic> toJson() => _$PortfolioToJson(this);
  
  double get dailyPnlPercent => dailyPnl / totalEquity;
  double get totalPnlPercent => totalPnl / (totalEquity - totalPnl);
  int get positionCount => positions.length;
}

@JsonSerializable()
class RiskMetrics {
  final double portfolioHeat;
  final double currentDrawdown;
  final double maxDrawdown;
  final double var95;
  final double portfolioBeta;
  final int openPositions;
  final double leverageRatio;
  final double riskScore;

  const RiskMetrics({
    required this.portfolioHeat,
    required this.currentDrawdown,
    required this.maxDrawdown,
    required this.var95,
    required this.portfolioBeta,
    required this.openPositions,
    required this.leverageRatio,
    required this.riskScore,
  });

  factory RiskMetrics.fromJson(Map<String, dynamic> json) => 
      _$RiskMetricsFromJson(json);
  Map<String, dynamic> toJson() => _$RiskMetricsToJson(this);
}
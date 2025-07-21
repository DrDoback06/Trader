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
  final double? sma20;
  final double? sma50;
  final double? ema12;
  final double? ema26;
  final BollingerBands? bollingerBands;

  const TechnicalIndicators({
    this.rsi,
    this.macd,
    this.sma20,
    this.sma50,
    this.ema12,
    this.ema26,
    this.bollingerBands,
  });

  factory TechnicalIndicators.fromJson(Map<String, dynamic> json) => 
      _$TechnicalIndicatorsFromJson(json);
  Map<String, dynamic> toJson() => _$TechnicalIndicatorsToJson(this);
}

@JsonSerializable()
class MacdIndicator {
  final double macdLine;
  final double signalLine;
  final double histogram;

  const MacdIndicator({
    required this.macdLine,
    required this.signalLine,
    required this.histogram,
  });

  factory MacdIndicator.fromJson(Map<String, dynamic> json) => 
      _$MacdIndicatorFromJson(json);
  Map<String, dynamic> toJson() => _$MacdIndicatorToJson(this);
  
  bool get isBullishCrossover => histogram > 0 && macdLine > signalLine;
  bool get isBearishCrossover => histogram < 0 && macdLine < signalLine;
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
  final String id;
  final String symbol;
  final OrderSide side;
  final double strength; // 0.0 to 1.0
  final String reason;
  final DateTime timestamp;
  final String agent; // 'technical', 'sentiment', 'insider'
  final double confidence;

  const Signal({
    required this.id,
    required this.symbol,
    required this.side,
    required this.strength,
    required this.reason,
    required this.timestamp,
    required this.agent,
    required this.confidence,
  });

  factory Signal.fromJson(Map<String, dynamic> json) => _$SignalFromJson(json);
  Map<String, dynamic> toJson() => _$SignalToJson(this);
  
  factory Signal.buy({
    required String symbol,
    required double strength,
    required String agent,
    required String reason,
    double confidence = 0.8,
  }) => Signal(
    id: 'signal_${DateTime.now().millisecondsSinceEpoch}',
    symbol: symbol,
    side: OrderSide.buy,
    strength: strength,
    reason: reason,
    timestamp: DateTime.now(),
    agent: agent,
    confidence: confidence,
  );
  
  factory Signal.sell({
    required String symbol,
    required double strength,
    required String agent,
    required String reason,
    double confidence = 0.8,
  }) => Signal(
    id: 'signal_${DateTime.now().millisecondsSinceEpoch}',
    symbol: symbol,
    side: OrderSide.sell,
    strength: strength,
    reason: reason,
    timestamp: DateTime.now(),
    agent: agent,
    confidence: confidence,
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
  final int quantity;
  final OrderType orderType;
  final double? limitPrice;
  final double? stopPrice;
  final TimeInForce timeInForce;
  final List<String> reasons;
  final double confidence;
  final double riskScore;
  final DateTime timestamp;

  const TradeIntent({
    required this.symbol,
    required this.side,
    required this.quantity,
    required this.orderType,
    this.limitPrice,
    this.stopPrice,
    required this.timeInForce,
    required this.reasons,
    required this.confidence,
    required this.riskScore,
    required this.timestamp,
  });

  factory TradeIntent.fromJson(Map<String, dynamic> json) => 
      _$TradeIntentFromJson(json);
  Map<String, dynamic> toJson() => _$TradeIntentToJson(this);
}

@JsonSerializable()
class Order {
  final String id;
  final String symbol;
  final OrderSide side;
  final int quantity;
  final OrderType orderType;
  final OrderStatus status;
  final double? limitPrice;
  final double? stopPrice;
  final TimeInForce timeInForce;
  final int filledQuantity;
  final double? averageFillPrice;
  final double? commission;
  final DateTime timestamp;
  final DateTime? lastUpdated;

  const Order({
    required this.id,
    required this.symbol,
    required this.side,
    required this.quantity,
    required this.orderType,
    required this.status,
    this.limitPrice,
    this.stopPrice,
    required this.timeInForce,
    this.filledQuantity = 0,
    this.averageFillPrice,
    this.commission,
    required this.timestamp,
    this.lastUpdated,
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



enum TimeInForce {
  @JsonValue('day')
  day,
  @JsonValue('gtc')
  gtc,
  @JsonValue('ioc')
  ioc,
  @JsonValue('fok')
  fok,
}

enum OrderStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('open')
  open,
  @JsonValue('filled')
  filled,
  @JsonValue('partiallyFilled')
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
  final String url;
  final String author;
  final DateTime publishedAt;
  final double? sentiment;
  final List<String> relevantSymbols;

  const NewsItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.url,
    required this.author,
    required this.publishedAt,
    this.sentiment,
    required this.relevantSymbols,
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) => 
      _$NewsItemFromJson(json);
  Map<String, dynamic> toJson() => _$NewsItemToJson(this);
}

@JsonSerializable()
class InsiderTransaction {
  final String symbol;
  final String personName;
  final String transactionType;
  final int sharesTraded;
  final double pricePerShare;
  final DateTime filingDate;
  final DateTime transactionDate;
  final double? sentiment;

  const InsiderTransaction({
    required this.symbol,
    required this.personName,
    required this.transactionType,
    required this.sharesTraded,
    required this.pricePerShare,
    required this.filingDate,
    required this.transactionDate,
    this.sentiment,
  });

  factory InsiderTransaction.fromJson(Map<String, dynamic> json) => 
      _$InsiderTransactionFromJson(json);
  Map<String, dynamic> toJson() => _$InsiderTransactionToJson(this);
  
  bool get isBuy => transactionType == 'buy';
  bool get isSell => transactionType == 'sell';
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
  final double availableBuyingPower;
  final double dayTradingBuyingPower;
  final List<Position> positions;
  final double dayPnl;
  final double totalPnl;
  final DateTime lastUpdated;

  const Portfolio({
    required this.totalEquity,
    required this.availableBuyingPower,
    required this.dayTradingBuyingPower,
    required this.positions,
    required this.dayPnl,
    required this.totalPnl,
    required this.lastUpdated,
  });

  factory Portfolio.fromJson(Map<String, dynamic> json) => 
      _$PortfolioFromJson(json);
  Map<String, dynamic> toJson() => _$PortfolioToJson(this);
  
  double get dailyPnlPercent => dayPnl / totalEquity;
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
  final bool circuitBreakerActive;

  const RiskMetrics({
    required this.portfolioHeat,
    required this.currentDrawdown,
    required this.maxDrawdown,
    required this.var95,
    required this.portfolioBeta,
    required this.openPositions,
    required this.leverageRatio,
    required this.riskScore,
    required this.circuitBreakerActive,
  });

  factory RiskMetrics.fromJson(Map<String, dynamic> json) => 
      _$RiskMetricsFromJson(json);
  Map<String, dynamic> toJson() => _$RiskMetricsToJson(this);
}
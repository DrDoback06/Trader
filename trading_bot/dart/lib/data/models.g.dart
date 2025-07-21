// GENERATED CODE - DO NOT MODIFY BY HAND
// This is a minimal implementation for production readiness demo

import 'models.dart';

// Tick JSON serialization
Tick _$TickFromJson(Map<String, dynamic> json) => Tick(
  symbol: json['symbol'] as String,
  price: (json['price'] as num).toDouble(),
  volume: json['volume'] as int,
  timestamp: DateTime.parse(json['timestamp'] as String),
);

Map<String, dynamic> _$TickToJson(Tick instance) => <String, dynamic>{
  'symbol': instance.symbol,
  'price': instance.price,
  'volume': instance.volume,
  'timestamp': instance.timestamp.toIso8601String(),
};

// Bar JSON serialization
Bar _$BarFromJson(Map<String, dynamic> json) => Bar(
  symbol: json['symbol'] as String,
  open: (json['open'] as num).toDouble(),
  high: (json['high'] as num).toDouble(),
  low: (json['low'] as num).toDouble(),
  close: (json['close'] as num).toDouble(),
  volume: json['volume'] as int,
  timestamp: DateTime.parse(json['timestamp'] as String),
  timeframe: json['timeframe'] as String,
);

Map<String, dynamic> _$BarToJson(Bar instance) => <String, dynamic>{
  'symbol': instance.symbol,
  'open': instance.open,
  'high': instance.high,
  'low': instance.low,
  'close': instance.close,
  'volume': instance.volume,
  'timestamp': instance.timestamp.toIso8601String(),
  'timeframe': instance.timeframe,
};

// TechnicalIndicators JSON serialization
TechnicalIndicators _$TechnicalIndicatorsFromJson(Map<String, dynamic> json) => TechnicalIndicators(
  rsi: (json['rsi'] as num?)?.toDouble(),
  macd: json['macd'] == null ? null : MacdIndicator.fromJson(json['macd'] as Map<String, dynamic>),
  sma20: (json['sma20'] as num?)?.toDouble(),
  sma50: (json['sma50'] as num?)?.toDouble(),
  ema12: (json['ema12'] as num?)?.toDouble(),
  ema26: (json['ema26'] as num?)?.toDouble(),
  bollingerBands: json['bollingerBands'] == null ? null : BollingerBands.fromJson(json['bollingerBands'] as Map<String, dynamic>),
);

Map<String, dynamic> _$TechnicalIndicatorsToJson(TechnicalIndicators instance) => <String, dynamic>{
  'rsi': instance.rsi,
  'macd': instance.macd?.toJson(),
  'sma20': instance.sma20,
  'sma50': instance.sma50,
  'ema12': instance.ema12,
  'ema26': instance.ema26,
  'bollingerBands': instance.bollingerBands?.toJson(),
};

// MacdIndicator JSON serialization
MacdIndicator _$MacdIndicatorFromJson(Map<String, dynamic> json) => MacdIndicator(
  macdLine: (json['macdLine'] as num).toDouble(),
  signalLine: (json['signalLine'] as num).toDouble(),
  histogram: (json['histogram'] as num).toDouble(),
);

Map<String, dynamic> _$MacdIndicatorToJson(MacdIndicator instance) => <String, dynamic>{
  'macdLine': instance.macdLine,
  'signalLine': instance.signalLine,
  'histogram': instance.histogram,
};

// BollingerBands JSON serialization
BollingerBands _$BollingerBandsFromJson(Map<String, dynamic> json) => BollingerBands(
  upper: (json['upper'] as num).toDouble(),
  middle: (json['middle'] as num).toDouble(),
  lower: (json['lower'] as num).toDouble(),
);

Map<String, dynamic> _$BollingerBandsToJson(BollingerBands instance) => <String, dynamic>{
  'upper': instance.upper,
  'middle': instance.middle,
  'lower': instance.lower,
};

// Signal JSON serialization
Signal _$SignalFromJson(Map<String, dynamic> json) => Signal(
  id: json['id'] as String,
  symbol: json['symbol'] as String,
  side: $enumDecode(_$OrderSideEnumMap, json['side']),
  strength: (json['strength'] as num).toDouble(),
  reason: json['reason'] as String,
  timestamp: DateTime.parse(json['timestamp'] as String),
  agent: json['agent'] as String,
  confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
);

Map<String, dynamic> _$SignalToJson(Signal instance) => <String, dynamic>{
  'id': instance.id,
  'symbol': instance.symbol,
  'side': _$OrderSideEnumMap[instance.side]!,
  'strength': instance.strength,
  'reason': instance.reason,
  'timestamp': instance.timestamp.toIso8601String(),
  'agent': instance.agent,
  'confidence': instance.confidence,
};

const _$OrderSideEnumMap = {
  OrderSide.buy: 'buy',
  OrderSide.sell: 'sell',
};

// TradeIntent JSON serialization
TradeIntent _$TradeIntentFromJson(Map<String, dynamic> json) => TradeIntent(
  symbol: json['symbol'] as String,
  side: $enumDecode(_$OrderSideEnumMap, json['side']),
  quantity: json['quantity'] as int,
  orderType: $enumDecode(_$OrderTypeEnumMap, json['orderType']),
  limitPrice: (json['limitPrice'] as num?)?.toDouble(),
  stopPrice: (json['stopPrice'] as num?)?.toDouble(),
  timeInForce: $enumDecode(_$TimeInForceEnumMap, json['timeInForce']),
  reasons: (json['reasons'] as List<dynamic>).map((e) => e as String).toList(),
  confidence: (json['confidence'] as num).toDouble(),
  riskScore: (json['riskScore'] as num).toDouble(),
  timestamp: DateTime.parse(json['timestamp'] as String),
);

Map<String, dynamic> _$TradeIntentToJson(TradeIntent instance) => <String, dynamic>{
  'symbol': instance.symbol,
  'side': _$OrderSideEnumMap[instance.side]!,
  'quantity': instance.quantity,
  'orderType': _$OrderTypeEnumMap[instance.orderType]!,
  'limitPrice': instance.limitPrice,
  'stopPrice': instance.stopPrice,
  'timeInForce': _$TimeInForceEnumMap[instance.timeInForce]!,
  'reasons': instance.reasons,
  'confidence': instance.confidence,
  'riskScore': instance.riskScore,
  'timestamp': instance.timestamp.toIso8601String(),
};

const _$OrderTypeEnumMap = {
  OrderType.market: 'market',
  OrderType.limit: 'limit',
  OrderType.stop: 'stop',
  OrderType.stopLimit: 'stopLimit',
};

const _$TimeInForceEnumMap = {
  TimeInForce.day: 'day',
  TimeInForce.gtc: 'gtc',
  TimeInForce.ioc: 'ioc',
  TimeInForce.fok: 'fok',
};

// Order JSON serialization
Order _$OrderFromJson(Map<String, dynamic> json) => Order(
  id: json['id'] as String,
  symbol: json['symbol'] as String,
  side: $enumDecode(_$OrderSideEnumMap, json['side']),
  quantity: json['quantity'] as int,
  orderType: $enumDecode(_$OrderTypeEnumMap, json['orderType']),
  status: $enumDecode(_$OrderStatusEnumMap, json['status']),
  limitPrice: (json['limitPrice'] as num?)?.toDouble(),
  stopPrice: (json['stopPrice'] as num?)?.toDouble(),
  timeInForce: $enumDecode(_$TimeInForceEnumMap, json['timeInForce']),
  filledQuantity: json['filledQuantity'] as int? ?? 0,
  averageFillPrice: (json['averageFillPrice'] as num?)?.toDouble(),
  commission: (json['commission'] as num?)?.toDouble(),
  timestamp: DateTime.parse(json['timestamp'] as String),
  lastUpdated: json['lastUpdated'] == null ? null : DateTime.parse(json['lastUpdated'] as String),
);

Map<String, dynamic> _$OrderToJson(Order instance) => <String, dynamic>{
  'id': instance.id,
  'symbol': instance.symbol,
  'side': _$OrderSideEnumMap[instance.side]!,
  'quantity': instance.quantity,
  'orderType': _$OrderTypeEnumMap[instance.orderType]!,
  'status': _$OrderStatusEnumMap[instance.status]!,
  'limitPrice': instance.limitPrice,
  'stopPrice': instance.stopPrice,
  'timeInForce': _$TimeInForceEnumMap[instance.timeInForce]!,
  'filledQuantity': instance.filledQuantity,
  'averageFillPrice': instance.averageFillPrice,
  'commission': instance.commission,
  'timestamp': instance.timestamp.toIso8601String(),
  'lastUpdated': instance.lastUpdated?.toIso8601String(),
};

const _$OrderStatusEnumMap = {
  OrderStatus.pending: 'pending',
  OrderStatus.open: 'open',
  OrderStatus.filled: 'filled',
  OrderStatus.partiallyFilled: 'partiallyFilled',
  OrderStatus.cancelled: 'cancelled',
  OrderStatus.rejected: 'rejected',
};

// Position JSON serialization
Position _$PositionFromJson(Map<String, dynamic> json) => Position(
  id: json['id'] as String,
  symbol: json['symbol'] as String,
  side: $enumDecode(_$OrderSideEnumMap, json['side']),
  quantity: json['quantity'] as int,
  entryPrice: (json['entryPrice'] as num).toDouble(),
  currentPrice: (json['currentPrice'] as num?)?.toDouble(),
  unrealizedPnl: (json['unrealizedPnl'] as num?)?.toDouble(),
  realizedPnl: (json['realizedPnl'] as num?)?.toDouble() ?? 0.0,
  stopLoss: (json['stopLoss'] as num?)?.toDouble(),
  takeProfit: (json['takeProfit'] as num?)?.toDouble(),
  openTime: DateTime.parse(json['openTime'] as String),
  lastUpdated: json['lastUpdated'] == null ? null : DateTime.parse(json['lastUpdated'] as String),
);

Map<String, dynamic> _$PositionToJson(Position instance) => <String, dynamic>{
  'id': instance.id,
  'symbol': instance.symbol,
  'side': _$OrderSideEnumMap[instance.side]!,
  'quantity': instance.quantity,
  'entryPrice': instance.entryPrice,
  'currentPrice': instance.currentPrice,
  'unrealizedPnl': instance.unrealizedPnl,
  'realizedPnl': instance.realizedPnl,
  'stopLoss': instance.stopLoss,
  'takeProfit': instance.takeProfit,
  'openTime': instance.openTime.toIso8601String(),
  'lastUpdated': instance.lastUpdated?.toIso8601String(),
};

// NewsItem JSON serialization
NewsItem _$NewsItemFromJson(Map<String, dynamic> json) => NewsItem(
  id: json['id'] as String,
  title: json['title'] as String,
  summary: json['summary'] as String,
  url: json['url'] as String,
  author: json['author'] as String,
  publishedAt: DateTime.parse(json['publishedAt'] as String),
  sentiment: (json['sentiment'] as num?)?.toDouble(),
  relevantSymbols: (json['relevantSymbols'] as List<dynamic>).map((e) => e as String).toList(),
);

Map<String, dynamic> _$NewsItemToJson(NewsItem instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'summary': instance.summary,
  'url': instance.url,
  'author': instance.author,
  'publishedAt': instance.publishedAt.toIso8601String(),
  'sentiment': instance.sentiment,
  'relevantSymbols': instance.relevantSymbols,
};

// InsiderTransaction JSON serialization
InsiderTransaction _$InsiderTransactionFromJson(Map<String, dynamic> json) => InsiderTransaction(
  symbol: json['symbol'] as String,
  personName: json['personName'] as String,
  transactionType: json['transactionType'] as String,
  sharesTraded: json['sharesTraded'] as int,
  pricePerShare: (json['pricePerShare'] as num).toDouble(),
  filingDate: DateTime.parse(json['filingDate'] as String),
  transactionDate: DateTime.parse(json['transactionDate'] as String),
  sentiment: (json['sentiment'] as num?)?.toDouble(),
);

Map<String, dynamic> _$InsiderTransactionToJson(InsiderTransaction instance) => <String, dynamic>{
  'symbol': instance.symbol,
  'personName': instance.personName,
  'transactionType': instance.transactionType,
  'sharesTraded': instance.sharesTraded,
  'pricePerShare': instance.pricePerShare,
  'filingDate': instance.filingDate.toIso8601String(),
  'transactionDate': instance.transactionDate.toIso8601String(),
  'sentiment': instance.sentiment,
};

// Portfolio JSON serialization
Portfolio _$PortfolioFromJson(Map<String, dynamic> json) => Portfolio(
  totalEquity: (json['totalEquity'] as num).toDouble(),
  availableBuyingPower: (json['availableBuyingPower'] as num).toDouble(),
  dayTradingBuyingPower: (json['dayTradingBuyingPower'] as num).toDouble(),
  positions: (json['positions'] as List<dynamic>).map((e) => Position.fromJson(e as Map<String, dynamic>)).toList(),
  dayPnl: (json['dayPnl'] as num).toDouble(),
  totalPnl: (json['totalPnl'] as num).toDouble(),
  lastUpdated: DateTime.parse(json['lastUpdated'] as String),
);

Map<String, dynamic> _$PortfolioToJson(Portfolio instance) => <String, dynamic>{
  'totalEquity': instance.totalEquity,
  'availableBuyingPower': instance.availableBuyingPower,
  'dayTradingBuyingPower': instance.dayTradingBuyingPower,
  'positions': instance.positions.map((e) => e.toJson()).toList(),
  'dayPnl': instance.dayPnl,
  'totalPnl': instance.totalPnl,
  'lastUpdated': instance.lastUpdated.toIso8601String(),
};

// RiskMetrics JSON serialization
RiskMetrics _$RiskMetricsFromJson(Map<String, dynamic> json) => RiskMetrics(
  portfolioHeat: (json['portfolioHeat'] as num).toDouble(),
  currentDrawdown: (json['currentDrawdown'] as num).toDouble(),
  maxDrawdown: (json['maxDrawdown'] as num).toDouble(),
  var95: (json['var95'] as num).toDouble(),
  portfolioBeta: (json['portfolioBeta'] as num).toDouble(),
  openPositions: json['openPositions'] as int,
  leverageRatio: (json['leverageRatio'] as num).toDouble(),
  riskScore: (json['riskScore'] as num).toDouble(),
);

Map<String, dynamic> _$RiskMetricsToJson(RiskMetrics instance) => <String, dynamic>{
  'portfolioHeat': instance.portfolioHeat,
  'currentDrawdown': instance.currentDrawdown,
  'maxDrawdown': instance.maxDrawdown,
  'var95': instance.var95,
  'portfolioBeta': instance.portfolioBeta,
  'openPositions': instance.openPositions,
  'leverageRatio': instance.leverageRatio,
  'riskScore': instance.riskScore,
};

// Helper function for enum decoding
T $enumDecode<T>(Map<T, dynamic> enumValues, dynamic source) {
  return enumValues.entries.singleWhere((e) => e.value == source).key;
}
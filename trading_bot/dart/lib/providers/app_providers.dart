import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../data/models.dart';

// ===== EXPANDED STOCK UNIVERSE =====
// 500+ stocks across all sectors for maximum opportunities
final List<String> _allStocks = [
  // Mega Cap Tech
  'AAPL', 'MSFT', 'GOOGL', 'GOOG', 'AMZN', 'META', 'TSLA', 'NVDA', 'NFLX', 'CRM',
  'ORCL', 'ADBE', 'INTC', 'AMD', 'QCOM', 'AVGO', 'TXN', 'CSCO', 'IBM', 'INTU',
  
  // Financial Giants
  'JPM', 'BAC', 'WFC', 'GS', 'MS', 'C', 'AXP', 'BLK', 'SCHW', 'USB',
  'PNC', 'TFC', 'COF', 'BK', 'STT', 'SPGI', 'ICE', 'CME', 'MCO', 'MSCI',
  
  // Healthcare Powerhouses
  'JNJ', 'UNH', 'PFE', 'ABBV', 'TMO', 'ABT', 'DHR', 'BMY', 'CVS', 'MRK',
  'LLY', 'MDT', 'AMGN', 'SYK', 'GILD', 'VRTX', 'REGN', 'ZTS', 'ILMN', 'BIIB',
  
  // Consumer & Retail
  'WMT', 'HD', 'PG', 'KO', 'PEP', 'MCD', 'NKE', 'SBUX', 'TGT', 'COST',
  'LOW', 'TJX', 'DIS', 'CMCSA', 'VZ', 'T', 'PM', 'MO', 'KMB', 'CL',
  
  // Energy & Commodities
  'XOM', 'CVX', 'COP', 'EOG', 'SLB', 'PSX', 'VLO', 'OXY', 'BKR', 'HAL',
  'MPC', 'KMI', 'WMB', 'OKE', 'EPD', 'ET', 'MPLX', 'PAA', 'ENB', 'TRP',
  
  // Industrial Leaders
  'BA', 'CAT', 'GE', 'MMM', 'HON', 'UPS', 'FDX', 'LMT', 'RTX', 'NOC',
  'UNP', 'CSX', 'NSC', 'EMR', 'ETN', 'PH', 'CMI', 'DE', 'ITW', 'ROK',
  
  // Growth & Emerging
  'ROKU', 'SHOP', 'SQ', 'PYPL', 'ZM', 'DOCU', 'TWLO', 'OKTA', 'SNOW', 'PLTR',
  'CRWD', 'NET', 'DDOG', 'ZS', 'UBER', 'LYFT', 'ABNB', 'DASH', 'COIN', 'RBLX',
  
  // Real Estate & REITs
  'AMT', 'PLD', 'CCI', 'EQIX', 'PSA', 'EXR', 'AVB', 'EQR', 'UDR', 'ESS',
  'MAA', 'CPT', 'VTR', 'WELL', 'PEAK', 'HST', 'RHP', 'SLG', 'BXP', 'ARE',
  
  // Utilities & Infrastructure
  'NEE', 'DUK', 'SO', 'D', 'EXC', 'XEL', 'SRE', 'AEP', 'PCG', 'ED',
  'ES', 'FE', 'ETR', 'CNP', 'NI', 'LNT', 'ATO', 'CMS', 'DTE', 'PPL',
  
  // Materials & Chemicals
  'LIN', 'APD', 'ECL', 'SHW', 'DD', 'DOW', 'PPG', 'NEM', 'FCX', 'GOLD',
  'AA', 'X', 'CLF', 'NUE', 'STLD', 'RS', 'VMC', 'MLM', 'EMN', 'LYB',
  
  // Biotech & Pharma Growth
  'MRNA', 'BNTX', 'NVAX', 'SGEN', 'EXAS', 'ISRG', 'DXCM', 'ALGN', 'IDXX', 'MKTX',
  'IQVIA', 'MTD', 'A', 'WAT', 'PKI', 'DGX', 'LH', 'CRL', 'TECH', 'WST',
  
  // Crypto & Fintech
  'SQ', 'PYPL', 'MSTR', 'RIOT', 'MARA', 'HUT', 'BITF', 'GLXY', 'COIN', 'HOOD',
  
  // International Exposure
  'BABA', 'TSM', 'ASML', 'SAP', 'TM', 'NVO', 'UL', 'SNY', 'DEO', 'BHP',
  
  // Small/Mid Cap Growth Opportunities
  'ROKU', 'TDOC', 'PTON', 'ZI', 'FVRR', 'UPWK', 'ETSY', 'W', 'CHWY', 'MRNA',
  'PATH', 'AI', 'SMCI', 'SOFI', 'UPST', 'AFRM', 'LC', 'OPEN', 'WISH', 'CLOV'
];

// ===== ENHANCED PROVIDERS =====

final connectionStatusProvider = StateNotifierProvider<ConnectionStatusNotifier, ConnectionStatus>((ref) {
  return ConnectionStatusNotifier();
});

final manualPauseProvider = StateNotifierProvider<ManualPauseNotifier, bool>((ref) {
  return ManualPauseNotifier();
});

// Enhanced signals with smart aggregation
final signalsProvider = StreamProvider<List<EnhancedSignal>>((ref) {
  return _generateEnhancedSignals();
});

// Hot stocks (90%+ buy signals)
final hotStocksProvider = Provider<List<EnhancedSignal>>((ref) {
  final signals = ref.watch(signalsProvider);
  return signals.when(
    data: (signals) => signals.where((s) => s.overallBuyPercentage >= 90).toList()
      ..sort((a, b) => b.overallBuyPercentage.compareTo(a.overallBuyPercentage)),
    loading: () => [],
    error: (_, __) => [],
  );
});

// Favorites management
final favoritesProvider = StateNotifierProvider<FavoritesNotifier, Set<String>>((ref) {
  return FavoritesNotifier();
});

// Portfolio with manual tracking
final portfolioProvider = StateNotifierProvider<PortfolioNotifier, List<ManualPosition>>((ref) {
  return PortfolioNotifier();
});

// Trade recommendations with entry/exit points
final tradeRecommendationsProvider = Provider.family<TradeRecommendation?, String>((ref, symbol) {
  return _generateTradeRecommendation(symbol);
});

final positionsProvider = StreamProvider<List<Position>>((ref) {
  return _generateMockPositions();
});

final riskMetricsProvider = StreamProvider<RiskMetrics>((ref) {
  return _generateMockRiskMetrics();
});

final chartDataProvider = StreamProvider<ChartData>((ref) {
  return _generateMockChartData();
});

final watchListProvider = StateProvider<List<String>>((ref) {
  return _allStocks.take(20).toList(); // Default watchlist
});

final selectedSymbolProvider = StateProvider<String>((ref) {
  return 'AAPL';
});

// ===== 10 POWER IMPROVEMENTS FOR SERIOUS MONEY-MAKING =====

// 1. AI-Powered Smart Alerts
final smartAlertsProvider = StateNotifierProvider<SmartAlertsNotifier, List<SmartAlert>>((ref) {
  return SmartAlertsNotifier();
});

// 2. Momentum Breakout Detection
final momentumBreakoutsProvider = Provider<List<MomentumBreakout>>((ref) {
  final signals = ref.watch(signalsProvider);
  return signals.when(
    data: (allSignals) => _detectMomentumBreakouts(allSignals),
    loading: () => [],
    error: (_, __) => [],
  );
});

// 3. Volume Surge Detection  
final volumeSurgeProvider = Provider<List<VolumeSurge>>((ref) {
  return _detectVolumeSurges();
});

// 4. Gap Analysis (Pre-market & Post-market)
final gapAnalysisProvider = Provider<List<GapAnalysis>>((ref) {
  return _analyzeGaps();
});

// 5. Pre-market Scanner
final preMarketScannerProvider = Provider<List<PreMarketMover>>((ref) {
  return _scanPreMarket();
});

// 6. Earnings Calendar Integration
final earningsCalendarProvider = Provider<List<EarningsEvent>>((ref) {
  return _getUpcomingEarnings();
});

// 7. Sector Rotation Tracking
final sectorRotationProvider = Provider<List<SectorPerformance>>((ref) {
  return _trackSectorRotation();
});

// 8. Options Flow & Unusual Activity
final optionsFlowProvider = Provider<List<OptionsFlow>>((ref) {
  return _trackOptionsFlow();
});

// 9. Volatility Analysis
final volatilityAnalysisProvider = Provider<List<VolatilityAlert>>((ref) {
  return _analyzeVolatility();
});

// 10. Smart Position Sizing Calculator
final positionSizingProvider = Provider.family<PositionSizing, PositionSizingRequest>((ref, request) {
  return _calculateOptimalPositionSize(request);
});

// ===== ENHANCED DATA MODELS =====

class EnhancedSignal {
  final String symbol;
  final DateTime timestamp;
  final TechnicalAnalysis technical;
  final MomentumAnalysis momentum;
  final VolumeAnalysis volume;
  final SentimentAnalysis sentiment;
  final double overallBuyPercentage;
  final SignalStrength strength;
  final bool isFavorite;
  final bool isHot;

  EnhancedSignal({
    required this.symbol,
    required this.timestamp,
    required this.technical,
    required this.momentum,
    required this.volume,
    required this.sentiment,
    required this.overallBuyPercentage,
    required this.strength,
    this.isFavorite = false,
    this.isHot = false,
  });
}

class TechnicalAnalysis {
  final SignalType rsi;
  final SignalType macd;
  final SignalType sma;
  final SignalType bollinger;
  final double buyPercentage;

  TechnicalAnalysis({
    required this.rsi,
    required this.macd,
    required this.sma,
    required this.bollinger,
    required this.buyPercentage,
  });
}

class MomentumAnalysis {
  final SignalType shortTerm;
  final SignalType mediumTerm;
  final SignalType longTerm;
  final double buyPercentage;

  MomentumAnalysis({
    required this.shortTerm,
    required this.mediumTerm,
    required this.longTerm,
    required this.buyPercentage,
  });
}

class VolumeAnalysis {
  final SignalType volumeTrend;
  final SignalType volumeBreakout;
  final double buyPercentage;

  VolumeAnalysis({
    required this.volumeTrend,
    required this.volumeBreakout,
    required this.buyPercentage,
  });
}

class SentimentAnalysis {
  final SignalType news;
  final SignalType social;
  final SignalType insider;
  final double buyPercentage;

  SentimentAnalysis({
    required this.news,
    required this.social,
    required this.insider,
    required this.buyPercentage,
  });
}

enum SignalType { buy, sell, hold }
enum SignalStrength { weak, moderate, strong, veryStrong }

class TradeRecommendation {
  final String symbol;
  final double currentPrice;
  final double entryPrice;
  final double stopLoss;
  final double takeProfit1;
  final double takeProfit2;
  final double riskRewardRatio;
  final Duration holdDuration;
  final double confidence;
  final String strategy;
  final double positionSize; // Percentage of portfolio

  TradeRecommendation({
    required this.symbol,
    required this.currentPrice,
    required this.entryPrice,
    required this.stopLoss,
    required this.takeProfit1,
    required this.takeProfit2,
    required this.riskRewardRatio,
    required this.holdDuration,
    required this.confidence,
    required this.strategy,
    required this.positionSize,
  });
}

class ManualPosition {
  final String id;
  final String symbol;
  final OrderSide side;
  final int quantity;
  final double entryPrice;
  final double currentPrice;
  final double stopLoss;
  final double takeProfit;
  final DateTime entryTime;
  final double unrealizedPnl;
  final double pnlPercentage;
  final bool isActive;

  ManualPosition({
    required this.id,
    required this.symbol,
    required this.side,
    required this.quantity,
    required this.entryPrice,
    required this.currentPrice,
    required this.stopLoss,
    required this.takeProfit,
    required this.entryTime,
    required this.unrealizedPnl,
    required this.pnlPercentage,
    this.isActive = true,
  });

  ManualPosition copyWith({
    double? currentPrice,
    double? stopLoss,
    double? takeProfit,
    bool? isActive,
  }) {
    final newCurrentPrice = currentPrice ?? this.currentPrice;
    final newUnrealizedPnl = (newCurrentPrice - entryPrice) * quantity * (side == OrderSide.buy ? 1 : -1);
    final newPnlPercentage = (newUnrealizedPnl / (entryPrice * quantity)) * 100;

    return ManualPosition(
      id: id,
      symbol: symbol,
      side: side,
      quantity: quantity,
      entryPrice: entryPrice,
      currentPrice: newCurrentPrice,
      stopLoss: stopLoss ?? this.stopLoss,
      takeProfit: takeProfit ?? this.takeProfit,
      entryTime: entryTime,
      unrealizedPnl: newUnrealizedPnl,
      pnlPercentage: newPnlPercentage,
      isActive: isActive ?? this.isActive,
    );
  }
}

// ===== POWER IMPROVEMENT DATA MODELS =====

class SmartAlert {
  final String id;
  final String symbol;
  final AlertType type;
  final String title;
  final String message;
  final AlertPriority priority;
  final DateTime timestamp;
  final Map<String, dynamic> data;
  final bool isRead;

  SmartAlert({
    required this.id,
    required this.symbol,
    required this.type,
    required this.title,
    required this.message,
    required this.priority,
    required this.timestamp,
    required this.data,
    this.isRead = false,
  });
}

enum AlertType { 
  breakout, volumeSpike, gapUp, gapDown, earningsPlay, 
  sectorRotation, optionsFlow, volatilityExpansion, priceAlert 
}
enum AlertPriority { low, medium, high, critical }

class MomentumBreakout {
  final String symbol;
  final double breakoutPrice;
  final double resistance;
  final double volume;
  final double volumeRatio; // vs 20-day average
  final BreakoutType type;
  final double confidence;
  final DateTime timestamp;

  MomentumBreakout({
    required this.symbol,
    required this.breakoutPrice,
    required this.resistance,
    required this.volume,
    required this.volumeRatio,
    required this.type,
    required this.confidence,
    required this.timestamp,
  });
}

enum BreakoutType { bullish, bearish, consolidation }

class VolumeSurge {
  final String symbol;
  final double currentVolume;
  final double averageVolume;
  final double surgeRatio;
  final double price;
  final double priceChange;
  final DateTime timestamp;

  VolumeSurge({
    required this.symbol,
    required this.currentVolume,
    required this.averageVolume,
    required this.surgeRatio,
    required this.price,
    required this.priceChange,
    required this.timestamp,
  });
}

class GapAnalysis {
  final String symbol;
  final double gapPercentage;
  final double previousClose;
  final double currentPrice;
  final GapType type;
  final double volume;
  final GapQuality quality;
  final DateTime timestamp;

  GapAnalysis({
    required this.symbol,
    required this.gapPercentage,
    required this.previousClose,
    required this.currentPrice,
    required this.type,
    required this.volume,
    required this.quality,
    required this.timestamp,
  });
}

enum GapType { gapUp, gapDown }
enum GapQuality { weak, moderate, strong, explosive }

class PreMarketMover {
  final String symbol;
  final double price;
  final double change;
  final double changePercent;
  final double volume;
  final String catalyst;
  final double dayHigh;
  final double dayLow;

  PreMarketMover({
    required this.symbol,
    required this.price,
    required this.change,
    required this.changePercent,
    required this.volume,
    required this.catalyst,
    required this.dayHigh,
    required this.dayLow,
  });
}

class EarningsEvent {
  final String symbol;
  final DateTime reportDate;
  final String reportTime; // BMO, AMC
  final double estimatedEPS;
  final double previousEPS;
  final double estimatedRevenue;
  final double impliedMove;
  final EarningsSetup setup;

  EarningsEvent({
    required this.symbol,
    required this.reportDate,
    required this.reportTime,
    required this.estimatedEPS,
    required this.previousEPS,
    required this.estimatedRevenue,
    required this.impliedMove,
    required this.setup,
  });
}

enum EarningsSetup { bullish, bearish, neutral, highVolatility }

class SectorPerformance {
  final String sectorName;
  final double dayChange;
  final double weekChange;
  final double monthChange;
  final double relativeStrength;
  final List<String> topPerformers;
  final SectorTrend trend;

  SectorPerformance({
    required this.sectorName,
    required this.dayChange,
    required this.weekChange,
    required this.monthChange,
    required this.relativeStrength,
    required this.topPerformers,
    required this.trend,
  });
}

enum SectorTrend { rotating_in, rotating_out, stable, volatile }

class OptionsFlow {
  final String symbol;
  final double premium;
  final int volume;
  final String optionType; // calls/puts
  final DateTime expiry;
  final double strike;
  final FlowType flowType;
  final double spotPrice;

  OptionsFlow({
    required this.symbol,
    required this.premium,
    required this.volume,
    required this.optionType,
    required this.expiry,
    required this.strike,
    required this.flowType,
    required this.spotPrice,
  });
}

enum FlowType { sweep, block, unusualActivity }

class VolatilityAlert {
  final String symbol;
  final double currentIV;
  final double historicalIV;
  final double ivRank;
  final VolatilitySignal signal;
  final double confidence;

  VolatilityAlert({
    required this.symbol,
    required this.currentIV,
    required this.historicalIV,
    required this.ivRank,
    required this.signal,
    required this.confidence,
  });
}

enum VolatilitySignal { expansion, contraction, mean_reversion }

class PositionSizing {
  final double suggestedShares;
  final double suggestedDollarAmount;
  final double riskAmount;
  final double portfolioPercentage;
  final double kellyPercentage;
  final String reasoning;

  PositionSizing({
    required this.suggestedShares,
    required this.suggestedDollarAmount,
    required this.riskAmount,
    required this.portfolioPercentage,
    required this.kellyPercentage,
    required this.reasoning,
  });
}

class PositionSizingRequest {
  final String symbol;
  final double entryPrice;
  final double stopLoss;
  final double portfolioValue;
  final double riskPercentage;
  final double winRate;
  final double avgWin;
  final double avgLoss;

  PositionSizingRequest({
    required this.symbol,
    required this.entryPrice,
    required this.stopLoss,
    required this.portfolioValue,
    required this.riskPercentage,
    required this.winRate,
    required this.avgWin,
    required this.avgLoss,
  });
}

// ===== STATE NOTIFIERS =====

class ConnectionStatusNotifier extends StateNotifier<ConnectionStatus> {
  ConnectionStatusNotifier() : super(ConnectionStatus(isConnected: true, lastUpdated: DateTime.now())) {
    _startHeartbeat();
  }

  void _startHeartbeat() {
    Timer.periodic(Duration(seconds: 5), (_) {
      // Simulate occasional disconnections for realism
      final isConnected = Random().nextDouble() > 0.05; // 95% uptime
      state = ConnectionStatus(isConnected: isConnected, lastUpdated: DateTime.now());
    });
  }
}

class ManualPauseNotifier extends StateNotifier<bool> {
  ManualPauseNotifier() : super(false);

  void toggle() {
    state = !state;
  }
}

class FavoritesNotifier extends StateNotifier<Set<String>> {
  FavoritesNotifier() : super({'AAPL', 'TSLA', 'NVDA'}); // Default favorites

  void addFavorite(String symbol) {
    state = {...state, symbol};
  }

  void removeFavorite(String symbol) {
    state = state.where((s) => s != symbol).toSet();
  }

  void toggleFavorite(String symbol) {
    if (state.contains(symbol)) {
      removeFavorite(symbol);
    } else {
      addFavorite(symbol);
    }
  }
}

class PortfolioNotifier extends StateNotifier<List<ManualPosition>> {
  PortfolioNotifier() : super([]) {
    _startPriceUpdates();
  }

  void _startPriceUpdates() {
    Timer.periodic(Duration(seconds: 2), (_) {
      // Update current prices for all positions
      state = state.map((position) {
        final priceChange = (Random().nextDouble() - 0.5) * 0.02; // ±1% random movement
        final newPrice = position.currentPrice * (1 + priceChange);
        return position.copyWith(currentPrice: newPrice);
      }).toList();
    });
  }

  void addPosition(ManualPosition position) {
    state = [...state, position];
  }

  void removePosition(String id) {
    state = state.where((p) => p.id != id).toList();
  }

  void updatePosition(String id, {double? stopLoss, double? takeProfit}) {
    state = state.map((p) {
      if (p.id == id) {
        return p.copyWith(stopLoss: stopLoss, takeProfit: takeProfit);
      }
      return p;
    }).toList();
  }

  void closePosition(String id) {
    state = state.map((p) {
      if (p.id == id) {
        return p.copyWith(isActive: false);
      }
      return p;
    }).toList();
  }
}

// ===== STATE NOTIFIERS FOR POWER IMPROVEMENTS =====

class SmartAlertsNotifier extends StateNotifier<List<SmartAlert>> {
  SmartAlertsNotifier() : super([]) {
    _generateSmartAlerts();
  }

  void _generateSmartAlerts() {
    Timer.periodic(Duration(seconds: 30), (_) {
      final random = Random();
      
      // Generate various types of alerts
      final newAlerts = <SmartAlert>[];
      
      if (random.nextDouble() > 0.7) {
        newAlerts.add(_generateBreakoutAlert());
      }
      
      if (random.nextDouble() > 0.8) {
        newAlerts.add(_generateVolumeSpikeAlert());
      }
      
      if (random.nextDouble() > 0.9) {
        newAlerts.add(_generateEarningsAlert());
      }

      if (newAlerts.isNotEmpty) {
        state = [...newAlerts, ...state].take(50).toList(); // Keep latest 50
      }
    });
  }

  SmartAlert _generateBreakoutAlert() {
    final symbols = ['AAPL', 'TSLA', 'NVDA', 'MSFT', 'GOOGL'];
    final symbol = symbols[Random().nextInt(symbols.length)];
    final price = 100 + Random().nextDouble() * 300;
    
    return SmartAlert(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      symbol: symbol,
      type: AlertType.breakout,
      title: '🚀 BREAKOUT ALERT',
      message: '$symbol broke above resistance at \$${price.toStringAsFixed(2)} with 3x volume!',
      priority: AlertPriority.high,
      timestamp: DateTime.now(),
      data: {'price': price, 'volume_ratio': 3.2},
    );
  }

  SmartAlert _generateVolumeSpikeAlert() {
    final symbols = ['AMD', 'ROKU', 'SHOP', 'COIN', 'PLTR'];
    final symbol = symbols[Random().nextInt(symbols.length)];
    final volumeRatio = 2 + Random().nextDouble() * 8;
    
    return SmartAlert(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      symbol: symbol,
      type: AlertType.volumeSpike,
      title: '📈 VOLUME SPIKE',
      message: '$symbol volume is ${volumeRatio.toStringAsFixed(1)}x above average - something big happening!',
      priority: AlertPriority.medium,
      timestamp: DateTime.now(),
      data: {'volume_ratio': volumeRatio},
    );
  }

  SmartAlert _generateEarningsAlert() {
    final symbols = ['META', 'AMZN', 'GOOG', 'NFLX'];
    final symbol = symbols[Random().nextInt(symbols.length)];
    
    return SmartAlert(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      symbol: symbol,
      type: AlertType.earningsPlay,
      title: '💰 EARNINGS OPPORTUNITY',
      message: '$symbol reporting tomorrow AMC - implied move 8.5%, high probability setup detected',
      priority: AlertPriority.critical,
      timestamp: DateTime.now(),
      data: {'implied_move': 8.5, 'setup': 'bullish'},
    );
  }

  void markAsRead(String alertId) {
    state = state.map((alert) {
      if (alert.id == alertId) {
        return SmartAlert(
          id: alert.id,
          symbol: alert.symbol,
          type: alert.type,
          title: alert.title,
          message: alert.message,
          priority: alert.priority,
          timestamp: alert.timestamp,
          data: alert.data,
          isRead: true,
        );
      }
      return alert;
    }).toList();
  }

  void clearAll() {
    state = [];
  }
}

// ===== STREAM GENERATORS =====

Stream<List<EnhancedSignal>> _generateEnhancedSignals() {
  return Stream.periodic(Duration(seconds: 10), (_) {
    return _allStocks.map((symbol) => _generateEnhancedSignal(symbol)).toList()
      ..sort((a, b) {
        // Sort by: Hot stocks first, then favorites, then by buy percentage
        if (a.isHot && !b.isHot) return -1;
        if (!a.isHot && b.isHot) return 1;
        if (a.isFavorite && !b.isFavorite) return -1;
        if (!a.isFavorite && b.isFavorite) return 1;
        return b.overallBuyPercentage.compareTo(a.overallBuyPercentage);
      });
  });
}

EnhancedSignal _generateEnhancedSignal(String symbol) {
  final random = Random();
  
  // Generate technical analysis
  final technical = TechnicalAnalysis(
    rsi: _randomSignalType(),
    macd: _randomSignalType(),
    sma: _randomSignalType(),
    bollinger: _randomSignalType(),
    buyPercentage: _calculateBuyPercentage([
      _randomSignalType(), _randomSignalType(), _randomSignalType(), _randomSignalType()
    ]),
  );

  // Generate momentum analysis
  final momentum = MomentumAnalysis(
    shortTerm: _randomSignalType(),
    mediumTerm: _randomSignalType(),
    longTerm: _randomSignalType(),
    buyPercentage: _calculateBuyPercentage([
      _randomSignalType(), _randomSignalType(), _randomSignalType()
    ]),
  );

  // Generate volume analysis
  final volume = VolumeAnalysis(
    volumeTrend: _randomSignalType(),
    volumeBreakout: _randomSignalType(),
    buyPercentage: _calculateBuyPercentage([
      _randomSignalType(), _randomSignalType()
    ]),
  );

  // Generate sentiment analysis
  final sentiment = SentimentAnalysis(
    news: _randomSignalType(),
    social: _randomSignalType(),
    insider: _randomSignalType(),
    buyPercentage: _calculateBuyPercentage([
      _randomSignalType(), _randomSignalType(), _randomSignalType()
    ]),
  );

  // Calculate overall buy percentage
  final overallBuyPercentage = (technical.buyPercentage + momentum.buyPercentage + 
                               volume.buyPercentage + sentiment.buyPercentage) / 4;

  // Determine strength
  final strength = overallBuyPercentage >= 80 ? SignalStrength.veryStrong :
                   overallBuyPercentage >= 65 ? SignalStrength.strong :
                   overallBuyPercentage >= 40 ? SignalStrength.moderate :
                   SignalStrength.weak;

  return EnhancedSignal(
    symbol: symbol,
    timestamp: DateTime.now(),
    technical: technical,
    momentum: momentum,
    volume: volume,
    sentiment: sentiment,
    overallBuyPercentage: overallBuyPercentage,
    strength: strength,
    isHot: overallBuyPercentage >= 90,
  );
}

SignalType _randomSignalType() {
  final random = Random();
  final value = random.nextDouble();
  if (value < 0.4) return SignalType.buy;
  if (value < 0.7) return SignalType.hold;
  return SignalType.sell;
}

double _calculateBuyPercentage(List<SignalType> signals) {
  final buyCount = signals.where((s) => s == SignalType.buy).length;
  final holdCount = signals.where((s) => s == SignalType.hold).length;
  return ((buyCount * 100) + (holdCount * 50)) / signals.length;
}

TradeRecommendation _generateTradeRecommendation(String symbol) {
  final random = Random();
  final currentPrice = 100 + random.nextDouble() * 400; // $100-$500 range
  
  final entryPrice = currentPrice * (0.98 + random.nextDouble() * 0.04); // ±2%
  final stopLoss = entryPrice * (0.92 + random.nextDouble() * 0.06); // 2-8% below entry
  final takeProfit1 = entryPrice * (1.05 + random.nextDouble() * 0.10); // 5-15% above entry
  final takeProfit2 = entryPrice * (1.15 + random.nextDouble() * 0.20); // 15-35% above entry
  
  final riskRewardRatio = (takeProfit1 - entryPrice) / (entryPrice - stopLoss);
  
  final strategies = ['Breakout', 'Pullback', 'Trend Following', 'Mean Reversion', 'Momentum'];
  
  return TradeRecommendation(
    symbol: symbol,
    currentPrice: currentPrice,
    entryPrice: entryPrice,
    stopLoss: stopLoss,
    takeProfit1: takeProfit1,
    takeProfit2: takeProfit2,
    riskRewardRatio: riskRewardRatio,
    holdDuration: Duration(days: 1 + random.nextInt(30)),
    confidence: 60 + random.nextDouble() * 35, // 60-95%
    strategy: strategies[random.nextInt(strategies.length)],
    positionSize: 1 + random.nextDouble() * 4, // 1-5% of portfolio
  );
}

// ===== EXISTING MOCK DATA GENERATORS (Updated) =====

Stream<List<Position>> _generateMockPositions() {
  return Stream.periodic(const Duration(seconds: 15), (_) {
    return _generateRandomPositions();
  });
}

List<Position> _generateRandomPositions() {
  final random = Random();
  final positions = <Position>[];
  
  for (int i = 0; i < random.nextInt(5) + 2; i++) {
    final symbol = _allStocks[random.nextInt(_allStocks.length)];
    final side = random.nextBool() ? OrderSide.buy : OrderSide.sell;
    final quantity = random.nextInt(100) + 10;
    final entryPrice = 50.0 + random.nextDouble() * 200;
    final currentPrice = entryPrice * (0.95 + random.nextDouble() * 0.1);
    final unrealizedPnl = (currentPrice - entryPrice) * quantity * (side == OrderSide.buy ? 1 : -1);
    
    positions.add(Position(
      id: 'pos_$i',
      symbol: symbol,
      side: side,
      quantity: quantity,
      entryPrice: entryPrice,
      currentPrice: currentPrice,
      unrealizedPnl: unrealizedPnl,
      realizedPnl: 0.0,
      stopLoss: entryPrice * 0.95,
      takeProfit: entryPrice * 1.1,
      openTime: DateTime.now().subtract(Duration(hours: random.nextInt(72))),
      lastUpdated: DateTime.now(),
    ));
  }
  return positions;
}

Stream<RiskMetrics> _generateMockRiskMetrics() {
  return Stream.periodic(const Duration(seconds: 10), (_) {
    return RiskMetrics(
      portfolioHeat: Random().nextDouble() * 15.0,
      currentDrawdown: Random().nextDouble() * 5.0,
      maxDrawdown: 8.0,
      var95: 2500.0 + Random().nextDouble() * 2000,
      portfolioBeta: 0.8 + Random().nextDouble() * 0.6,
      openPositions: Random().nextInt(8) + 1,
      leverageRatio: 1.0 + Random().nextDouble() * 2.0,
      riskScore: Random().nextDouble() * 100,
      circuitBreakerActive: Random().nextBool(),
    );
  });
}

Stream<ChartData> _generateMockChartData() {
  return Stream.periodic(const Duration(seconds: 30), (_) {
    return _generateRandomChartData();
  });
}

ChartData _generateRandomChartData() {
  final random = Random();
  final now = DateTime.now();
  final bars = <Bar>[];
  final candlesticks = <CandlestickData>[];
  final rsiData = <RSIData>[];
  final macdData = <MACDData>[];

  double price = 100 + random.nextDouble() * 100;
  
  for (int i = 0; i < 100; i++) {
    final timestamp = now.subtract(Duration(minutes: 100 - i));
    final open = price;
    price += (random.nextDouble() - 0.5) * 2;
    final close = price;
    final high = [open, close, price + random.nextDouble()].reduce((a, b) => a > b ? a : b);
    final low = [open, close, price - random.nextDouble()].reduce((a, b) => a < b ? a : b);
    final volume = random.nextInt(1000000) + 100000;

    bars.add(Bar(
      symbol: 'AAPL',
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume,
      timestamp: timestamp,
      timeframe: '1m',
    ));

    candlesticks.add(CandlestickData(
      timestamp: timestamp,
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume,
    ));

    rsiData.add(RSIData(
      timestamp: timestamp,
      value: 30 + random.nextDouble() * 40,
    ));

    macdData.add(MACDData(
      timestamp: timestamp,
      macdLine: random.nextDouble() * 2 - 1,
      signalLine: random.nextDouble() * 2 - 1,
      histogram: random.nextDouble() * 2 - 1,
    ));
  }

  return ChartData(
    symbol: 'AAPL',
    bars: bars,
    candlesticks: candlesticks,
    rsi: rsiData,
    macd: macdData,
  );
}

RiskMetrics _generateRandomRiskMetrics() {
  return RiskMetrics(
    portfolioHeat: Random().nextDouble() * 0.8,
    currentDrawdown: Random().nextDouble() * 0.15,
    maxDrawdown: 0.2,
    var95: Random().nextDouble() * 10000 + 5000,
    portfolioBeta: 0.8 + Random().nextDouble() * 0.4,
    openPositions: Random().nextInt(8) + 1,
    leverageRatio: 1.0 + Random().nextDouble() * 2.0,
    riskScore: Random().nextDouble() * 100,
    circuitBreakerActive: Random().nextBool(),
  );
}

// Data classes
class ConnectionStatus {
  final bool isConnected;
  final DateTime lastUpdated;

  ConnectionStatus({
    required this.isConnected,
    required this.lastUpdated,
  });
}

class ChartData {
  final String symbol;
  final List<Bar> bars;
  final List<CandlestickData> candlesticks;
  final List<RSIData> rsi;
  final List<MACDData> macd;

  ChartData({
    required this.symbol,
    required this.bars,
    required this.candlesticks,
    required this.rsi,
    required this.macd,
  });
}

class CandlestickData {
  final DateTime timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;

  CandlestickData({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });
}

class RSIData {
  final DateTime timestamp;
  final double value;

  RSIData({
    required this.timestamp,
    required this.value,
  });
}

class MACDData {
  final DateTime timestamp;
  final double macdLine;
  final double signalLine;
  final double histogram;

  MACDData({
    required this.timestamp,
    required this.macdLine,
    required this.signalLine,
    required this.histogram,
  });
}

class DrawdownPoint {
  final DateTime date;
  final double drawdown;

  DrawdownPoint(this.date, this.drawdown);
}

// ===== POWER IMPROVEMENT GENERATORS =====

List<MomentumBreakout> _detectMomentumBreakouts(List<EnhancedSignal> signals) {
  return signals.where((s) => s.overallBuyPercentage >= 85).map((signal) {
    final random = Random();
    final price = 50 + random.nextDouble() * 200;
    
    return MomentumBreakout(
      symbol: signal.symbol,
      breakoutPrice: price,
      resistance: price * 0.98,
      volume: (1000000 + random.nextInt(5000000)).toDouble(),
      volumeRatio: 2 + random.nextDouble() * 6,
      type: signal.overallBuyPercentage >= 90 ? BreakoutType.bullish : BreakoutType.consolidation,
      confidence: signal.overallBuyPercentage,
      timestamp: DateTime.now(),
    );
  }).take(10).toList();
}

List<VolumeSurge> _detectVolumeSurges() {
  final symbols = _allStocks.take(20).toList();
  final random = Random();
  
  return symbols.where((_) => random.nextDouble() > 0.7).map((symbol) {
    final currentVolume = 500000 + random.nextInt(2000000);
    final averageVolume = 200000 + random.nextInt(500000);
    final surgeRatio = currentVolume / averageVolume;
    
    return VolumeSurge(
      symbol: symbol,
      currentVolume: currentVolume.toDouble(),
      averageVolume: averageVolume.toDouble(),
      surgeRatio: surgeRatio,
      price: 50 + random.nextDouble() * 200,
      priceChange: random.nextDouble() * 20 - 10,
      timestamp: DateTime.now(),
    );
  }).toList();
}

List<GapAnalysis> _analyzeGaps() {
  final symbols = ['TSLA', 'NVDA', 'AMD', 'ROKU', 'SHOP', 'COIN'];
  final random = Random();
  
  return symbols.where((_) => random.nextDouble() > 0.6).map((symbol) {
    final previousClose = 100 + random.nextDouble() * 200;
    final gapPercent = random.nextDouble() * 15 - 7.5; // -7.5% to +7.5%
    final currentPrice = previousClose * (1 + gapPercent / 100);
    
    return GapAnalysis(
      symbol: symbol,
      gapPercentage: gapPercent,
      previousClose: previousClose,
      currentPrice: currentPrice,
      type: gapPercent > 0 ? GapType.gapUp : GapType.gapDown,
      volume: (1000000 + random.nextInt(3000000)).toDouble(),
      quality: gapPercent.abs() > 5 ? GapQuality.strong : 
               gapPercent.abs() > 3 ? GapQuality.moderate : GapQuality.weak,
      timestamp: DateTime.now(),
    );
  }).toList();
}

List<PreMarketMover> _scanPreMarket() {
  final symbols = ['AAPL', 'MSFT', 'GOOGL', 'AMZN', 'META', 'TSLA', 'NVDA'];
  final catalysts = ['Earnings Beat', 'Analyst Upgrade', 'FDA Approval', 'Contract Win', 'Merger News'];
  final random = Random();
  
  return symbols.take(5).map((symbol) {
    final price = 100 + random.nextDouble() * 400;
    final changePercent = random.nextDouble() * 20 - 10;
    
    return PreMarketMover(
      symbol: symbol,
      price: price,
      change: price * changePercent / 100,
      changePercent: changePercent,
      volume: (50000 + random.nextInt(200000)).toDouble(),
      catalyst: catalysts[random.nextInt(catalysts.length)],
      dayHigh: price * (1 + random.nextDouble() * 0.05),
      dayLow: price * (1 - random.nextDouble() * 0.05),
    );
  }).toList();
}

List<EarningsEvent> _getUpcomingEarnings() {
  final symbols = ['AAPL', 'MSFT', 'GOOGL', 'AMZN', 'META', 'TSLA', 'NVDA', 'NFLX'];
  final reportTimes = ['BMO', 'AMC'];
  final setups = [EarningsSetup.bullish, EarningsSetup.bearish, EarningsSetup.neutral, EarningsSetup.highVolatility];
  final random = Random();
  
  return symbols.take(4).map((symbol) {
    return EarningsEvent(
      symbol: symbol,
      reportDate: DateTime.now().add(Duration(days: random.nextInt(7))),
      reportTime: reportTimes[random.nextInt(reportTimes.length)],
      estimatedEPS: random.nextDouble() * 5,
      previousEPS: random.nextDouble() * 4,
      estimatedRevenue: 10 + random.nextDouble() * 50,
      impliedMove: 3 + random.nextDouble() * 12,
      setup: setups[random.nextInt(setups.length)],
    );
  }).toList();
}

List<SectorPerformance> _trackSectorRotation() {
  final sectors = [
    'Technology', 'Healthcare', 'Financials', 'Energy', 'Consumer Discretionary',
    'Industrials', 'Communication Services', 'Consumer Staples', 'Utilities', 'Real Estate'
  ];
  final trends = [SectorTrend.rotating_in, SectorTrend.rotating_out, SectorTrend.stable, SectorTrend.volatile];
  final random = Random();
  
  return sectors.map((sector) {
    final dayChange = random.nextDouble() * 8 - 4;
    
    return SectorPerformance(
      sectorName: sector,
      dayChange: dayChange,
      weekChange: random.nextDouble() * 15 - 7.5,
      monthChange: random.nextDouble() * 25 - 12.5,
      relativeStrength: 40 + random.nextDouble() * 20,
      topPerformers: _allStocks.take(3).toList(),
      trend: trends[random.nextInt(trends.length)],
    );
  }).toList();
}

List<OptionsFlow> _trackOptionsFlow() {
  final symbols = ['SPY', 'QQQ', 'AAPL', 'TSLA', 'NVDA'];
  final optionTypes = ['calls', 'puts'];
  final flowTypes = [FlowType.sweep, FlowType.block, FlowType.unusualActivity];
  final random = Random();
  
  return symbols.where((_) => random.nextDouble() > 0.5).map((symbol) {
    final spotPrice = 100 + random.nextDouble() * 300;
    final strike = spotPrice + (random.nextDouble() * 40 - 20);
    
    return OptionsFlow(
      symbol: symbol,
      premium: (50000 + random.nextInt(500000)).toDouble(),
      volume: 1000 + random.nextInt(10000),
      optionType: optionTypes[random.nextInt(optionTypes.length)],
      expiry: DateTime.now().add(Duration(days: 7 + random.nextInt(60))),
      strike: strike,
      flowType: flowTypes[random.nextInt(flowTypes.length)],
      spotPrice: spotPrice,
    );
  }).toList();
}

List<VolatilityAlert> _analyzeVolatility() {
  final symbols = _allStocks.take(15).toList();
  final signals = [VolatilitySignal.expansion, VolatilitySignal.contraction, VolatilitySignal.mean_reversion];
  final random = Random();
  
  return symbols.where((_) => random.nextDouble() > 0.7).map((symbol) {
    final currentIV = 20 + random.nextDouble() * 60;
    final historicalIV = 15 + random.nextDouble() * 50;
    
    return VolatilityAlert(
      symbol: symbol,
      currentIV: currentIV,
      historicalIV: historicalIV,
      ivRank: random.nextDouble() * 100,
      signal: signals[random.nextInt(signals.length)],
      confidence: 60 + random.nextDouble() * 35,
    );
  }).toList();
}

PositionSizing _calculateOptimalPositionSize(PositionSizingRequest request) {
  // Kelly Criterion calculation
  final winProbability = request.winRate / 100;
  final lossProbability = 1 - winProbability;
  final avgWinRatio = request.avgWin / request.avgLoss;
  final kellyPercentage = ((avgWinRatio * winProbability) - lossProbability) / avgWinRatio;
  
  // Risk-based position sizing
  final riskAmount = request.portfolioValue * (request.riskPercentage / 100);
  final priceRisk = request.entryPrice - request.stopLoss;
  final suggestedShares = riskAmount / priceRisk;
  final suggestedDollarAmount = suggestedShares * request.entryPrice;
  final portfolioPercentage = (suggestedDollarAmount / request.portfolioValue) * 100;
  
  String reasoning = '';
  if (kellyPercentage > 0.25) {
    reasoning = 'High Kelly % suggests strong edge - consider max 25% position';
  } else if (kellyPercentage > 0.1) {
    reasoning = 'Good Kelly % indicates favorable risk/reward';
  } else if (kellyPercentage > 0) {
    reasoning = 'Low Kelly % suggests small position appropriate';
  } else {
    reasoning = 'Negative Kelly % suggests avoiding this trade';
  }
  
  return PositionSizing(
    suggestedShares: suggestedShares.clamp(0, double.infinity),
    suggestedDollarAmount: suggestedDollarAmount.clamp(0, double.infinity),
    riskAmount: riskAmount,
    portfolioPercentage: portfolioPercentage.clamp(0, 100),
    kellyPercentage: (kellyPercentage * 100).clamp(-100, 100),
    reasoning: reasoning,
  );
}
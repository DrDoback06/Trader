import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:redis/redis.dart';
import 'package:http/http.dart' as http;
import 'package:rxdart/rxdart.dart';
import 'dart:math';

import '../data/models.dart';
import '../config.dart';

// Connection status provider
final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  return Stream.periodic(const Duration(seconds: 5), (_) async {
    try {
      // Test Redis connection
      final redis = RedisConnection();
      final commands = await redis.connect(Env.redisHost, Env.redisPort);
      await commands.send_object(['PING']);
      redis.close();
      
      return ConnectionStatus(isConnected: true, lastUpdated: DateTime.now());
    } catch (e) {
      return ConnectionStatus(isConnected: false, lastUpdated: DateTime.now());
    }
  }).asyncMap((future) => future);
});

// Manual pause provider
final manualPauseProvider = StateNotifierProvider<ManualPauseNotifier, bool>((ref) {
  return ManualPauseNotifier();
});

class ManualPauseNotifier extends StateNotifier<bool> {
  ManualPauseNotifier() : super(false);

  void toggle() async {
    state = !state;
    
    // Send pause/resume command to risk agent via Redis
    try {
      final redis = RedisConnection();
      final commands = await redis.connect(Env.redisHost, Env.redisPort);
      
      await commands.send_object([
        'SET',
        'risk_agent_disabled',
        state ? 'true' : 'false'
      ]);
      
      redis.close();
    } catch (e) {
      print('Failed to update risk agent state: $e');
    }
  }
}

// Signals provider - streams live signals from Redis
final signalsProvider = StreamProvider<List<Signal>>((ref) {
  return Stream.periodic(Duration(seconds: 2), (index) {
    return _generateMockSignals();
  });
});

// Positions provider - streams live positions from Redis
final positionsProvider = StreamProvider<List<Position>>((ref) {
  return Stream.periodic(Duration(seconds: 3), (index) {
    return _generateMockPositions();
  });
});

// Risk metrics provider - polls risk data via HTTP
final riskMetricsProvider = StreamProvider<RiskMetrics>((ref) {
  return Stream.periodic(const Duration(seconds: 10), (_) async {
    try {
      // In a real implementation, this would call a REST endpoint
      // For now, return mock data
      return RiskMetrics(
        portfolioHeat: 8.5,
        currentDrawdown: 0.5,
        maxDrawdown: 1.2,
        var95: 2500.0,
        portfolioBeta: 1.1,
        openPositions: 3,
        leverageRatio: 1.5,
        riskScore: 75.0,
        circuitBreakerActive: false,
      );
    } catch (e) {
      throw Exception('Failed to fetch risk metrics: $e');
    }
  }).asyncMap((future) => future);
});

// Chart data provider for mock data (simplified for production build)
final chartDataProvider = FutureProvider<ChartData>((ref) async {
  // Generate mock chart data
  final symbol = ref.watch(selectedSymbolProvider);
  final now = DateTime.now();
  final bars = <Bar>[];
  final candlesticks = <CandlestickData>[];
  final rsi = <RSIData>[];
  final macd = <MACDData>[];
  
  for (int i = 0; i < 100; i++) {
    final timestamp = now.subtract(Duration(minutes: 100 - i));
    final price = 100.0 + (i % 20 - 10) * 0.5;
    
    bars.add(Bar(
      symbol: symbol,
      open: price,
      high: price + 0.5,
      low: price - 0.5,
      close: price + 0.1,
      volume: 1000 + (i % 500),
      timestamp: timestamp,
      timeframe: '1m',
    ));
    
    candlesticks.add(CandlestickData(
      timestamp: timestamp,
      open: price,
      high: price + 0.5,
      low: price - 0.5,
      close: price + 0.1,
      volume: 1000 + (i % 500),
    ));
    
    rsi.add(RSIData(
      timestamp: timestamp,
      value: 30 + (i % 40).toDouble(),
    ));
    
    macd.add(MACDData(
      timestamp: timestamp,
      macdLine: (i % 10 - 5) * 0.1,
      signalLine: (i % 8 - 4) * 0.1,
      histogram: (i % 6 - 3) * 0.05,
    ));
  }
  
  return ChartData(
    symbol: symbol,
    bars: bars,
    candlesticks: candlesticks,
    rsi: rsi,
    macd: macd,
  );
});

// Watch list provider
final watchListProvider = StateNotifierProvider<WatchListNotifier, List<String>>((ref) {
  return WatchListNotifier();
});

class WatchListNotifier extends StateNotifier<List<String>> {
  WatchListNotifier() : super(['AAPL', 'MSFT', 'GOOGL', 'TSLA', 'NVDA']);

  void addSymbol(String symbol) {
    if (!state.contains(symbol.toUpperCase())) {
      state = [...state, symbol.toUpperCase()];
    }
  }

  void removeSymbol(String symbol) {
    state = state.where((s) => s != symbol.toUpperCase()).toList();
  }

  void toggleSymbol(String symbol) {
    final upperSymbol = symbol.toUpperCase();
    if (state.contains(upperSymbol)) {
      removeSymbol(upperSymbol);
    } else {
      addSymbol(upperSymbol);
    }
  }
}

// Selected symbol provider for live chart
final selectedSymbolProvider = StateProvider<String>((ref) => 'AAPL');

// Helper function to create Redis stream
Stream<String> _createRedisStream(String channel) async* {
  try {
    final redis = RedisConnection();
    final commands = await redis.connect(Env.redisHost, Env.redisPort);
    final pubsub = PubSub(commands);
    
    pubsub.subscribe([channel]);
    
    await for (final message in pubsub.getStream()) {
      if (message is List && message.length >= 3 && message[2] is String) {
        yield message[2] as String;
      }
    }
  } catch (e) {
    print('Redis stream error for $channel: $e');
    // Retry after delay
    await Future.delayed(const Duration(seconds: 5));
    yield* _createRedisStream(channel);
  }
}

// Helper functions for mock data generation
List<double> _generateMockRsi(List<Bar> bars) {
  return bars.asMap().entries.map((entry) {
    final index = entry.key;
    final oscillation = (index % 30) / 30.0; // 0 to 1
    return 30 + oscillation * 40; // RSI between 30-70
  }).toList();
}

List<MacdData> _generateMockMacd(List<Bar> bars) {
  return bars.asMap().entries.map((entry) {
    final index = entry.key;
    final macd = (index % 20 - 10) * 0.1;
    final signal = macd * 0.8;
    final histogram = macd - signal;
    
    return MacdData(
      macd: macd,
      signal: signal,
      histogram: histogram,
    );
  }).toList();
}

// Mock data generation functions
List<Signal> _generateMockSignals() {
  final signals = <Signal>[];
  final symbols = ['AAPL', 'GOOGL', 'MSFT', 'AMZN', 'TSLA', 'NVDA'];
  final agents = ['technical', 'sentiment', 'insider', 'momentum'];
  final sides = [OrderSide.buy, OrderSide.sell];
  
  for (int i = 0; i < 5; i++) {
    signals.add(Signal(
      id: 'signal_${DateTime.now().millisecondsSinceEpoch}_$i',
      symbol: symbols[Random().nextInt(symbols.length)],
      side: sides[Random().nextInt(sides.length)],
      strength: Random().nextDouble() * 10,
      reason: 'Mock signal reason ${i + 1}',
      timestamp: DateTime.now().subtract(Duration(minutes: i * 5)),
      agent: agents[Random().nextInt(agents.length)],
      confidence: 0.7 + Random().nextDouble() * 0.3,
    ));
  }
  
  return signals;
}

List<Position> _generateMockPositions() {
  final positions = <Position>[];
  final symbols = ['AAPL', 'GOOGL', 'MSFT'];
  final sides = [OrderSide.buy, OrderSide.sell];
  
  for (int i = 0; i < symbols.length; i++) {
    final entryPrice = 100.0 + Random().nextDouble() * 200;
    final currentPrice = entryPrice + (Random().nextDouble() - 0.5) * 20;
    final quantity = (100 + Random().nextInt(400));
    final unrealizedPnl = (currentPrice - entryPrice) * quantity;
    
    positions.add(Position(
      id: 'pos_${symbols[i]}_${DateTime.now().millisecondsSinceEpoch}',
      symbol: symbols[i],
      side: sides[Random().nextInt(sides.length)],
      quantity: quantity,
      entryPrice: entryPrice,
      currentPrice: currentPrice,
      unrealizedPnl: unrealizedPnl,
      realizedPnl: Random().nextDouble() * 1000 - 500,
      stopLoss: entryPrice * 0.95,
      takeProfit: entryPrice * 1.1,
      openTime: DateTime.now().subtract(Duration(hours: i + 1)),
      lastUpdated: DateTime.now(),
    ));
  }
  
  return positions;
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

// RiskMetrics class is now imported from ../data/models.dart

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

class MacdData {
  final double macd;
  final double signal;
  final double histogram;

  MacdData({
    required this.macd,
    required this.signal,
    required this.histogram,
  });
}
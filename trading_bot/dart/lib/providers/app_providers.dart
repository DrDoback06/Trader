import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:redis/redis.dart';
import 'package:http/http.dart' as http;

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
  return _createRedisStream('signals').map((data) {
    try {
      final signalData = jsonDecode(data) as Map<String, dynamic>;
      return [Signal.fromJson(signalData)];
    } catch (e) {
      return <Signal>[];
    }
  }).scan<List<Signal>>((previous, element, index) {
    final allSignals = [...previous, ...element];
    
    // Keep only recent signals (last 100)
    if (allSignals.length > 100) {
      allSignals.removeRange(0, allSignals.length - 100);
    }
    
    // Sort by timestamp descending
    allSignals.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    return allSignals;
  }, <Signal>[]);
});

// Positions provider - streams live positions from Redis
final positionsProvider = StreamProvider<List<Position>>((ref) {
  return _createRedisStream('position_events').map((data) {
    try {
      final eventData = jsonDecode(data) as Map<String, dynamic>;
      final position = Position.fromJson(eventData['position']);
      return [position];
    } catch (e) {
      return <Position>[];
    }
  }).scan<List<Position>>((previous, element, index) {
    // Update positions list
    final positionsMap = <String, Position>{};
    
    // Add existing positions
    for (final position in previous) {
      positionsMap[position.symbol] = position;
    }
    
    // Add/update new positions
    for (final position in element) {
      positionsMap[position.symbol] = position;
    }
    
    return positionsMap.values.toList()
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
  }, <Position>[]);
});

// Risk metrics provider - polls risk data via HTTP
final riskMetricsProvider = StreamProvider<RiskMetrics>((ref) {
  return Stream.periodic(const Duration(seconds: 10), (_) async {
    try {
      // In a real implementation, this would call a REST endpoint
      // For now, return mock data
      return RiskMetrics(
        equity: 100000.0,
        drawdown: 0.5,
        maxDrawdown: 1.2,
        circuitBreakerActive: false,
        openPositions: 3,
        maxPositions: 10,
        portfolioHeat: 8.5,
        maxPortfolioHeat: 15.0,
        valueAtRisk95: 2500.0,
        portfolioBeta: 1.1,
      );
    } catch (e) {
      throw Exception('Failed to fetch risk metrics: $e');
    }
  }).asyncMap((future) => future);
});

// Chart data provider for specific symbols
final chartDataProvider = FutureProvider.family<ChartData, String>((ref, symbol) async {
  try {
    // Mock chart data - in real implementation, this would call gRPC service
    final now = DateTime.now();
    final bars = <Bar>[];
    
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
    }
    
    return ChartData(
      symbol: symbol,
      bars: bars,
      rsiData: _generateMockRsi(bars),
      macdData: _generateMockMacd(bars),
    );
  } catch (e) {
    throw Exception('Failed to fetch chart data for $symbol: $e');
  }
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
    
    await pubsub.subscribe([channel]);
    
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

// Data classes
class ConnectionStatus {
  final bool isConnected;
  final DateTime lastUpdated;

  ConnectionStatus({
    required this.isConnected,
    required this.lastUpdated,
  });
}

class RiskMetrics {
  final double equity;
  final double drawdown;
  final double maxDrawdown;
  final bool circuitBreakerActive;
  final int openPositions;
  final int maxPositions;
  final double portfolioHeat;
  final double maxPortfolioHeat;
  final double? valueAtRisk95;
  final double? portfolioBeta;

  RiskMetrics({
    required this.equity,
    required this.drawdown,
    required this.maxDrawdown,
    required this.circuitBreakerActive,
    required this.openPositions,
    required this.maxPositions,
    required this.portfolioHeat,
    required this.maxPortfolioHeat,
    this.valueAtRisk95,
    this.portfolioBeta,
  });
}

class ChartData {
  final String symbol;
  final List<Bar> bars;
  final List<double> rsiData;
  final List<MacdData> macdData;

  ChartData({
    required this.symbol,
    required this.bars,
    required this.rsiData,
    required this.macdData,
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
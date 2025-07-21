import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redis/redis.dart';
import 'package:grpc/grpc.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import '../data/models.dart';
import '../config.dart';

final _logger = Logger();

/// Real Redis connection provider
final redisProvider = Provider<RedisConnection>((ref) {
  return RedisConnection();
});

/// Real signals provider - streams from Redis
final realSignalsProvider = StreamProvider<List<Signal>>((ref) async* {
  final redis = ref.read(redisProvider);
  Command? commands;
  
  try {
    commands = await redis.connect(Env.redisHost, Env.redisPort);
    _logger.i('Connected to Redis for signals stream');
    
    final pubsub = PubSub(commands);
    await pubsub.subscribe(['signals']);
    
    List<Signal> signalBuffer = [];
    
    await for (final message in pubsub.getStream()) {
      try {
        if (message is List && message.length >= 3 && message[2] is String) {
          final signalData = jsonDecode(message[2] as String) as Map<String, dynamic>;
          final signal = Signal.fromJson(signalData);
          
          // Add to buffer and keep only recent 100 signals
          signalBuffer.add(signal);
          if (signalBuffer.length > 100) {
            signalBuffer = signalBuffer.sublist(signalBuffer.length - 100);
          }
          
          // Sort by timestamp descending
          signalBuffer.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          
          yield List<Signal>.from(signalBuffer);
          _logger.d('Received signal: ${signal.symbol} ${signal.type.name}');
        }
      } catch (e) {
        _logger.e('Error parsing signal: $e');
      }
    }
  } catch (e) {
    _logger.e('Redis signals connection error: $e');
    yield [];
  } finally {
    if (commands != null) {
      try {
        await commands.get_connection().close();
      } catch (e) {
        _logger.w('Error closing Redis connection: $e');
      }
    }
  }
});

/// Real positions provider - streams from Redis
final realPositionsProvider = StreamProvider<List<Position>>((ref) async* {
  final redis = ref.read(redisProvider);
  Command? commands;
  
  try {
    commands = await redis.connect(Env.redisHost, Env.redisPort);
    _logger.i('Connected to Redis for positions stream');
    
    final pubsub = PubSub(commands);
    await pubsub.subscribe(['position_events']);
    
    Map<String, Position> positionsMap = {};
    
    await for (final message in pubsub.getStream()) {
      try {
        if (message is List && message.length >= 3 && message[2] is String) {
          final eventData = jsonDecode(message[2] as String) as Map<String, dynamic>;
          
          if (eventData['type'] == 'position_opened' || eventData['type'] == 'position_updated') {
            final position = Position.fromJson(eventData['position']);
            positionsMap[position.symbol] = position;
          } else if (eventData['type'] == 'position_closed') {
            final symbol = eventData['symbol'] as String;
            positionsMap.remove(symbol);
          }
          
          final positions = positionsMap.values.toList()
            ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
          
          yield positions;
          _logger.d('Positions updated: ${positions.length} open positions');
        }
      } catch (e) {
        _logger.e('Error parsing position event: $e');
      }
    }
  } catch (e) {
    _logger.e('Redis positions connection error: $e');
    yield [];
  } finally {
    if (commands != null) {
      try {
        await commands.get_connection().close();
      } catch (e) {
        _logger.w('Error closing Redis connection: $e');
      }
    }
  }
});

/// Real risk metrics provider - HTTP polling + Redis events
final realRiskMetricsProvider = StreamProvider<RiskMetrics>((ref) async* {
  // Initial HTTP fetch
  yield* Stream.periodic(const Duration(seconds: 10), (_) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.restApiUrl}/risk/status'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return RiskMetrics.fromJson(data);
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _logger.e('Error fetching risk metrics: $e');
      throw Exception('Failed to fetch risk metrics: $e');
    }
  }).asyncMap((future) => future);
});

/// Real chart data provider - gRPC calls
final realChartDataProvider = FutureProvider.family<ChartData, ChartRequest>((ref, request) async {
  final channel = ClientChannel(
    'localhost',
    port: Env.taServicePort,
    options: const ChannelOptions(
      credentials: ChannelCredentials.insecure(),
    ),
  );

  try {
    final client = TechnicalAnalysisServiceClient(channel);
    
    _logger.d('Fetching chart data for ${request.symbol} ${request.timeframe}');
    
    final response = await client.getBars(GetBarsRequest(
      symbol: request.symbol,
      interval: request.timeframe,
      limit: request.limit,
    )).timeout(const Duration(seconds: 10));

    final bars = response.bars.map((bar) => Bar(
      symbol: bar.symbol,
      open: bar.open,
      high: bar.high,
      low: bar.low,
      close: bar.close,
      volume: bar.volume.toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(bar.timestamp.toInt()),
      timeframe: request.timeframe,
    )).toList();

    // Get technical indicators
    final indicators = await client.getAllIndicators(AllIndicatorsRequest(
      symbol: request.symbol,
      prices: PriceData(
        open: bars.map((b) => b.open).toList(),
        high: bars.map((b) => b.high).toList(),
        low: bars.map((b) => b.low).toList(),
        close: bars.map((b) => b.close).toList(),
        volume: bars.map((b) => b.volume).toList(),
        timestamp: bars.map((b) => b.timestamp.millisecondsSinceEpoch).toList(),
      ),
    ));

    return ChartData(
      symbol: request.symbol,
      bars: bars,
      rsiData: indicators.rsi.values,
      macdData: indicators.macd.data.map((d) => MacdData(
        macd: d.macd,
        signal: d.signal,
        histogram: d.histogram,
      )).toList(),
    );

  } catch (e) {
    _logger.e('Error fetching chart data: $e');
    throw Exception('Failed to fetch chart data: $e');
  } finally {
    await channel.shutdown();
  }
});

/// Real connection status provider - Redis ping
final realConnectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  return Stream.periodic(const Duration(seconds: 5), (_) async {
    try {
      // Test Redis connection
      final redis = RedisConnection();
      final commands = await redis.connect(Env.redisHost, Env.redisPort);
      final response = await commands.send_object(['PING']).timeout(const Duration(seconds: 2));
      await commands.get_connection().close();
      
      final isConnected = response.toString() == 'PONG';
      
      // Test gRPC connection
      bool grpcConnected = false;
      try {
        final channel = ClientChannel(
          'localhost',
          port: Env.taServicePort,
          options: const ChannelOptions(
            credentials: ChannelCredentials.insecure(),
          ),
        );
        
        final client = TechnicalAnalysisServiceClient(channel);
        await client.healthCheck(Empty()).timeout(const Duration(seconds: 2));
        await channel.shutdown();
        grpcConnected = true;
      } catch (e) {
        grpcConnected = false;
      }

      return ConnectionStatus(
        isConnected: isConnected && grpcConnected,
        lastUpdated: DateTime.now(),
        redisConnected: isConnected,
        grpcConnected: grpcConnected,
      );
    } catch (e) {
      _logger.w('Connection check failed: $e');
      return ConnectionStatus(
        isConnected: false,
        lastUpdated: DateTime.now(),
        redisConnected: false,
        grpcConnected: false,
      );
    }
  }).asyncMap((future) => future);
});

/// Enhanced manual pause provider with Redis persistence
final realManualPauseProvider = StateNotifierProvider<RealManualPauseNotifier, bool>((ref) {
  return RealManualPauseNotifier(ref.read(redisProvider));
});

class RealManualPauseNotifier extends StateNotifier<bool> {
  final RedisConnection _redis;
  Command? _commands;

  RealManualPauseNotifier(this._redis) : super(false) {
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    try {
      _commands = await _redis.connect(Env.redisHost, Env.redisPort);
      final result = await _commands!.send_object(['GET', 'risk_agent_disabled']);
      state = result?.toString() == 'true';
      _logger.d('Loaded manual pause state: $state');
    } catch (e) {
      _logger.e('Error loading manual pause state: $e');
    }
  }

  Future<void> toggle() async {
    state = !state;
    
    try {
      _commands ??= await _redis.connect(Env.redisHost, Env.redisPort);
      
      // Set the pause state in Redis
      await _commands!.send_object([
        'SET',
        'risk_agent_disabled',
        state ? 'true' : 'false'
      ]);

      // Publish event for immediate notification
      await _commands!.send_object([
        'PUBLISH',
        'risk_events',
        jsonEncode({
          'type': state ? 'manual_pause_enabled' : 'manual_pause_disabled',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ]);

      _logger.i('Manual pause ${state ? 'enabled' : 'disabled'}');
    } catch (e) {
      _logger.e('Failed to update manual pause state: $e');
      // Revert state on error
      state = !state;
    }
  }

  @override
  void dispose() {
    _commands?.get_connection().close();
    super.dispose();
  }
}

// Data classes for enhanced functionality
class ConnectionStatus {
  final bool isConnected;
  final DateTime lastUpdated;
  final bool redisConnected;
  final bool grpcConnected;

  ConnectionStatus({
    required this.isConnected,
    required this.lastUpdated,
    required this.redisConnected,
    required this.grpcConnected,
  });
}

class ChartRequest {
  final String symbol;
  final String timeframe;
  final int limit;

  ChartRequest({
    required this.symbol,
    required this.timeframe,
    this.limit = 200,
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

// Mock gRPC service classes for compilation
class TechnicalAnalysisServiceClient {
  TechnicalAnalysisServiceClient(ClientChannel channel);
  
  Future<GetBarsResponse> getBars(GetBarsRequest request) async {
    throw UnimplementedError('Replace with real gRPC generated client');
  }
  
  Future<AllIndicatorsResponse> getAllIndicators(AllIndicatorsRequest request) async {
    throw UnimplementedError('Replace with real gRPC generated client');
  }
  
  Future<Empty> healthCheck(Empty request) async {
    throw UnimplementedError('Replace with real gRPC generated client');
  }
}

class GetBarsRequest {
  final String symbol;
  final String interval;
  final int limit;
  
  GetBarsRequest({required this.symbol, required this.interval, required this.limit});
}

class GetBarsResponse {
  final List<GrpcBar> bars;
  GetBarsResponse({required this.bars});
}

class GrpcBar {
  final String symbol;
  final double open, high, low, close;
  final int volume;
  final int timestamp;
  
  GrpcBar({
    required this.symbol,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.timestamp,
  });
}

class AllIndicatorsRequest {
  final String symbol;
  final PriceData prices;
  
  AllIndicatorsRequest({required this.symbol, required this.prices});
}

class AllIndicatorsResponse {
  final RsiData rsi;
  final MacdIndicatorData macd;
  
  AllIndicatorsResponse({required this.rsi, required this.macd});
}

class RsiData {
  final List<double> values;
  RsiData({required this.values});
}

class MacdIndicatorData {
  final List<GrpcMacdData> data;
  MacdIndicatorData({required this.data});
}

class GrpcMacdData {
  final double macd, signal, histogram;
  GrpcMacdData({required this.macd, required this.signal, required this.histogram});
}

class PriceData {
  final List<double> open, high, low, close, volume;
  final List<int> timestamp;
  
  PriceData({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.timestamp,
  });
}

class Empty {}
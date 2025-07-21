import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:redis/redis.dart';
import 'package:grpc/grpc.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/polygon_ws.dart';
import '../ta/ta_service.dart';
import '../utils/logger.dart';

/// Technical analysis agent that generates trading signals based on RSI, MACD, Bollinger Bands, and volume analysis
class TechnicalAgent {
  static const String agentName = 'technical_agent';
  
  final Logger _logger = Logger();
  final Map<String, List<Bar>> _barHistory = {};
  final Map<String, TechnicalIndicators> _indicators = {};
  final Map<String, double> _volumeHistory = {};
  
  late RedisConnection _redis;
  late Command _redisCommands;
  late TechnicalAnalysisService _taService;
  
  StreamSubscription? _barSubscription;
  Timer? _heartbeatTimer;
  
  /// Maximum bars to keep in memory per symbol
  static const int maxBarsPerSymbol = 200;
  
  /// Volume spike threshold (2x average)
  static const double volumeSpikeThreshold = 2.0;
  
  TechnicalAgent();
  
  /// Isolate entry point for the technical agent
  static void isolateEntryPoint(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);
    
    final agent = TechnicalAgent();
    
    receivePort.listen((message) async {
      if (message is Map<String, dynamic>) {
        switch (message['action']) {
          case 'start':
            await agent.start();
            break;
          case 'stop':
            await agent.stop();
            break;
          case 'ping':
            mainSendPort.send({'type': 'pong', 'agent': agentName});
            break;
          case 'analyze_symbol':
            final symbol = message['symbol'] as String;
            await agent._analyzeSymbol(symbol);
            break;
        }
      }
    });
  }
  
  /// Start the technical agent
  Future<void> start() async {
    try {
      _logger.i('Starting Technical Agent...');
      
      // Initialize Redis connection
      await _initializeRedis();
      
      // Initialize TA service
      await _initializeTaService();
      
      // Subscribe to market data
      _subscribeToMarketData();
      
      // Start heartbeat
      _startHeartbeat();
      
      _logger.i('Technical Agent started successfully');
      
    } catch (e) {
      _logger.e('Failed to start Technical Agent: $e');
      rethrow;
    }
  }
  
  /// Stop the technical agent
  Future<void> stop() async {
    _logger.i('Stopping Technical Agent...');
    
    await _barSubscription?.cancel();
    _heartbeatTimer?.cancel();
    
    try {
      await _taService.shutdown();
    } catch (e) {
      _logger.w('Error shutting down TA service: $e');
    }
    
    try {
      _redis.close();
    } catch (e) {
      _logger.w('Error closing Redis connection: $e');
    }
    
    _logger.i('Technical Agent stopped');
  }
  
  Future<void> _initializeRedis() async {
    _redis = RedisConnection();
    _redisCommands = await _redis.connect(Env.redisHost, Env.redisPort);
    _logger.i('Technical Agent connected to Redis');
  }
  
  Future<void> _initializeTaService() async {
    final channel = ClientChannel(
      'localhost',
      port: Env.taServicePort,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
      ),
    );
    
    _taService = TechnicalAnalysisService(channel);
    _logger.i('Technical Agent connected to TA service');
  }
  
  void _subscribeToMarketData() {
    // Subscribe to bars from Redis (published by Polygon WS client)
    _barSubscription = _listenToRedisChannel('bars').listen((data) {
      try {
        final barData = jsonDecode(data) as Map<String, dynamic>;
        final bar = Bar.fromJson(barData);
        _processBar(bar);
      } catch (e) {
        _logger.e('Error processing bar data: $e');
      }
    });
    
    _logger.i('Technical Agent subscribed to market data');
  }
  
  Stream<String> _listenToRedisChannel(String channel) async* {
    final pubsub = PubSub(_redisCommands);
    await pubsub.subscribe([channel]);
    
    await for (final message in pubsub.getStream()) {
      if (message is List && message.length >= 3 && message[2] is String) {
        yield message[2] as String;
      }
    }
  }
  
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _logger.d('Technical Agent heartbeat - tracking ${_barHistory.length} symbols');
    });
  }
  
  /// Process incoming bar data
  Future<void> _processBar(Bar bar) async {
    try {
      // Add bar to history
      _addBarToHistory(bar);
      
      // Update volume tracking
      _updateVolumeHistory(bar);
      
      // Check if we have enough data for analysis
      final bars = _barHistory[bar.symbol];
      if (bars == null || bars.length < 50) {
        return; // Need more data
      }
      
      // Perform technical analysis
      await _analyzeSymbol(bar.symbol);
      
    } catch (e) {
      _logger.e('Error processing bar for ${bar.symbol}: $e');
    }
  }
  
  void _addBarToHistory(Bar bar) {
    _barHistory.putIfAbsent(bar.symbol, () => <Bar>[]);
    final bars = _barHistory[bar.symbol]!;
    
    // Add new bar
    bars.add(bar);
    
    // Keep only the most recent bars
    if (bars.length > maxBarsPerSymbol) {
      bars.removeRange(0, bars.length - maxBarsPerSymbol);
    }
    
    // Sort by timestamp to ensure chronological order
    bars.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }
  
  void _updateVolumeHistory(Bar bar) {
    final symbol = bar.symbol;
    final bars = _barHistory[symbol];
    if (bars == null || bars.length < 20) return;
    
    // Calculate 20-period volume average
    final recentBars = bars.skip(bars.length - 20).toList();
    final avgVolume = recentBars.map((b) => b.volume).reduce((a, b) => a + b) / 20;
    
    _volumeHistory[symbol] = avgVolume;
  }
  
  /// Analyze a symbol and generate signals
  Future<void> _analyzeSymbol(String symbol) async {
    try {
      final bars = _barHistory[symbol];
      if (bars == null || bars.length < 50) return;
      
      // Get technical indicators
      final indicators = await _getTechnicalIndicators(symbol, bars);
      if (indicators == null) return;
      
      _indicators[symbol] = indicators;
      
      // Generate signals based on indicators
      final signals = _generateSignals(symbol, bars.last, indicators);
      
      // Publish signals
      for (final signal in signals) {
        await _publishSignal(signal);
      }
      
    } catch (e) {
      _logger.e('Error analyzing symbol $symbol: $e');
    }
  }
  
  /// Get technical indicators from TA service
  Future<TechnicalIndicators?> _getTechnicalIndicators(
    String symbol, 
    List<Bar> bars,
  ) async {
    try {
      final priceData = PriceData(
        open: bars.map((b) => b.open).toList(),
        high: bars.map((b) => b.high).toList(),
        low: bars.map((b) => b.low).toList(),
        close: bars.map((b) => b.close).toList(),
        volume: bars.map((b) => b.volume).toList(),
        timestamp: bars.map((b) => b.timestamp.millisecondsSinceEpoch).toList(),
      );
      
      final request = AllIndicatorsRequest(
        symbol: symbol,
        prices: priceData,
      );
      
      final response = await _taService.getAllIndicators(request);
      
      return TechnicalIndicators(
        rsi: response.rsi.currentRsi > 0 ? response.rsi.currentRsi : null,
        macd: response.macd.currentMacd != 0 ? MacdIndicator(
          macd: response.macd.currentMacd,
          signal: response.macd.currentSignal,
          histogram: response.macd.currentHistogram,
        ) : null,
        bollinger: response.bollinger.currentUpper > 0 ? BollingerBands(
          upper: response.bollinger.currentUpper,
          middle: response.bollinger.currentMiddle,
          lower: response.bollinger.currentLower,
          bandwidth: response.bollinger.bandwidth,
        ) : null,
        atr: response.atr.currentAtr > 0 ? response.atr.currentAtr : null,
        sma20: response.movingAverages.results[20]?.currentValue,
        sma50: response.movingAverages.results[50]?.currentValue,
        volumeAvg: _volumeHistory[symbol],
      );
      
    } catch (e) {
      _logger.e('Error getting technical indicators for $symbol: $e');
      return null;
    }
  }
  
  /// Generate trading signals based on technical analysis
  List<Signal> _generateSignals(
    String symbol, 
    Bar currentBar, 
    TechnicalIndicators indicators,
  ) {
    final signals = <Signal>[];
    final currentPrice = currentBar.close;
    final currentVolume = currentBar.volume;
    
    // RSI signals
    if (indicators.rsi != null) {
      if (indicators.rsi! < AppConfig.rsiOversold) {
        final strength = (AppConfig.rsiOversold - indicators.rsi!) / AppConfig.rsiOversold;
        signals.add(Signal.buy(
          symbol: symbol,
          strength: strength.clamp(0.0, 1.0),
          source: agentName,
          metadata: {
            'rsi': indicators.rsi!,
            'reason': 'RSI oversold',
          },
        ));
      } else if (indicators.rsi! > AppConfig.rsiOverbought) {
        final strength = (indicators.rsi! - AppConfig.rsiOverbought) / (100 - AppConfig.rsiOverbought);
        signals.add(Signal.sell(
          symbol: symbol,
          strength: strength.clamp(0.0, 1.0),
          source: agentName,
          metadata: {
            'rsi': indicators.rsi!,
            'reason': 'RSI overbought',
          },
        ));
      }
    }
    
    // MACD signals
    if (indicators.macd != null) {
      if (indicators.macd!.isBullishCrossover) {
        signals.add(Signal.buy(
          symbol: symbol,
          strength: 0.7,
          source: agentName,
          metadata: {
            'macd': indicators.macd!.macd,
            'signal': indicators.macd!.signal,
            'reason': 'MACD bullish crossover',
          },
        ));
      } else if (indicators.macd!.isBearishCrossover) {
        signals.add(Signal.sell(
          symbol: symbol,
          strength: 0.7,
          source: agentName,
          metadata: {
            'macd': indicators.macd!.macd,
            'signal': indicators.macd!.signal,
            'reason': 'MACD bearish crossover',
          },
        ));
      }
    }
    
    // Bollinger Bands signals
    if (indicators.bollinger != null) {
      if (indicators.bollinger!.isPriceBelowLower(currentPrice)) {
        signals.add(Signal.buy(
          symbol: symbol,
          strength: 0.6,
          source: agentName,
          metadata: {
            'price': currentPrice,
            'lowerBand': indicators.bollinger!.lower,
            'reason': 'Price below Bollinger lower band',
          },
        ));
      } else if (indicators.bollinger!.isPriceAboveUpper(currentPrice)) {
        signals.add(Signal.sell(
          symbol: symbol,
          strength: 0.6,
          source: agentName,
          metadata: {
            'price': currentPrice,
            'upperBand': indicators.bollinger!.upper,
            'reason': 'Price above Bollinger upper band',
          },
        ));
      }
    }
    
    // Volume spike signal
    final avgVolume = indicators.volumeAvg;
    if (avgVolume != null && avgVolume > 0) {
      final volumeRatio = currentVolume / avgVolume;
      if (volumeRatio > volumeSpikeThreshold) {
        final strength = (volumeRatio / volumeSpikeThreshold / 2).clamp(0.0, 0.5);
        signals.add(Signal.buy(
          symbol: symbol,
          strength: strength,
          source: agentName,
          metadata: {
            'volume': currentVolume,
            'avgVolume': avgVolume,
            'volumeRatio': volumeRatio,
            'reason': 'Volume spike detected',
          },
        ));
      }
    }
    
    // Multi-condition strong signals
    if (indicators.rsi != null && 
        indicators.macd != null && 
        indicators.bollinger != null &&
        avgVolume != null) {
      
      // Strong buy signal
      if (indicators.rsi! < 30 && 
          indicators.macd!.isBullishCrossover &&
          currentPrice > indicators.bollinger!.lower &&
          currentVolume > avgVolume * volumeSpikeThreshold) {
        signals.add(Signal.buy(
          symbol: symbol,
          strength: 0.9,
          source: agentName,
          metadata: {
            'rsi': indicators.rsi!,
            'macd': indicators.macd!.macd,
            'price': currentPrice,
            'volume': currentVolume,
            'reason': 'Strong multi-indicator buy signal',
          },
        ));
      }
      
      // Strong sell signal  
      if (indicators.rsi! > 70 && 
          indicators.macd!.isBearishCrossover &&
          currentPrice < indicators.bollinger!.upper) {
        signals.add(Signal.sell(
          symbol: symbol,
          strength: 0.8,
          source: agentName,
          metadata: {
            'rsi': indicators.rsi!,
            'macd': indicators.macd!.macd,
            'price': currentPrice,
            'reason': 'Strong multi-indicator sell signal',
          },
        ));
      }
    }
    
    return signals;
  }
  
  /// Publish signal to Redis
  Future<void> _publishSignal(Signal signal) async {
    try {
      final signalJson = jsonEncode(signal.toJson());
      await _redisCommands.send_object(['PUBLISH', 'signals', signalJson]);
      
      AppLogger.instance.signal(
        agentName,
        signal.symbol,
        signal.type.name.toUpperCase(),
        signal.strength,
        reason: signal.metadata['reason'] as String?,
      );
      
    } catch (e) {
      _logger.e('Error publishing signal: $e');
    }
  }
  
  /// Get current indicators for a symbol (for testing/debugging)
  TechnicalIndicators? getCurrentIndicators(String symbol) {
    return _indicators[symbol];
  }
  
  /// Get bar history for a symbol (for testing)
  List<Bar>? getBarHistory(String symbol) {
    return _barHistory[symbol];
  }
}
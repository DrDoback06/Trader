import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:redis/redis.dart';
import 'package:grpc/grpc.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/alpha_vantage_client.dart';
import '../utils/logger.dart';

/// Sentiment analysis agent that generates signals based on news sentiment analysis
class SentimentAgent {
  static const String agentName = 'sentiment_agent';
  
  final Logger _logger = Logger();
  final Map<String, double> _sentimentCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  
  late RedisConnection _redis;
  late Command _redisCommands;
  late AlphaVantageClient _alphaVantageClient;
  
  Timer? _refreshTimer;
  Timer? _heartbeatTimer;
  
  /// Cache duration for sentiment scores (5 minutes)
  static const Duration cacheDuration = Duration(minutes: 5);
  
  /// Sentiment thresholds
  static const double bullishThreshold = 0.25;
  static const double bearishThreshold = -0.4;
  static const double strongBullishThreshold = 0.6;
  static const double strongBearishThreshold = -0.6;
  
  /// Refresh interval for sentiment data
  static const Duration refreshInterval = Duration(minutes: 10);
  
  SentimentAgent();
  
  /// Isolate entry point for the sentiment agent
  static void isolateEntryPoint(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);
    
    final agent = SentimentAgent();
    
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
          case 'refresh_sentiment':
            await agent._refreshAllSentiment();
            break;
        }
      }
    });
  }
  
  /// Start the sentiment agent
  Future<void> start() async {
    try {
      _logger.i('Starting Sentiment Agent...');
      
      // Initialize Redis connection
      await _initializeRedis();
      
      // Initialize Alpha Vantage client
      _initializeAlphaVantage();
      
      // Start periodic refresh
      _startPeriodicRefresh();
      
      // Start heartbeat
      _startHeartbeat();
      
      _logger.i('Sentiment Agent started successfully');
      
    } catch (e) {
      _logger.e('Failed to start Sentiment Agent: $e');
      rethrow;
    }
  }
  
  /// Stop the sentiment agent
  Future<void> stop() async {
    _logger.i('Stopping Sentiment Agent...');
    
    _refreshTimer?.cancel();
    _heartbeatTimer?.cancel();
    
    try {
      _redis.close();
    } catch (e) {
      _logger.w('Error closing Redis connection: $e');
    }
    
    _logger.i('Sentiment Agent stopped');
  }
  
  Future<void> _initializeRedis() async {
    _redis = RedisConnection();
    _redisCommands = await _redis.connect(Env.redisHost, Env.redisPort);
    _logger.i('Sentiment Agent connected to Redis');
  }
  
  void _initializeAlphaVantage() {
    _alphaVantageClient = alphaVantageClient;
    _logger.i('Sentiment Agent initialized Alpha Vantage client');
  }
  
  void _startPeriodicRefresh() {
    _refreshTimer = Timer.periodic(refreshInterval, (timer) {
      _refreshAllSentiment();
    });
    
    // Initial refresh
    _refreshAllSentiment();
    
    _logger.i('Sentiment Agent started periodic refresh');
  }
  
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _logger.d('Sentiment Agent heartbeat - cached ${_sentimentCache.length} symbols');
    });
  }
  
  /// Get sentiment score for a symbol
  Future<double?> getSentimentScore(String symbol) async {
    try {
      // Check cache first
      final cachedScore = _getCachedSentiment(symbol);
      if (cachedScore != null) {
        return cachedScore;
      }
      
      // Fetch fresh sentiment data
      final sentiment = await _fetchSentimentFromAlphaVantage(symbol);
      if (sentiment != null) {
        _cacheSentiment(symbol, sentiment);
        return sentiment;
      }
      
      return null;
      
    } catch (e) {
      _logger.e('Error getting sentiment for $symbol: $e');
      return null;
    }
  }
  
  /// Get cached sentiment if still valid
  double? _getCachedSentiment(String symbol) {
    final timestamp = _cacheTimestamps[symbol];
    if (timestamp == null) return null;
    
    final age = DateTime.now().difference(timestamp);
    if (age > cacheDuration) {
      // Remove expired cache entry
      _sentimentCache.remove(symbol);
      _cacheTimestamps.remove(symbol);
      return null;
    }
    
    return _sentimentCache[symbol];
  }
  
  /// Cache sentiment score with timestamp
  void _cacheSentiment(String symbol, double sentiment) {
    _sentimentCache[symbol] = sentiment;
    _cacheTimestamps[symbol] = DateTime.now();
  }
  
  /// Fetch sentiment from Alpha Vantage
  Future<double?> _fetchSentimentFromAlphaVantage(String symbol) async {
    try {
      final newsItems = await _alphaVantageClient.getNewsSentiment(symbol, limit: 20);
      
      if (newsItems.isEmpty) {
        _logger.d('No news found for $symbol');
        return null;
      }
      
      // Calculate aggregate sentiment
      final sentimentScores = newsItems
          .where((item) => item.sentimentScore != null)
          .map((item) => item.sentimentScore!)
          .toList();
      
      if (sentimentScores.isEmpty) {
        _logger.d('No sentiment scores available for $symbol');
        return null;
      }
      
      // Weight recent news more heavily
      final weightedSum = sentimentScores.asMap().entries.map((entry) {
        final index = entry.key;
        final score = entry.value;
        final weight = 1.0 - (index / sentimentScores.length * 0.5); // Recent news has higher weight
        return score * weight;
      }).reduce((a, b) => a + b);
      
      final totalWeight = sentimentScores.asMap().entries.map((entry) {
        final index = entry.key;
        return 1.0 - (index / sentimentScores.length * 0.5);
      }).reduce((a, b) => a + b);
      
      final aggregateSentiment = weightedSum / totalWeight;
      
      _logger.d('Sentiment for $symbol: ${aggregateSentiment.toStringAsFixed(3)} (from ${sentimentScores.length} articles)');
      
      return aggregateSentiment;
      
    } catch (e) {
      _logger.e('Error fetching sentiment for $symbol: $e');
      return null;
    }
  }
  
  /// Analyze a symbol and generate sentiment-based signals
  Future<void> _analyzeSymbol(String symbol) async {
    try {
      final sentiment = await getSentimentScore(symbol);
      if (sentiment == null) {
        _logger.d('No sentiment data available for $symbol');
        return;
      }
      
      final signals = _generateSentimentSignals(symbol, sentiment);
      
      // Publish signals
      for (final signal in signals) {
        await _publishSignal(signal);
      }
      
    } catch (e) {
      _logger.e('Error analyzing sentiment for $symbol: $e');
    }
  }
  
  /// Generate trading signals based on sentiment
  List<Signal> _generateSentimentSignals(String symbol, double sentiment) {
    final signals = <Signal>[];
    
    // Strong bullish sentiment
    if (sentiment >= strongBullishThreshold) {
      signals.add(Signal.buy(
        symbol: symbol,
        strength: 0.8,
        source: agentName,
        metadata: {
          'sentiment': sentiment,
          'reason': 'Strong bullish sentiment',
          'threshold': strongBullishThreshold,
        },
      ));
    }
    // Bullish sentiment
    else if (sentiment >= bullishThreshold) {
      final strength = (sentiment - bullishThreshold) / (strongBullishThreshold - bullishThreshold) * 0.6;
      signals.add(Signal.buy(
        symbol: symbol,
        strength: strength.clamp(0.2, 0.6),
        source: agentName,
        metadata: {
          'sentiment': sentiment,
          'reason': 'Bullish sentiment',
          'threshold': bullishThreshold,
        },
      ));
    }
    // Strong bearish sentiment (block signal)
    else if (sentiment <= strongBearishThreshold) {
      signals.add(Signal(
        symbol: symbol,
        type: SignalType.sell,
        strength: 0.9,
        source: agentName,
        timestamp: DateTime.now(),
        metadata: {
          'sentiment': sentiment,
          'reason': 'Strong bearish sentiment - block trades',
          'threshold': strongBearishThreshold,
          'block_trading': true,
        },
      ));
    }
    // Bearish sentiment (caution signal)
    else if (sentiment <= bearishThreshold) {
      final strength = (bearishThreshold - sentiment) / (bearishThreshold - strongBearishThreshold) * 0.5;
      signals.add(Signal(
        symbol: symbol,
        type: SignalType.sell,
        strength: strength.clamp(0.2, 0.5),
        source: agentName,
        timestamp: DateTime.now(),
        metadata: {
          'sentiment': sentiment,
          'reason': 'Bearish sentiment - reduce exposure',
          'threshold': bearishThreshold,
        },
      ));
    }
    
    return signals;
  }
  
  /// Refresh sentiment for all symbols we're tracking
  Future<void> _refreshAllSentiment() async {
    try {
      _logger.d('Refreshing sentiment for all tracked symbols');
      
      // Get list of active symbols from Redis (symbols that have recent bars)
      final activeSymbols = await _getActiveSymbols();
      
      // Refresh sentiment for each symbol (with rate limiting)
      for (final symbol in activeSymbols) {
        try {
          await _analyzeSymbol(symbol);
          
          // Rate limiting - Alpha Vantage free tier is 5 requests per minute
          await Future.delayed(const Duration(seconds: 15));
          
        } catch (e) {
          _logger.w('Error refreshing sentiment for $symbol: $e');
        }
      }
      
      _logger.i('Completed sentiment refresh for ${activeSymbols.length} symbols');
      
    } catch (e) {
      _logger.e('Error during sentiment refresh: $e');
    }
  }
  
  /// Get list of active symbols from Redis
  Future<List<String>> _getActiveSymbols() async {
    try {
      // In a real implementation, we might query Redis for recently active symbols
      // For now, return a list of major stocks to track
      return [
        'AAPL', 'MSFT', 'GOOGL', 'AMZN', 'TSLA',
        'NVDA', 'META', 'NFLX', 'ADBE', 'CRM',
        'SPY', 'QQQ', 'IWM', 'DIA', 'VTI',
      ];
    } catch (e) {
      _logger.e('Error getting active symbols: $e');
      return [];
    }
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
  
  /// Get current sentiment for a symbol (for testing/debugging)
  double? getCurrentSentiment(String symbol) {
    return _sentimentCache[symbol];
  }
  
  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    final now = DateTime.now();
    final validEntries = _cacheTimestamps.entries
        .where((entry) => now.difference(entry.value) <= cacheDuration)
        .length;
    
    return {
      'total_cached': _sentimentCache.length,
      'valid_entries': validEntries,
      'cache_duration_minutes': cacheDuration.inMinutes,
    };
  }
  
  /// Clear expired cache entries
  void _cleanupCache() {
    final now = DateTime.now();
    final expiredSymbols = <String>[];
    
    for (final entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) > cacheDuration) {
        expiredSymbols.add(entry.key);
      }
    }
    
    for (final symbol in expiredSymbols) {
      _sentimentCache.remove(symbol);
      _cacheTimestamps.remove(symbol);
    }
    
    if (expiredSymbols.isNotEmpty) {
      _logger.d('Cleaned up ${expiredSymbols.length} expired sentiment cache entries');
    }
  }
}
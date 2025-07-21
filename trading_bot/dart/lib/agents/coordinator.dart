import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:logger/logger.dart';
import 'package:redis/redis.dart';
import 'package:postgres/postgres.dart';

import '../config.dart';
import '../data/models.dart';
import '../utils/logger.dart';

/// Coordinates signals from all agents and makes trading decisions
class AgentCoordinator {
  static AgentCoordinator? _instance;
  static AgentCoordinator get instance => _instance ??= AgentCoordinator._();
  
  AgentCoordinator._();
  
  final Logger _logger = Logger();
  final Map<String, List<Signal>> _recentSignals = {};
  final Map<String, TradeIntent> _activeIntents = {};
  
  late RedisConnection _redis;
  late Command _redisCommands;
  late Connection _postgres;
  
  StreamSubscription? _signalSubscription;
  Timer? _cleanupTimer;
  Timer? _heartbeatTimer;
  
  bool _isInitialized = false;
  
  /// Time window to consider signals for consensus
  static const Duration signalWindow = Duration(minutes: 15);
  
  /// Minimum number of agents that must agree for a trade
  static const int minAgentConsensus = 2;
  
  /// Minimum total weighted strength for a trade
  static const double minConsensusStrength = AppConfig.signalConsensusThreshold; // 1.2
  
  /// Cooldown period between trades on the same symbol
  static const Duration tradeCooldown = Duration(minutes: 30);
  
  /// Initialize the coordinator
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _logger.i('Initializing Agent Coordinator...');
      
      // Initialize connections
      await _initializeRedis();
      await _initializePostgres();
      
      // Create database tables
      await _createTables();
      
      // Subscribe to signals
      _subscribeToSignals();
      
      // Start cleanup timer
      _startCleanupTimer();
      
      // Start heartbeat
      _startHeartbeat();
      
      _isInitialized = true;
      _logger.i('Agent Coordinator initialized successfully');
      
    } catch (e) {
      _logger.e('Failed to initialize Agent Coordinator: $e');
      rethrow;
    }
  }
  
  Future<void> _initializeRedis() async {
    _redis = RedisConnection();
    _redisCommands = await _redis.connect(Env.redisHost, Env.redisPort);
    _logger.i('Agent Coordinator connected to Redis');
  }
  
  Future<void> _initializePostgres() async {
    _postgres = await Connection.open(
      Endpoint(
        host: Env.postgresHost,
        port: Env.postgresPort,
        database: Env.postgresDb,
        username: Env.postgresUser,
        password: Env.postgresPassword,
      ),
    );
    _logger.i('Agent Coordinator connected to PostgreSQL');
  }
  
  Future<void> _createTables() async {
    const createTablesSql = '''
      CREATE TABLE IF NOT EXISTS signals (
        id SERIAL PRIMARY KEY,
        symbol VARCHAR(10) NOT NULL,
        agent VARCHAR(50) NOT NULL,
        signal_type VARCHAR(10) NOT NULL,
        strength DECIMAL(5,4) NOT NULL,
        metadata JSONB,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE INDEX IF NOT EXISTS idx_signals_symbol_time 
      ON signals(symbol, created_at DESC);
      
      CREATE INDEX IF NOT EXISTS idx_signals_agent_time 
      ON signals(agent, created_at DESC);
      
      CREATE TABLE IF NOT EXISTS trade_decisions (
        id SERIAL PRIMARY KEY,
        symbol VARCHAR(10) NOT NULL,
        side VARCHAR(10) NOT NULL,
        strength DECIMAL(5,4) NOT NULL,
        percent_equity DECIMAL(8,6) NOT NULL,
        stop_loss DECIMAL(10,4),
        take_profit DECIMAL(10,4),
        trailing_stop DECIMAL(8,6),
        contributing_agents TEXT[] NOT NULL,
        signal_count INTEGER NOT NULL,
        decision_metadata JSONB,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE INDEX IF NOT EXISTS idx_trade_decisions_symbol_time 
      ON trade_decisions(symbol, created_at DESC);
    ''';
    
    await _postgres.execute(createTablesSql);
    _logger.i('Coordinator database tables created/verified');
  }
  
  void _subscribeToSignals() {
    _signalSubscription = _listenToRedisChannel('signals').listen((data) {
      try {
        final signalData = jsonDecode(data) as Map<String, dynamic>;
        final signal = Signal.fromJson(signalData);
        _processSignal(signal);
      } catch (e) {
        _logger.e('Error processing signal: $e');
      }
    });
    
    _logger.i('Agent Coordinator subscribed to signals');
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
  
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _cleanupOldSignals();
      _cleanupOldIntents();
    });
  }
  
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      final symbolCount = _recentSignals.length;
      final intentCount = _activeIntents.length;
      _logger.d('Coordinator heartbeat - $symbolCount symbols, $intentCount active intents');
    });
  }
  
  /// Process incoming signal from agents
  Future<void> _processSignal(Signal signal) async {
    try {
      _logger.d('Processing signal: ${signal.source} -> ${signal.symbol} ${signal.type.name} (${signal.strength})');
      
      // Store signal in database
      await _storeSignal(signal);
      
      // Add to recent signals
      _recentSignals.putIfAbsent(signal.symbol, () => <Signal>[]);
      _recentSignals[signal.symbol]!.add(signal);
      
      // Check for consensus
      await _checkConsensus(signal.symbol);
      
    } catch (e) {
      _logger.e('Error processing signal for ${signal.symbol}: $e');
    }
  }
  
  /// Store signal in database
  Future<void> _storeSignal(Signal signal) async {
    try {
      const insertSql = '''
        INSERT INTO signals (symbol, agent, signal_type, strength, metadata)
        VALUES (\$1, \$2, \$3, \$4, \$5)
      ''';
      
      await _postgres.execute(insertSql, parameters: [
        signal.symbol,
        signal.source,
        signal.type.name,
        signal.strength,
        jsonEncode(signal.metadata),
      ]);
      
    } catch (e) {
      _logger.e('Error storing signal: $e');
    }
  }
  
  /// Check if signals for a symbol reach consensus for a trade
  Future<void> _checkConsensus(String symbol) async {
    try {
      // Get recent signals for this symbol
      final signals = _getRecentSignals(symbol);
      if (signals.length < minAgentConsensus) {
        return; // Not enough signals
      }
      
      // Check if we already have an active intent for this symbol
      if (_activeIntents.containsKey(symbol)) {
        final existingIntent = _activeIntents[symbol]!;
        final timeSinceIntent = DateTime.now().difference(existingIntent.timestamp);
        
        if (timeSinceIntent < tradeCooldown) {
          _logger.d('Skipping consensus check for $symbol - cooldown active');
          return;
        }
      }
      
      // Group signals by type (buy/sell)
      final buySignals = signals.where((s) => s.type == SignalType.buy).toList();
      final sellSignals = signals.where((s) => s.type == SignalType.sell).toList();
      
      // Check for buy consensus
      final buyConsensus = _evaluateConsensus(buySignals, OrderSide.buy);
      if (buyConsensus != null) {
        await _generateTradeIntent(symbol, buyConsensus, buySignals);
        return;
      }
      
      // Check for sell consensus
      final sellConsensus = _evaluateConsensus(sellSignals, OrderSide.sell);
      if (sellConsensus != null) {
        await _generateTradeIntent(symbol, sellConsensus, sellSignals);
        return;
      }
      
    } catch (e) {
      _logger.e('Error checking consensus for $symbol: $e');
    }
  }
  
  /// Get recent signals for a symbol within the time window
  List<Signal> _getRecentSignals(String symbol) {
    final signals = _recentSignals[symbol] ?? [];
    final cutoff = DateTime.now().subtract(signalWindow);
    
    return signals.where((signal) => signal.timestamp.isAfter(cutoff)).toList();
  }
  
  /// Evaluate if signals reach consensus
  ConsensusResult? _evaluateConsensus(List<Signal> signals, OrderSide side) {
    if (signals.isEmpty) return null;
    
    // Get unique agents
    final agents = signals.map((s) => s.source).toSet();
    if (agents.length < minAgentConsensus) {
      return null; // Not enough different agents
    }
    
    // Calculate weighted strength
    double totalStrength = 0.0;
    final agentWeights = <String, double>{
      'technical_agent': 1.0,
      'sentiment_agent': 0.8,
      'insider_agent': 1.2, // Higher weight for insider signals
    };
    
    for (final signal in signals) {
      final weight = agentWeights[signal.source] ?? 1.0;
      totalStrength += signal.strength * weight;
    }
    
    // Check for blocking signals (strong bearish sentiment)
    final blockingSignals = signals.where((s) => 
      s.metadata['block_trading'] == true
    ).toList();
    
    if (blockingSignals.isNotEmpty && side == OrderSide.buy) {
      _logger.i('Blocking buy signal for consensus due to bearish sentiment');
      return null;
    }
    
    // Check if consensus strength meets threshold
    if (totalStrength >= minConsensusStrength) {
      return ConsensusResult(
        side: side,
        strength: totalStrength,
        agents: agents.toList(),
        signals: signals,
      );
    }
    
    return null;
  }
  
  /// Generate trade intent from consensus
  Future<void> _generateTradeIntent(
    String symbol, 
    ConsensusResult consensus, 
    List<Signal> signals,
  ) async {
    try {
      _logger.i('Generating trade intent for $symbol: ${consensus.side.name} (strength: ${consensus.strength})');
      
      // Calculate position sizing based on strength and risk
      final positionSize = _calculatePositionSize(consensus.strength);
      
      // Calculate stop loss and take profit levels
      final stopLoss = await _calculateStopLoss(symbol, consensus.side);
      final takeProfit = await _calculateTakeProfit(symbol, consensus.side, stopLoss);
      
      // Create trade intent
      final intent = TradeIntent(
        symbol: symbol,
        side: consensus.side,
        percentOfEquity: positionSize,
        stopLoss: stopLoss,
        takeProfit: takeProfit,
        confidence: consensus.strength / 2, // Normalize to 0-1 range
        timestamp: DateTime.now(),
        signals: signals,
      );
      
      // Store active intent
      _activeIntents[symbol] = intent;
      
      // Store decision in database
      await _storeTradeDecision(intent, consensus);
      
      // Publish trade intent
      await _publishTradeIntent(intent);
      
      AppLogger.instance.trade(
        symbol, 
        'INTENT_${consensus.side.name}',
        positionSize * 100, // As percentage
        null, // No price yet
        metadata: {
          'strength': consensus.strength,
          'agents': consensus.agents,
          'stop_loss': stopLoss,
          'take_profit': takeProfit,
        },
      );
      
    } catch (e) {
      _logger.e('Error generating trade intent for $symbol: $e');
    }
  }
  
  /// Calculate position size based on signal strength
  double _calculatePositionSize(double strength) {
    // Base position size from config
    double baseSize = Env.defaultPositionSize; // Default 2%
    
    // Scale by strength (strength is already weighted, so normalize)
    final normalizedStrength = (strength / 3.0).clamp(0.0, 1.0); // Max expected strength ~3.0
    
    // Position size = base * (0.5 + 0.5 * strength)
    // This gives range from 50% to 100% of base size
    final positionSize = baseSize * (0.5 + 0.5 * normalizedStrength);
    
    return positionSize.clamp(0.005, 0.05); // Min 0.5%, Max 5%
  }
  
  /// Calculate stop loss level
  Future<double?> _calculateStopLoss(String symbol, OrderSide side) async {
    try {
      // Get current price (simplified - in real implementation, get from market data)
      final currentPrice = await _getCurrentPrice(symbol);
      if (currentPrice == null) return null;
      
      // Get ATR for dynamic stop loss
      final atr = await _getATR(symbol);
      final atrMultiple = Env.trailingStopAtrMultiple; // Default 1.5
      
      double stopDistance;
      if (atr != null && atr > 0) {
        stopDistance = atr * atrMultiple;
      } else {
        // Fallback to percentage-based stop
        stopDistance = currentPrice * AppConfig.minStopLoss; // 1%
      }
      
      // Ensure minimum stop distance
      stopDistance = math.max(stopDistance, currentPrice * AppConfig.minStopLoss);
      
      if (side == OrderSide.buy) {
        return currentPrice - stopDistance;
      } else {
        return currentPrice + stopDistance;
      }
      
    } catch (e) {
      _logger.e('Error calculating stop loss for $symbol: $e');
      return null;
    }
  }
  
  /// Calculate take profit level
  Future<double?> _calculateTakeProfit(String symbol, OrderSide side, double? stopLoss) async {
    try {
      final currentPrice = await _getCurrentPrice(symbol);
      if (currentPrice == null || stopLoss == null) return null;
      
      // Use reward:risk ratio of 2:1
      final riskDistance = (currentPrice - stopLoss).abs();
      final rewardDistance = riskDistance * AppConfig.rewardRiskRatio; // 2.0
      
      if (side == OrderSide.buy) {
        return currentPrice + rewardDistance;
      } else {
        return currentPrice - rewardDistance;
      }
      
    } catch (e) {
      _logger.e('Error calculating take profit for $symbol: $e');
      return null;
    }
  }
  
  /// Get current price for a symbol (mock implementation)
  Future<double?> _getCurrentPrice(String symbol) async {
    // In real implementation, this would fetch from market data
    // For now, return a mock price
    return 100.0; // Mock price
  }
  
  /// Get ATR for a symbol (mock implementation)
  Future<double?> _getATR(String symbol) async {
    // In real implementation, this would fetch from TA service or cache
    // For now, return a mock ATR
    return 2.0; // Mock ATR
  }
  
  /// Store trade decision in database
  Future<void> _storeTradeDecision(TradeIntent intent, ConsensusResult consensus) async {
    try {
      const insertSql = '''
        INSERT INTO trade_decisions 
        (symbol, side, strength, percent_equity, stop_loss, take_profit, 
         contributing_agents, signal_count, decision_metadata)
        VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9)
      ''';
      
      final metadata = {
        'consensus_strength': consensus.strength,
        'signal_window_minutes': signalWindow.inMinutes,
        'signals': consensus.signals.map((s) => {
          'agent': s.source,
          'strength': s.strength,
          'metadata': s.metadata,
        }).toList(),
      };
      
      await _postgres.execute(insertSql, parameters: [
        intent.symbol,
        intent.side.name,
        consensus.strength,
        intent.percentOfEquity,
        intent.stopLoss,
        intent.takeProfit,
        consensus.agents,
        consensus.signals.length,
        jsonEncode(metadata),
      ]);
      
    } catch (e) {
      _logger.e('Error storing trade decision: $e');
    }
  }
  
  /// Publish trade intent to Redis
  Future<void> _publishTradeIntent(TradeIntent intent) async {
    try {
      final intentJson = jsonEncode(intent.toJson());
      await _redisCommands.send_object(['PUBLISH', 'trade_intents', intentJson]);
      
    } catch (e) {
      _logger.e('Error publishing trade intent: $e');
    }
  }
  
  /// Clean up old signals outside the time window
  void _cleanupOldSignals() {
    final cutoff = DateTime.now().subtract(signalWindow);
    
    for (final symbol in _recentSignals.keys.toList()) {
      final signals = _recentSignals[symbol]!;
      signals.removeWhere((signal) => signal.timestamp.isBefore(cutoff));
      
      if (signals.isEmpty) {
        _recentSignals.remove(symbol);
      }
    }
  }
  
  /// Clean up old trade intents
  void _cleanupOldIntents() {
    final cutoff = DateTime.now().subtract(tradeCooldown);
    
    _activeIntents.removeWhere((symbol, intent) => 
      intent.timestamp.isBefore(cutoff)
    );
  }
  
  /// Get coordinator statistics
  Map<String, dynamic> getStats() {
    final totalSignals = _recentSignals.values
        .fold(0, (sum, signals) => sum + signals.length);
    
    return {
      'symbols_with_signals': _recentSignals.length,
      'total_recent_signals': totalSignals,
      'active_intents': _activeIntents.length,
      'signal_window_minutes': signalWindow.inMinutes,
      'min_consensus_strength': minConsensusStrength,
      'min_agent_consensus': minAgentConsensus,
    };
  }
  
  /// Shutdown the coordinator
  Future<void> shutdown() async {
    _logger.i('Shutting down Agent Coordinator...');
    
    await _signalSubscription?.cancel();
    _cleanupTimer?.cancel();
    _heartbeatTimer?.cancel();
    
    try {
      _redis.close();
    } catch (e) {
      _logger.w('Error closing Redis connection: $e');
    }
    
    try {
      await _postgres.close();
    } catch (e) {
      _logger.w('Error closing Postgres connection: $e');
    }
    
    _isInitialized = false;
    _logger.i('Agent Coordinator shutdown complete');
  }
}

/// Result of consensus evaluation
class ConsensusResult {
  final OrderSide side;
  final double strength;
  final List<String> agents;
  final List<Signal> signals;
  
  ConsensusResult({
    required this.side,
    required this.strength,
    required this.agents,
    required this.signals,
  });
}
import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'dart:math' as math;
import 'package:logger/logger.dart';
import 'package:redis/redis.dart';
import 'package:postgres/postgres.dart';

import '../config.dart';
import '../data/models.dart';
import '../utils/logger.dart';

/// Risk management agent that enforces portfolio-level risk controls
class RiskAgent {
  static const String agentName = 'risk_agent';
  
  final Logger _logger = Logger();
  
  late RedisConnection _redis;
  late Command _redisCommands;
  late Connection _postgres;
  
  Timer? _riskCheckTimer;
  Timer? _heartbeatTimer;
  StreamSubscription? _intentSubscription;
  
  // Risk state
  double _currentEquity = 0.0;
  double _startOfDayEquity = 0.0;
  double _maxDrawdown = 0.0;
  double _currentDrawdown = 0.0;
  bool _circuitBreakerActive = false;
  DateTime? _circuitBreakerTime;
  
  // Portfolio state
  final Map<String, Position> _openPositions = {};
  final List<double> _dailyReturns = [];
  
  // Risk metrics cache
  double? _valueAtRisk95;
  double? _portfolioBeta;
  DateTime? _lastVarCalculation;
  
  /// Circuit breaker threshold (max intraday drawdown)
  static const double circuitBreakerThreshold = AppConfig.maxDrawdown; // 3%
  
  /// Maximum positions allowed
  static const int maxPositions = AppConfig.maxPositions; // 10
  
  /// Maximum single position size
  static const double maxPositionSize = AppConfig.maxPositionSize; // 5%
  
  /// Maximum portfolio heat (sum of all position risks)
  static const double maxPortfolioHeat = AppConfig.maxPortfolioHeat; // 15%
  
  /// Value-at-Risk calculation period
  static const int varPeriod = 252; // 1 year of daily returns
  
  RiskAgent();
  
  /// Isolate entry point for the risk agent
  static void isolateEntryPoint(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);
    
    final agent = RiskAgent();
    
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
          case 'check_trade_intent':
            final intent = TradeIntent.fromJson(message['intent']);
            final allowed = await agent.allows(intent);
            mainSendPort.send({'allowed': allowed, 'intent_id': message['intent_id']});
            break;
          case 'update_equity':
            final equity = message['equity'] as double;
            await agent._updateEquity(equity);
            break;
        }
      }
    });
  }
  
  /// Start the risk agent
  Future<void> start() async {
    try {
      _logger.i('Starting Risk Agent...');
      
      // Initialize connections
      await _initializeRedis();
      await _initializePostgres();
      
      // Create database tables
      await _createTables();
      
      // Load initial portfolio state
      await _loadPortfolioState();
      
      // Subscribe to trade intents
      _subscribeToTradeIntents();
      
      // Start periodic risk checks
      _startRiskChecks();
      
      // Start heartbeat
      _startHeartbeat();
      
      _logger.i('Risk Agent started successfully');
      
    } catch (e) {
      _logger.e('Failed to start Risk Agent: $e');
      rethrow;
    }
  }
  
  /// Stop the risk agent
  Future<void> stop() async {
    _logger.i('Stopping Risk Agent...');
    
    _riskCheckTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _intentSubscription?.cancel();
    
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
    
    _logger.i('Risk Agent stopped');
  }
  
  Future<void> _initializeRedis() async {
    _redis = RedisConnection();
    _redisCommands = await _redis.connect(Env.redisHost, Env.redisPort);
    _logger.i('Risk Agent connected to Redis');
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
    _logger.i('Risk Agent connected to PostgreSQL');
  }
  
  Future<void> _createTables() async {
    const createTablesSql = '''
      CREATE TABLE IF NOT EXISTS positions (
        id SERIAL PRIMARY KEY,
        symbol VARCHAR(10) NOT NULL,
        side VARCHAR(10) NOT NULL,
        quantity DECIMAL(15,6) NOT NULL,
        entry_price DECIMAL(10,4) NOT NULL,
        current_price DECIMAL(10,4),
        stop_loss DECIMAL(10,4),
        take_profit DECIMAL(10,4),
        trailing_stop DECIMAL(8,6),
        unrealized_pnl DECIMAL(15,2),
        risk_amount DECIMAL(15,2),
        opened_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        closed_at TIMESTAMP,
        status VARCHAR(20) DEFAULT 'open'
      );
      
      CREATE INDEX IF NOT EXISTS idx_positions_symbol_status 
      ON positions(symbol, status);
      
      CREATE INDEX IF NOT EXISTS idx_positions_opened_at 
      ON positions(opened_at DESC);
      
      CREATE TABLE IF NOT EXISTS portfolio_metrics (
        id SERIAL PRIMARY KEY,
        equity DECIMAL(15,2) NOT NULL,
        drawdown DECIMAL(8,6) NOT NULL,
        var_95 DECIMAL(15,2),
        portfolio_heat DECIMAL(8,6),
        open_positions INTEGER NOT NULL,
        circuit_breaker_active BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE INDEX IF NOT EXISTS idx_portfolio_metrics_time 
      ON portfolio_metrics(created_at DESC);
      
      CREATE TABLE IF NOT EXISTS daily_returns (
        id SERIAL PRIMARY KEY,
        date DATE NOT NULL UNIQUE,
        return_pct DECIMAL(10,8) NOT NULL,
        equity DECIMAL(15,2) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE INDEX IF NOT EXISTS idx_daily_returns_date 
      ON daily_returns(date DESC);
    ''';
    
    await _postgres.execute(createTablesSql);
    _logger.i('Risk Agent database tables created/verified');
  }
  
  Future<void> _loadPortfolioState() async {
    try {
      // Load current equity and drawdown
      await _loadCurrentEquity();
      
      // Load open positions
      await _loadOpenPositions();
      
      // Load recent daily returns for VaR calculation
      await _loadDailyReturns();
      
      // Calculate initial risk metrics
      await _calculateRiskMetrics();
      
      _logger.i('Portfolio state loaded: equity=\$${_currentEquity.toStringAsFixed(2)}, positions=${_openPositions.length}');
      
    } catch (e) {
      _logger.e('Error loading portfolio state: $e');
    }
  }
  
  Future<void> _loadCurrentEquity() async {
    try {
      const query = '''
        SELECT equity, drawdown, circuit_breaker_active 
        FROM portfolio_metrics 
        ORDER BY created_at DESC 
        LIMIT 1
      ''';
      
      final result = await _postgres.execute(query);
      if (result.isNotEmpty) {
        final row = result.first;
        _currentEquity = (row[0] as num).toDouble();
        _currentDrawdown = (row[1] as num).toDouble();
        _circuitBreakerActive = row[2] as bool;
      } else {
        // Initialize with default starting equity
        _currentEquity = Env.startingEquity; // Default $100k
        _startOfDayEquity = _currentEquity;
        _currentDrawdown = 0.0;
      }
      
    } catch (e) {
      _logger.e('Error loading current equity: $e');
      _currentEquity = Env.startingEquity;
      _startOfDayEquity = _currentEquity;
    }
  }
  
  Future<void> _loadOpenPositions() async {
    try {
      const query = '''
        SELECT symbol, side, quantity, entry_price, current_price, 
               stop_loss, take_profit, trailing_stop, unrealized_pnl, 
               risk_amount, opened_at
        FROM positions 
        WHERE status = 'open'
      ''';
      
      final result = await _postgres.execute(query);
      _openPositions.clear();
      
      for (final row in result) {
        final position = Position(
          symbol: row[0] as String,
          side: OrderSide.values.firstWhere((s) => s.name == row[1]),
          quantity: (row[2] as num).toDouble(),
          entryPrice: (row[3] as num).toDouble(),
          currentPrice: row[4] != null ? (row[4] as num).toDouble() : null,
          stopLoss: row[5] != null ? (row[5] as num).toDouble() : null,
          takeProfit: row[6] != null ? (row[6] as num).toDouble() : null,
          trailingStop: row[7] != null ? (row[7] as num).toDouble() : null,
          unrealizedPnl: row[8] != null ? (row[8] as num).toDouble() : null,
          openedAt: row[10] as DateTime,
        );
        
        _openPositions[position.symbol] = position;
      }
      
    } catch (e) {
      _logger.e('Error loading open positions: $e');
    }
  }
  
  Future<void> _loadDailyReturns() async {
    try {
      const query = '''
        SELECT return_pct 
        FROM daily_returns 
        ORDER BY date DESC 
        LIMIT ?
      ''';
      
      final result = await _postgres.execute(query, parameters: [varPeriod]);
      _dailyReturns.clear();
      
      for (final row in result) {
        _dailyReturns.add((row[0] as num).toDouble());
      }
      
      _logger.d('Loaded ${_dailyReturns.length} daily returns for VaR calculation');
      
    } catch (e) {
      _logger.e('Error loading daily returns: $e');
    }
  }
  
  void _subscribeToTradeIntents() {
    _intentSubscription = _listenToRedisChannel('trade_intents').listen((data) {
      try {
        final intentData = jsonDecode(data) as Map<String, dynamic>;
        final intent = TradeIntent.fromJson(intentData);
        _evaluateTradeIntent(intent);
      } catch (e) {
        _logger.e('Error processing trade intent: $e');
      }
    });
    
    _logger.i('Risk Agent subscribed to trade intents');
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
  
  void _startRiskChecks() {
    _riskCheckTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _performRiskCheck();
    });
    
    // Initial risk check
    _performRiskCheck();
  }
  
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _logger.d('Risk Agent heartbeat - equity: \$${_currentEquity.toStringAsFixed(2)}, '
               'drawdown: ${(_currentDrawdown * 100).toStringAsFixed(2)}%, '
               'positions: ${_openPositions.length}');
    });
  }
  
  /// Evaluate if a trade intent is allowed
  Future<void> _evaluateTradeIntent(TradeIntent intent) async {
    final allowed = await allows(intent);
    
    if (allowed) {
      // Publish approved intent
      await _publishApprovedIntent(intent);
    } else {
      // Log rejection
      _logger.w('Trade intent rejected for ${intent.symbol}: ${intent.side.name}');
      
      AppLogger.instance.risk(
        intent.symbol,
        'TRADE_REJECTED',
        'Risk limits exceeded',
        metadata: {
          'side': intent.side.name,
          'size_pct': intent.percentOfEquity * 100,
          'current_positions': _openPositions.length,
          'circuit_breaker': _circuitBreakerActive,
        },
      );
    }
  }
  
  /// Check if a trade intent is allowed under current risk limits
  Future<bool> allows(TradeIntent intent) async {
    try {
      // Circuit breaker check
      if (_circuitBreakerActive) {
        _logger.w('Trade blocked by circuit breaker');
        return false;
      }
      
      // Market hours check
      if (!AppConfig.isMarketHours && !Env.allowAfterHoursTrading) {
        _logger.w('Trade blocked - outside market hours');
        return false;
      }
      
      // Maximum positions check
      if (_openPositions.length >= maxPositions) {
        _logger.w('Trade blocked - maximum positions reached');
        return false;
      }
      
      // Position size check
      if (intent.percentOfEquity > maxPositionSize) {
        _logger.w('Trade blocked - position size too large');
        return false;
      }
      
      // Portfolio heat check
      final currentHeat = _calculateCurrentHeat();
      final intentRisk = _calculateTradeRisk(intent);
      
      if (currentHeat + intentRisk > maxPortfolioHeat) {
        _logger.w('Trade blocked - portfolio heat too high');
        return false;
      }
      
      // Existing position check (prevent doubling up)
      if (_openPositions.containsKey(intent.symbol)) {
        _logger.w('Trade blocked - already have position in ${intent.symbol}');
        return false;
      }
      
      // VaR check (if available)
      if (_valueAtRisk95 != null) {
        final projectedVar = _calculateProjectedVar(intent);
        if (projectedVar > _currentEquity * 0.05) { // Max 5% VaR
          _logger.w('Trade blocked - VaR limit exceeded');
          return false;
        }
      }
      
      return true;
      
    } catch (e) {
      _logger.e('Error evaluating trade intent: $e');
      return false; // Fail safe
    }
  }
  
  /// Calculate maximum position size allowed for a symbol
  double maxSizePct(String symbol) {
    try {
      // Start with maximum allowed position size
      double maxSize = maxPositionSize;
      
      // Reduce if circuit breaker is active
      if (_circuitBreakerActive) {
        return 0.0;
      }
      
      // Reduce based on current portfolio heat
      final currentHeat = _calculateCurrentHeat();
      final remainingHeat = maxPortfolioHeat - currentHeat;
      
      if (remainingHeat <= 0) {
        return 0.0;
      }
      
      // Return minimum of max size and remaining heat
      return math.min(maxSize, remainingHeat);
      
    } catch (e) {
      _logger.e('Error calculating max size for $symbol: $e');
      return 0.0;
    }
  }
  
  /// Calculate current portfolio heat (total risk exposure)
  double _calculateCurrentHeat() {
    double totalHeat = 0.0;
    
    for (final position in _openPositions.values) {
      // Risk per position = position size * stop distance / entry price
      if (position.stopLoss != null) {
        final stopDistance = (position.entryPrice - position.stopLoss!).abs();
        final riskPerShare = stopDistance;
        final positionValue = position.quantity * position.entryPrice;
        final positionRisk = (riskPerShare / position.entryPrice) * (positionValue / _currentEquity);
        totalHeat += positionRisk;
      } else {
        // If no stop loss, assume 2% risk
        final positionValue = position.quantity * position.entryPrice;
        totalHeat += (positionValue / _currentEquity) * 0.02;
      }
    }
    
    return totalHeat;
  }
  
  /// Calculate risk for a proposed trade
  double _calculateTradeRisk(TradeIntent intent) {
    if (intent.stopLoss == null) {
      // If no stop loss, assume 2% risk
      return intent.percentOfEquity * 0.02;
    }
    
    // Estimate entry price (mock)
    final estimatedPrice = 100.0; // In real implementation, get current market price
    
    final stopDistance = (estimatedPrice - intent.stopLoss!).abs();
    final riskPercentage = stopDistance / estimatedPrice;
    
    return intent.percentOfEquity * riskPercentage;
  }
  
  /// Calculate projected VaR with new position
  double _calculateProjectedVar(TradeIntent intent) {
    if (_valueAtRisk95 == null || _dailyReturns.length < 30) {
      return 0.0;
    }
    
    // Simplified projection - assume new position adds proportional risk
    final positionRisk = _calculateTradeRisk(intent);
    final portfolioRisk = _valueAtRisk95! / _currentEquity;
    
    return _currentEquity * (portfolioRisk + positionRisk);
  }
  
  /// Perform periodic risk checks
  Future<void> _performRiskCheck() async {
    try {
      // Update current positions
      await _updatePositionPrices();
      
      // Calculate current drawdown
      _calculateDrawdown();
      
      // Check circuit breaker
      _checkCircuitBreaker();
      
      // Calculate risk metrics
      await _calculateRiskMetrics();
      
      // Store metrics
      await _storePortfolioMetrics();
      
    } catch (e) {
      _logger.e('Error during risk check: $e');
    }
  }
  
  Future<void> _updatePositionPrices() async {
    // In real implementation, this would fetch current market prices
    // For now, simulate price updates
    for (final position in _openPositions.values) {
      // Mock price update (±1% random change)
      final random = math.Random();
      final change = (random.nextDouble() - 0.5) * 0.02; // ±1%
      position.currentPrice = position.entryPrice * (1 + change);
      
      // Calculate unrealized P&L
      if (position.side == OrderSide.buy) {
        position.unrealizedPnl = position.quantity * (position.currentPrice! - position.entryPrice);
      } else {
        position.unrealizedPnl = position.quantity * (position.entryPrice - position.currentPrice!);
      }
    }
  }
  
  void _calculateDrawdown() {
    if (_startOfDayEquity == 0) {
      _startOfDayEquity = _currentEquity;
    }
    
    // Calculate total unrealized P&L
    final totalUnrealizedPnl = _openPositions.values
        .fold(0.0, (sum, pos) => sum + (pos.unrealizedPnl ?? 0.0));
    
    final currentTotalEquity = _currentEquity + totalUnrealizedPnl;
    
    // Update equity high-water mark
    if (currentTotalEquity > _startOfDayEquity) {
      _startOfDayEquity = currentTotalEquity;
    }
    
    // Calculate current drawdown
    _currentDrawdown = (_startOfDayEquity - currentTotalEquity) / _startOfDayEquity;
    _maxDrawdown = math.max(_maxDrawdown, _currentDrawdown);
  }
  
  void _checkCircuitBreaker() {
    if (!_circuitBreakerActive && _currentDrawdown >= circuitBreakerThreshold) {
      _activateCircuitBreaker();
    } else if (_circuitBreakerActive && _currentDrawdown < circuitBreakerThreshold * 0.8) {
      // Reset circuit breaker when drawdown reduces to 80% of threshold
      _deactivateCircuitBreaker();
    }
  }
  
  void _activateCircuitBreaker() {
    _circuitBreakerActive = true;
    _circuitBreakerTime = DateTime.now();
    
    _logger.w('CIRCUIT BREAKER ACTIVATED - Drawdown: ${(_currentDrawdown * 100).toStringAsFixed(2)}%');
    
    AppLogger.instance.risk(
      'PORTFOLIO',
      'CIRCUIT_BREAKER_ON',
      'Maximum drawdown exceeded',
      metadata: {
        'drawdown_pct': _currentDrawdown * 100,
        'threshold_pct': circuitBreakerThreshold * 100,
        'equity': _currentEquity,
      },
    );
    
    // Publish circuit breaker event
    _publishCircuitBreakerEvent(true);
  }
  
  void _deactivateCircuitBreaker() {
    _circuitBreakerActive = false;
    
    _logger.i('Circuit breaker deactivated - Drawdown reduced to ${(_currentDrawdown * 100).toStringAsFixed(2)}%');
    
    AppLogger.instance.risk(
      'PORTFOLIO',
      'CIRCUIT_BREAKER_OFF',
      'Drawdown reduced below threshold',
      metadata: {
        'drawdown_pct': _currentDrawdown * 100,
        'equity': _currentEquity,
      },
    );
    
    // Publish circuit breaker event
    _publishCircuitBreakerEvent(false);
  }
  
  Future<void> _calculateRiskMetrics() async {
    try {
      // Calculate Value-at-Risk (95% confidence)
      if (_dailyReturns.length >= 30) {
        _valueAtRisk95 = _calculateHistoricalVar();
      }
      
      // Calculate portfolio beta (simplified)
      _portfolioBeta = _calculatePortfolioBeta();
      
      _lastVarCalculation = DateTime.now();
      
    } catch (e) {
      _logger.e('Error calculating risk metrics: $e');
    }
  }
  
  double _calculateHistoricalVar() {
    if (_dailyReturns.isEmpty) return 0.0;
    
    // Sort returns in ascending order
    final sortedReturns = List<double>.from(_dailyReturns)..sort();
    
    // 95% VaR is the 5th percentile
    final index = (sortedReturns.length * 0.05).floor();
    final var95Return = sortedReturns[math.max(0, index)];
    
    // Convert to dollar amount
    return _currentEquity * var95Return.abs();
  }
  
  double _calculatePortfolioBeta() {
    // Simplified beta calculation - in real implementation, 
    // this would compare returns against market benchmark
    return 1.0; // Assume market beta for now
  }
  
  Future<void> _storePortfolioMetrics() async {
    try {
      const insertSql = '''
        INSERT INTO portfolio_metrics 
        (equity, drawdown, var_95, portfolio_heat, open_positions, circuit_breaker_active)
        VALUES (\$1, \$2, \$3, \$4, \$5, \$6)
      ''';
      
      await _postgres.execute(insertSql, parameters: [
        _currentEquity,
        _currentDrawdown,
        _valueAtRisk95,
        _calculateCurrentHeat(),
        _openPositions.length,
        _circuitBreakerActive,
      ]);
      
    } catch (e) {
      _logger.e('Error storing portfolio metrics: $e');
    }
  }
  
  Future<void> _updateEquity(double newEquity) async {
    final oldEquity = _currentEquity;
    _currentEquity = newEquity;
    
    // Calculate daily return if this is end of day
    if (_isEndOfDay()) {
      final dailyReturn = (newEquity - oldEquity) / oldEquity;
      await _storeDailyReturn(dailyReturn);
      _dailyReturns.insert(0, dailyReturn);
      
      // Keep only recent returns for VaR calculation
      if (_dailyReturns.length > varPeriod) {
        _dailyReturns.removeRange(varPeriod, _dailyReturns.length);
      }
    }
  }
  
  bool _isEndOfDay() {
    final now = DateTime.now();
    return now.hour == 16 && now.minute == 0; // 4:00 PM market close
  }
  
  Future<void> _storeDailyReturn(double returnPct) async {
    try {
      const insertSql = '''
        INSERT INTO daily_returns (date, return_pct, equity)
        VALUES (CURRENT_DATE, \$1, \$2)
        ON CONFLICT (date) DO UPDATE SET 
          return_pct = EXCLUDED.return_pct,
          equity = EXCLUDED.equity
      ''';
      
      await _postgres.execute(insertSql, parameters: [returnPct, _currentEquity]);
      
    } catch (e) {
      _logger.e('Error storing daily return: $e');
    }
  }
  
  Future<void> _publishApprovedIntent(TradeIntent intent) async {
    try {
      final approvedIntent = intent.copyWith(
        metadata: {
          ...intent.metadata,
          'risk_approved': true,
          'max_portfolio_heat': maxPortfolioHeat,
          'current_heat': _calculateCurrentHeat(),
        },
      );
      
      final intentJson = jsonEncode(approvedIntent.toJson());
      await _redisCommands.send_object(['PUBLISH', 'approved_intents', intentJson]);
      
    } catch (e) {
      _logger.e('Error publishing approved intent: $e');
    }
  }
  
  Future<void> _publishCircuitBreakerEvent(bool active) async {
    try {
      final event = {
        'type': 'circuit_breaker',
        'active': active,
        'drawdown': _currentDrawdown,
        'equity': _currentEquity,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      await _redisCommands.send_object(['PUBLISH', 'risk_events', jsonEncode(event)]);
      
    } catch (e) {
      _logger.e('Error publishing circuit breaker event: $e');
    }
  }
  
  /// Get current risk metrics
  Map<String, dynamic> getRiskMetrics() {
    return {
      'equity': _currentEquity,
      'drawdown': _currentDrawdown * 100, // As percentage
      'max_drawdown': _maxDrawdown * 100,
      'circuit_breaker_active': _circuitBreakerActive,
      'open_positions': _openPositions.length,
      'max_positions': maxPositions,
      'portfolio_heat': _calculateCurrentHeat() * 100,
      'max_portfolio_heat': maxPortfolioHeat * 100,
      'value_at_risk_95': _valueAtRisk95,
      'portfolio_beta': _portfolioBeta,
      'last_var_calculation': _lastVarCalculation?.toIso8601String(),
    };
  }
}
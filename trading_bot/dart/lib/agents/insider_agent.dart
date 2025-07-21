import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:redis/redis.dart';
import 'package:postgres/postgres.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/alpha_vantage_client.dart';
import '../utils/logger.dart';

/// Insider trading analysis agent that generates signals based on insider transactions
class InsiderAgent {
  static const String agentName = 'insider_agent';
  
  final Logger _logger = Logger();
  final Map<String, List<InsiderTransaction>> _insiderData = {};
  final Map<String, DateTime> _lastRefresh = {};
  
  late RedisConnection _redis;
  late Command _redisCommands;
  late Connection _postgres;
  late AlphaVantageClient _alphaVantageClient;
  
  Timer? _refreshTimer;
  Timer? _heartbeatTimer;
  
  /// Minimum transaction value to be considered significant
  static const double significantTransactionThreshold = 100000.0; // $100k
  
  /// Time window for multiple insider transactions
  static const Duration multipleTransactionWindow = Duration(days: 7);
  
  /// Refresh interval for insider data (daily)
  static const Duration refreshInterval = Duration(hours: 24);
  
  /// Weight boosts for insider signals
  static const double ceoBoost = 0.2;
  static const double cfoBoost = 0.2;
  static const double multipleInsidersBoost = 0.3;
  
  InsiderAgent();
  
  /// Isolate entry point for the insider agent
  static void isolateEntryPoint(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);
    
    final agent = InsiderAgent();
    
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
          case 'refresh_insider_data':
            await agent._refreshInsiderData();
            break;
          case 'analyze_symbol':
            final symbol = message['symbol'] as String;
            await agent._analyzeSymbol(symbol);
            break;
        }
      }
    });
  }
  
  /// Start the insider agent
  Future<void> start() async {
    try {
      _logger.i('Starting Insider Agent...');
      
      // Initialize connections
      await _initializeRedis();
      await _initializePostgres();
      _initializeAlphaVantage();
      
      // Create database tables if they don't exist
      await _createTables();
      
      // Start periodic refresh (daily at 9:00 UTC)
      _startPeriodicRefresh();
      
      // Start heartbeat
      _startHeartbeat();
      
      _logger.i('Insider Agent started successfully');
      
    } catch (e) {
      _logger.e('Failed to start Insider Agent: $e');
      rethrow;
    }
  }
  
  /// Stop the insider agent
  Future<void> stop() async {
    _logger.i('Stopping Insider Agent...');
    
    _refreshTimer?.cancel();
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
    
    _logger.i('Insider Agent stopped');
  }
  
  Future<void> _initializeRedis() async {
    _redis = RedisConnection();
    _redisCommands = await _redis.connect(Env.redisHost, Env.redisPort);
    _logger.i('Insider Agent connected to Redis');
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
    _logger.i('Insider Agent connected to PostgreSQL');
  }
  
  void _initializeAlphaVantage() {
    _alphaVantageClient = alphaVantageClient;
    _logger.i('Insider Agent initialized Alpha Vantage client');
  }
  
  Future<void> _createTables() async {
    const createTableSql = '''
      CREATE TABLE IF NOT EXISTS insider_events (
        id SERIAL PRIMARY KEY,
        symbol VARCHAR(10) NOT NULL,
        insider_name VARCHAR(200) NOT NULL,
        title VARCHAR(200),
        transaction_type VARCHAR(50) NOT NULL,
        shares DECIMAL(15,2) NOT NULL,
        price DECIMAL(10,4),
        value DECIMAL(15,2),
        transaction_date DATE NOT NULL,
        filing_date DATE NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(symbol, insider_name, transaction_date, shares)
      );
      
      CREATE INDEX IF NOT EXISTS idx_insider_events_symbol_date 
      ON insider_events(symbol, transaction_date DESC);
      
      CREATE INDEX IF NOT EXISTS idx_insider_events_value 
      ON insider_events(value DESC) WHERE value IS NOT NULL;
    ''';
    
    await _postgres.execute(createTableSql);
    _logger.i('Insider events tables created/verified');
  }
  
  void _startPeriodicRefresh() {
    // Calculate time until next 9:00 UTC
    final now = DateTime.now().toUtc();
    var nextRefresh = DateTime.utc(now.year, now.month, now.day, 9, 0);
    
    if (nextRefresh.isBefore(now)) {
      nextRefresh = nextRefresh.add(const Duration(days: 1));
    }
    
    final timeUntilRefresh = nextRefresh.difference(now);
    
    // Schedule initial refresh
    Timer(timeUntilRefresh, () {
      _refreshInsiderData();
      
      // Then schedule daily refreshes
      _refreshTimer = Timer.periodic(refreshInterval, (timer) {
        _refreshInsiderData();
      });
    });
    
    _logger.i('Insider Agent scheduled next refresh for ${nextRefresh.toIso8601String()}');
  }
  
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _logger.d('Insider Agent heartbeat - tracking ${_insiderData.length} symbols');
    });
  }
  
  /// Refresh insider data for all tracked symbols
  Future<void> _refreshInsiderData() async {
    try {
      _logger.i('Starting daily insider data refresh');
      
      // Get list of symbols to track
      final symbols = await _getTrackedSymbols();
      
      int updatedCount = 0;
      
      for (final symbol in symbols) {
        try {
          final transactions = await _fetchInsiderTransactions(symbol);
          if (transactions.isNotEmpty) {
            await _storeInsiderTransactions(symbol, transactions);
            _insiderData[symbol] = transactions;
            _lastRefresh[symbol] = DateTime.now();
            updatedCount++;
            
            // Analyze for signals after updating data
            await _analyzeSymbol(symbol);
          }
          
          // Rate limiting for Alpha Vantage API
          await Future.delayed(const Duration(seconds: 15));
          
        } catch (e) {
          _logger.w('Error refreshing insider data for $symbol: $e');
        }
      }
      
      _logger.i('Completed insider data refresh for $updatedCount symbols');
      
    } catch (e) {
      _logger.e('Error during insider data refresh: $e');
    }
  }
  
  /// Get list of symbols to track for insider data
  Future<List<String>> _getTrackedSymbols() async {
    try {
      // In a real implementation, this might query active symbols from the database
      // For now, return a focused list of large-cap stocks where insider trading is most meaningful
      return [
        'AAPL', 'MSFT', 'GOOGL', 'AMZN', 'TSLA', 'NVDA', 'META', 'BRK.B',
        'UNH', 'JNJ', 'JPM', 'V', 'PG', 'XOM', 'HD', 'CVX', 'PFE', 'BAC',
        'ABBV', 'KO', 'AVGO', 'PEP', 'TMO', 'COST', 'MRK', 'DHR', 'VZ', 'ACN',
      ];
    } catch (e) {
      _logger.e('Error getting tracked symbols: $e');
      return [];
    }
  }
  
  /// Fetch insider transactions for a symbol
  Future<List<InsiderTransaction>> _fetchInsiderTransactions(String symbol) async {
    try {
      final transactions = await _alphaVantageClient.getInsiderTrading(symbol);
      
      // Filter for recent and significant transactions
      final cutoffDate = DateTime.now().subtract(const Duration(days: 90));
      final recentTransactions = transactions
          .where((tx) => tx.transactionDate.isAfter(cutoffDate))
          .toList();
      
      _logger.d('Fetched ${recentTransactions.length} recent insider transactions for $symbol');
      
      return recentTransactions;
      
    } catch (e) {
      _logger.e('Error fetching insider transactions for $symbol: $e');
      return [];
    }
  }
  
  /// Store insider transactions in database
  Future<void> _storeInsiderTransactions(
    String symbol, 
    List<InsiderTransaction> transactions,
  ) async {
    try {
      for (final transaction in transactions) {
        const insertSql = '''
          INSERT INTO insider_events 
          (symbol, insider_name, title, transaction_type, shares, price, value, 
           transaction_date, filing_date)
          VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9)
          ON CONFLICT (symbol, insider_name, transaction_date, shares) DO NOTHING
        ''';
        
        await _postgres.execute(insertSql, parameters: [
          symbol,
          transaction.insiderName,
          transaction.title,
          transaction.transactionType.name,
          transaction.shares,
          transaction.price,
          transaction.value,
          transaction.transactionDate,
          transaction.filingDate,
        ]);
      }
      
      _logger.d('Stored ${transactions.length} insider transactions for $symbol');
      
    } catch (e) {
      _logger.e('Error storing insider transactions for $symbol: $e');
    }
  }
  
  /// Analyze a symbol for insider trading signals
  Future<void> _analyzeSymbol(String symbol) async {
    try {
      final transactions = _insiderData[symbol] ?? [];
      if (transactions.isEmpty) {
        // Try to load from database
        final dbTransactions = await _loadInsiderTransactionsFromDb(symbol);
        if (dbTransactions.isNotEmpty) {
          _insiderData[symbol] = dbTransactions;
        } else {
          return;
        }
      }
      
      final signals = _generateInsiderSignals(symbol, _insiderData[symbol]!);
      
      // Publish signals
      for (final signal in signals) {
        await _publishSignal(signal);
      }
      
    } catch (e) {
      _logger.e('Error analyzing insider data for $symbol: $e');
    }
  }
  
  /// Load insider transactions from database
  Future<List<InsiderTransaction>> _loadInsiderTransactionsFromDb(String symbol) async {
    try {
      const querySql = '''
        SELECT insider_name, title, transaction_type, shares, price, value,
               transaction_date, filing_date
        FROM insider_events 
        WHERE symbol = \$1 
          AND transaction_date >= CURRENT_DATE - INTERVAL '90 days'
        ORDER BY transaction_date DESC
      ''';
      
      final result = await _postgres.execute(querySql, parameters: [symbol]);
      
      final transactions = <InsiderTransaction>[];
      for (final row in result) {
        transactions.add(InsiderTransaction(
          symbol: symbol,
          insiderName: row[0] as String,
          title: row[1] as String?,
          transactionType: _parseTransactionType(row[2] as String),
          shares: (row[3] as num).toDouble(),
          price: row[4] != null ? (row[4] as num).toDouble() : null,
          value: row[5] != null ? (row[5] as num).toDouble() : null,
          transactionDate: row[6] as DateTime,
          filingDate: row[7] as DateTime,
        ));
      }
      
      return transactions;
      
    } catch (e) {
      _logger.e('Error loading insider transactions for $symbol: $e');
      return [];
    }
  }
  
  /// Generate insider trading signals
  List<Signal> _generateInsiderSignals(
    String symbol, 
    List<InsiderTransaction> transactions,
  ) {
    final signals = <Signal>[];
    
    // Focus on buy transactions only (insider purchases are bullish signals)
    final buyTransactions = transactions
        .where((tx) => tx.isBuy)
        .where((tx) => tx.isSignificant) // >= $100k
        .toList();
    
    if (buyTransactions.isEmpty) {
      return signals;
    }
    
    // Recent significant purchases (within 30 days)
    final recentCutoff = DateTime.now().subtract(const Duration(days: 30));
    final recentBuys = buyTransactions
        .where((tx) => tx.transactionDate.isAfter(recentCutoff))
        .toList();
    
    if (recentBuys.isEmpty) {
      return signals;
    }
    
    // Calculate base signal strength
    double baseStrength = 0.3; // Base strength for any significant insider buying
    
    // Boost for executive purchases (CEO, CFO, etc.)
    final executiveBuys = recentBuys.where((tx) => _isExecutive(tx.title)).toList();
    if (executiveBuys.isNotEmpty) {
      baseStrength += ceoBoost; // +0.2 for executive purchases
    }
    
    // Boost for multiple insiders buying within 7 days
    final clusteredBuys = _findClusteredTransactions(recentBuys);
    if (clusteredBuys.length >= 2) {
      baseStrength += multipleInsidersBoost; // +0.3 for multiple insiders
    }
    
    // Calculate total purchase value
    final totalValue = recentBuys
        .where((tx) => tx.value != null)
        .fold(0.0, (sum, tx) => sum + tx.value!);
    
    // Additional boost for very large purchases
    if (totalValue > 1000000) { // > $1M
      baseStrength += 0.2;
    } else if (totalValue > 500000) { // > $500k
      baseStrength += 0.1;
    }
    
    // Cap the strength at 1.0
    final finalStrength = baseStrength.clamp(0.0, 1.0);
    
    if (finalStrength > 0.3) { // Only emit if above base threshold
      final reason = _buildInsiderReason(recentBuys, executiveBuys, clusteredBuys);
      
      signals.add(Signal.buy(
        symbol: symbol,
        strength: finalStrength,
        source: agentName,
        metadata: {
          'reason': reason,
          'transaction_count': recentBuys.length,
          'executive_count': executiveBuys.length,
          'total_value': totalValue,
          'largest_transaction': recentBuys
              .map((tx) => tx.value ?? 0)
              .reduce((a, b) => a > b ? a : b),
          'insider_names': recentBuys.map((tx) => tx.insiderName).toSet().toList(),
        },
      ));
    }
    
    return signals;
  }
  
  /// Check if insider title indicates executive status
  bool _isExecutive(String? title) {
    if (title == null) return false;
    
    final titleLower = title.toLowerCase();
    return titleLower.contains('ceo') ||
           titleLower.contains('cfo') ||
           titleLower.contains('president') ||
           titleLower.contains('chief') ||
           titleLower.contains('chairman');
  }
  
  /// Find transactions that are clustered in time (within 7 days)
  List<InsiderTransaction> _findClusteredTransactions(
    List<InsiderTransaction> transactions,
  ) {
    if (transactions.length < 2) return transactions;
    
    // Sort by transaction date
    final sorted = List<InsiderTransaction>.from(transactions)
      ..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));
    
    final clustered = <InsiderTransaction>[];
    
    for (int i = 0; i < sorted.length; i++) {
      final current = sorted[i];
      bool isInCluster = false;
      
      // Check if this transaction is within 7 days of any other
      for (int j = 0; j < sorted.length; j++) {
        if (i == j) continue;
        
        final other = sorted[j];
        final daysDiff = current.transactionDate.difference(other.transactionDate).inDays.abs();
        
        if (daysDiff <= 7) {
          isInCluster = true;
          break;
        }
      }
      
      if (isInCluster) {
        clustered.add(current);
      }
    }
    
    return clustered;
  }
  
  /// Build descriptive reason for insider signal
  String _buildInsiderReason(
    List<InsiderTransaction> recentBuys,
    List<InsiderTransaction> executiveBuys,
    List<InsiderTransaction> clusteredBuys,
  ) {
    final parts = <String>[];
    
    if (executiveBuys.isNotEmpty) {
      parts.add('${executiveBuys.length} executive purchase${executiveBuys.length > 1 ? 's' : ''}');
    }
    
    if (clusteredBuys.length >= 2) {
      parts.add('${clusteredBuys.length} insiders buying within 7 days');
    }
    
    final totalValue = recentBuys
        .where((tx) => tx.value != null)
        .fold(0.0, (sum, tx) => sum + tx.value!);
    
    if (totalValue > 1000000) {
      parts.add('total value >\$1M');
    } else if (totalValue > 500000) {
      parts.add('total value >\$500k');
    }
    
    if (parts.isEmpty) {
      return 'Significant insider buying activity';
    }
    
    return 'Insider buying: ${parts.join(', ')}';
  }
  
  TransactionType _parseTransactionType(String type) {
    switch (type.toLowerCase()) {
      case 'buy':
        return TransactionType.buy;
      case 'sell':
        return TransactionType.sell;
      case 'option_exercise':
        return TransactionType.optionExercise;
      default:
        return TransactionType.buy;
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
  
  /// Get insider data for a symbol (for testing/debugging)
  List<InsiderTransaction>? getInsiderData(String symbol) {
    return _insiderData[symbol];
  }
  
  /// Get statistics about insider data
  Map<String, dynamic> getInsiderStats() {
    final totalTransactions = _insiderData.values
        .fold(0, (sum, transactions) => sum + transactions.length);
    
    final symbolsWithData = _insiderData.keys.length;
    
    final lastRefreshTimes = _lastRefresh.values.toList()
      ..sort((a, b) => b.compareTo(a));
    
    return {
      'symbols_tracked': symbolsWithData,
      'total_transactions': totalTransactions,
      'last_refresh': lastRefreshTimes.isNotEmpty 
          ? lastRefreshTimes.first.toIso8601String() 
          : null,
      'refresh_interval_hours': refreshInterval.inHours,
    };
  }
}
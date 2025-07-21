import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:logger/logger.dart';
import 'package:redis/redis.dart';
import 'package:postgres/postgres.dart';
import 'package:grpc/grpc.dart';

import '../config.dart';
import '../data/models.dart';
import '../utils/logger.dart';

/// Executes trade orders via Trading212 bridge
class OrderExecutor {
  static OrderExecutor? _instance;
  static OrderExecutor get instance => _instance ??= OrderExecutor._();
  
  OrderExecutor._();
  
  final Logger _logger = Logger();
  final Map<String, Order> _pendingOrders = {};
  final Map<String, Position> _activePositions = {};
  
  late RedisConnection _redis;
  late Command _redisCommands;
  late Connection _postgres;
  late ClientChannel _tradingBridgeChannel;
  late Trading212BridgeService _tradingBridge;
  
  StreamSubscription? _intentSubscription;
  Timer? _heartbeatTimer;
  Timer? _orderStatusTimer;
  
  bool _isInitialized = false;
  
  /// Maximum retry attempts for failed orders
  static const int maxRetryAttempts = 3;
  
  /// Retry delay (exponential backoff)
  static const Duration baseRetryDelay = Duration(seconds: 5);
  
  /// Order timeout before cancellation
  static const Duration orderTimeout = Duration(minutes: 5);
  
  /// Initialize the order executor
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _logger.i('Initializing Order Executor...');
      
      // Initialize connections
      await _initializeRedis();
      await _initializePostgres();
      await _initializeTradingBridge();
      
      // Create database tables
      await _createTables();
      
      // Load pending orders and positions
      await _loadPendingOrders();
      await _loadActivePositions();
      
      // Subscribe to approved trade intents
      _subscribeToApprovedIntents();
      
      // Start order status monitoring
      _startOrderStatusMonitoring();
      
      // Start heartbeat
      _startHeartbeat();
      
      _isInitialized = true;
      _logger.i('Order Executor initialized successfully');
      
    } catch (e) {
      _logger.e('Failed to initialize Order Executor: $e');
      rethrow;
    }
  }
  
  Future<void> _initializeRedis() async {
    _redis = RedisConnection();
    _redisCommands = await _redis.connect(Env.redisHost, Env.redisPort);
    _logger.i('Order Executor connected to Redis');
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
    _logger.i('Order Executor connected to PostgreSQL');
  }
  
  Future<void> _initializeTradingBridge() async {
    _tradingBridgeChannel = ClientChannel(
      'localhost',
      port: Env.tradingBridgePort,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
      ),
    );
    
    _tradingBridge = Trading212BridgeService(_tradingBridgeChannel);
    
    // Test connection
    await _tradingBridge.ping();
    
    _logger.i('Order Executor connected to Trading212 bridge');
  }
  
  Future<void> _createTables() async {
    const createTablesSql = '''
      CREATE TABLE IF NOT EXISTS orders (
        id SERIAL PRIMARY KEY,
        order_id VARCHAR(100) UNIQUE NOT NULL,
        symbol VARCHAR(10) NOT NULL,
        side VARCHAR(10) NOT NULL,
        order_type VARCHAR(20) NOT NULL,
        quantity DECIMAL(15,6) NOT NULL,
        price DECIMAL(10,4),
        stop_loss DECIMAL(10,4),
        take_profit DECIMAL(10,4),
        time_in_force VARCHAR(10),
        status VARCHAR(20) NOT NULL,
        fill_price DECIMAL(10,4),
        fill_quantity DECIMAL(15,6),
        commission DECIMAL(10,4),
        retry_count INTEGER DEFAULT 0,
        error_message TEXT,
        intent_metadata JSONB,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        filled_at TIMESTAMP
      );
      
      CREATE INDEX IF NOT EXISTS idx_orders_symbol_status 
      ON orders(symbol, status);
      
      CREATE INDEX IF NOT EXISTS idx_orders_status_created 
      ON orders(status, created_at DESC);
      
      CREATE INDEX IF NOT EXISTS idx_orders_order_id 
      ON orders(order_id);
      
      CREATE TABLE IF NOT EXISTS executions (
        id SERIAL PRIMARY KEY,
        order_id VARCHAR(100) NOT NULL,
        execution_id VARCHAR(100) UNIQUE NOT NULL,
        quantity DECIMAL(15,6) NOT NULL,
        price DECIMAL(10,4) NOT NULL,
        commission DECIMAL(10,4),
        execution_time TIMESTAMP NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE INDEX IF NOT EXISTS idx_executions_order_id 
      ON executions(order_id);
      
      CREATE INDEX IF NOT EXISTS idx_executions_time 
      ON executions(execution_time DESC);
    ''';
    
    await _postgres.execute(createTablesSql);
    _logger.i('Order Executor database tables created/verified');
  }
  
  Future<void> _loadPendingOrders() async {
    try {
      const query = '''
        SELECT order_id, symbol, side, order_type, quantity, price, 
               stop_loss, take_profit, status, retry_count, intent_metadata,
               created_at, updated_at
        FROM orders 
        WHERE status IN ('pending', 'submitted', 'partially_filled')
      ''';
      
      final result = await _postgres.execute(query);
      _pendingOrders.clear();
      
      for (final row in result) {
        final order = Order(
          id: row[0] as String,
          symbol: row[1] as String,
          side: OrderSide.values.firstWhere((s) => s.name == row[2]),
          type: OrderType.values.firstWhere((t) => t.name == row[3]),
          quantity: (row[4] as num).toDouble(),
          price: row[5] != null ? (row[5] as num).toDouble() : null,
          stopLoss: row[6] != null ? (row[6] as num).toDouble() : null,
          takeProfit: row[7] != null ? (row[7] as num).toDouble() : null,
          status: OrderStatus.values.firstWhere((s) => s.name == row[8]),
          timestamp: row[12] as DateTime,
        );
        
        _pendingOrders[order.id] = order;
      }
      
      _logger.i('Loaded ${_pendingOrders.length} pending orders');
      
    } catch (e) {
      _logger.e('Error loading pending orders: $e');
    }
  }
  
  Future<void> _loadActivePositions() async {
    try {
      const query = '''
        SELECT symbol, side, quantity, entry_price, current_price,
               stop_loss, take_profit, unrealized_pnl, opened_at
        FROM positions 
        WHERE status = 'open'
      ''';
      
      final result = await _postgres.execute(query);
      _activePositions.clear();
      
      for (final row in result) {
        final position = Position(
          symbol: row[0] as String,
          side: OrderSide.values.firstWhere((s) => s.name == row[1]),
          quantity: (row[2] as num).toDouble(),
          entryPrice: (row[3] as num).toDouble(),
          currentPrice: row[4] != null ? (row[4] as num).toDouble() : null,
          stopLoss: row[5] != null ? (row[5] as num).toDouble() : null,
          takeProfit: row[6] != null ? (row[6] as num).toDouble() : null,
          unrealizedPnl: row[7] != null ? (row[7] as num).toDouble() : null,
          openedAt: row[8] as DateTime,
        );
        
        _activePositions[position.symbol] = position;
      }
      
      _logger.i('Loaded ${_activePositions.length} active positions');
      
    } catch (e) {
      _logger.e('Error loading active positions: $e');
    }
  }
  
  void _subscribeToApprovedIntents() {
    _intentSubscription = _listenToRedisChannel('approved_intents').listen((data) {
      try {
        final intentData = jsonDecode(data) as Map<String, dynamic>;
        final intent = TradeIntent.fromJson(intentData);
        _executeTradeIntent(intent);
      } catch (e) {
        _logger.e('Error processing approved intent: $e');
      }
    });
    
    _logger.i('Order Executor subscribed to approved intents');
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
  
  void _startOrderStatusMonitoring() {
    _orderStatusTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkOrderStatuses();
    });
  }
  
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _logger.d('Order Executor heartbeat - pending: ${_pendingOrders.length}, '
               'positions: ${_activePositions.length}');
    });
  }
  
  /// Execute a trade intent
  Future<void> _executeTradeIntent(TradeIntent intent) async {
    try {
      _logger.i('Executing trade intent: ${intent.symbol} ${intent.side.name} ${intent.percentOfEquity * 100}%');
      
      // Calculate order parameters
      final orderParams = await _calculateOrderParams(intent);
      if (orderParams == null) {
        _logger.e('Failed to calculate order parameters for ${intent.symbol}');
        return;
      }
      
      // Create bracket order (entry + stop + take profit)
      await _createBracketOrder(intent, orderParams);
      
    } catch (e) {
      _logger.e('Error executing trade intent for ${intent.symbol}: $e');
      
      AppLogger.instance.trade(
        intent.symbol,
        'EXECUTION_ERROR',
        intent.percentOfEquity * 100,
        null,
        metadata: {'error': e.toString()},
      );
    }
  }
  
  /// Calculate order parameters from trade intent
  Future<OrderParameters?> _calculateOrderParams(TradeIntent intent) async {
    try {
      // Get current market price
      final currentPrice = await _getCurrentMarketPrice(intent.symbol);
      if (currentPrice == null) {
        _logger.e('Could not get current price for ${intent.symbol}');
        return null;
      }
      
      // Get current account equity
      final accountInfo = await _tradingBridge.getAccountInfo();
      final equity = accountInfo.equity;
      
      // Calculate position value and quantity
      final positionValue = equity * intent.percentOfEquity;
      final quantity = _calculateQuantity(positionValue, currentPrice, intent.side);
      
      // Determine entry price (market or limit)
      double? entryPrice;
      OrderType orderType;
      
      if (Env.useMarketOrders) {
        orderType = OrderType.market;
        entryPrice = null; // Market order
      } else {
        orderType = OrderType.limit;
        // Place limit order slightly away from current price for better fill probability
        if (intent.side == OrderSide.buy) {
          entryPrice = currentPrice * 1.001; // 0.1% above market
        } else {
          entryPrice = currentPrice * 0.999; // 0.1% below market
        }
      }
      
      return OrderParameters(
        symbol: intent.symbol,
        side: intent.side,
        orderType: orderType,
        quantity: quantity,
        entryPrice: entryPrice,
        stopLoss: intent.stopLoss,
        takeProfit: intent.takeProfit,
        positionValue: positionValue,
        currentPrice: currentPrice,
      );
      
    } catch (e) {
      _logger.e('Error calculating order parameters: $e');
      return null;
    }
  }
  
  double _calculateQuantity(double positionValue, double price, OrderSide side) {
    // For stocks, quantity is simply position value / price
    // For fractional shares, we can use exact decimal quantities
    return positionValue / price;
  }
  
  Future<double?> _getCurrentMarketPrice(String symbol) async {
    try {
      final quote = await _tradingBridge.getQuote(symbol);
      return quote.price;
    } catch (e) {
      _logger.e('Error getting market price for $symbol: $e');
      return null;
    }
  }
  
  /// Create bracket order (entry + stop + take profit)
  Future<void> _createBracketOrder(TradeIntent intent, OrderParameters params) async {
    try {
      // Generate unique order IDs
      final entryOrderId = _generateOrderId('entry');
      final stopOrderId = _generateOrderId('stop');
      final tpOrderId = _generateOrderId('tp');
      
      // Create entry order
      final entryOrder = Order(
        id: entryOrderId,
        symbol: params.symbol,
        side: params.side,
        type: params.orderType,
        quantity: params.quantity,
        price: params.entryPrice,
        status: OrderStatus.pending,
        timestamp: DateTime.now(),
      );
      
      // Store entry order
      await _storeOrder(entryOrder, intent);
      _pendingOrders[entryOrder.id] = entryOrder;
      
      // Submit entry order with retry logic
      await _submitOrderWithRetry(entryOrder, intent);
      
    } catch (e) {
      _logger.e('Error creating bracket order: $e');
      rethrow;
    }
  }
  
  /// Submit order with retry logic
  Future<void> _submitOrderWithRetry(Order order, TradeIntent intent) async {
    int retryCount = 0;
    
    while (retryCount < maxRetryAttempts) {
      try {
        _logger.i('Submitting order ${order.id} (attempt ${retryCount + 1})');
        
        // Submit to Trading212 bridge
        final submitRequest = SubmitOrderRequest(
          orderId: order.id,
          symbol: order.symbol,
          side: order.side.name,
          orderType: order.type.name,
          quantity: order.quantity,
          price: order.price,
          stopLoss: order.stopLoss,
          takeProfit: order.takeProfit,
        );
        
        final response = await _tradingBridge.submitOrder(submitRequest);
        
        if (response.success) {
          // Order submitted successfully
          order.status = OrderStatus.submitted;
          await _updateOrderStatus(order, 'Order submitted successfully');
          
          AppLogger.instance.trade(
            order.symbol,
            'ORDER_SUBMITTED',
            (order.quantity * (order.price ?? 0.0)),
            order.price,
            metadata: {
              'order_id': order.id,
              'side': order.side.name,
              'type': order.type.name,
            },
          );
          
          return; // Success, exit retry loop
          
        } else {
          throw Exception('Order submission failed: ${response.errorMessage}');
        }
        
      } catch (e) {
        retryCount++;
        final errorMsg = 'Order submission attempt $retryCount failed: $e';
        _logger.w(errorMsg);
        
        if (retryCount >= maxRetryAttempts) {
          // Max retries reached, mark order as failed
          order.status = OrderStatus.failed;
          await _updateOrderStatus(order, 'Max retries exceeded: $e');
          
          AppLogger.instance.trade(
            order.symbol,
            'ORDER_FAILED',
            (order.quantity * (order.price ?? 0.0)),
            order.price,
            metadata: {
              'order_id': order.id,
              'error': e.toString(),
              'retry_count': retryCount,
            },
          );
          
          throw Exception('Order submission failed after $maxRetryAttempts attempts: $e');
        }
        
        // Wait before retry (exponential backoff)
        final delayMs = baseRetryDelay.inMilliseconds * math.pow(2, retryCount - 1);
        await Future.delayed(Duration(milliseconds: delayMs.toInt()));
      }
    }
  }
  
  /// Store order in database
  Future<void> _storeOrder(Order order, TradeIntent intent) async {
    try {
      const insertSql = '''
        INSERT INTO orders 
        (order_id, symbol, side, order_type, quantity, price, stop_loss, 
         take_profit, status, intent_metadata)
        VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10)
      ''';
      
      await _postgres.execute(insertSql, parameters: [
        order.id,
        order.symbol,
        order.side.name,
        order.type.name,
        order.quantity,
        order.price,
        order.stopLoss,
        order.takeProfit,
        order.status.name,
        jsonEncode(intent.toJson()),
      ]);
      
    } catch (e) {
      _logger.e('Error storing order: $e');
    }
  }
  
  /// Update order status in database
  Future<void> _updateOrderStatus(Order order, String? errorMessage) async {
    try {
      const updateSql = '''
        UPDATE orders 
        SET status = \$1, error_message = \$2, updated_at = CURRENT_TIMESTAMP,
            retry_count = retry_count + 1
        WHERE order_id = \$3
      ''';
      
      await _postgres.execute(updateSql, parameters: [
        order.status.name,
        errorMessage,
        order.id,
      ]);
      
    } catch (e) {
      _logger.e('Error updating order status: $e');
    }
  }
  
  /// Check status of pending orders
  Future<void> _checkOrderStatuses() async {
    try {
      for (final order in _pendingOrders.values.toList()) {
        await _checkSingleOrderStatus(order);
      }
    } catch (e) {
      _logger.e('Error checking order statuses: $e');
    }
  }
  
  /// Check status of a single order
  Future<void> _checkSingleOrderStatus(Order order) async {
    try {
      // Check if order has timed out
      final orderAge = DateTime.now().difference(order.timestamp);
      if (orderAge > orderTimeout && order.status == OrderStatus.pending) {
        _logger.w('Order ${order.id} timed out, cancelling');
        await _cancelOrder(order, 'Order timeout');
        return;
      }
      
      // Query order status from Trading212 bridge
      final statusRequest = OrderStatusRequest(orderId: order.id);
      final statusResponse = await _tradingBridge.getOrderStatus(statusRequest);
      
      final newStatus = OrderStatus.values.firstWhere(
        (s) => s.name == statusResponse.status,
        orElse: () => order.status,
      );
      
      if (newStatus != order.status) {
        _logger.i('Order ${order.id} status changed: ${order.status.name} -> ${newStatus.name}');
        order.status = newStatus;
        
        await _updateOrderStatus(order, null);
        
        // Handle specific status changes
        switch (newStatus) {
          case OrderStatus.filled:
            await _handleOrderFilled(order, statusResponse);
            break;
          case OrderStatus.partiallyFilled:
            await _handleOrderPartiallyFilled(order, statusResponse);
            break;
          case OrderStatus.cancelled:
          case OrderStatus.rejected:
          case OrderStatus.failed:
            _pendingOrders.remove(order.id);
            break;
          default:
            break;
        }
      }
      
    } catch (e) {
      _logger.e('Error checking status for order ${order.id}: $e');
    }
  }
  
  /// Handle order filled
  Future<void> _handleOrderFilled(Order order, OrderStatusResponse statusResponse) async {
    try {
      // Update order with fill information
      order.fillPrice = statusResponse.fillPrice;
      order.fillQuantity = statusResponse.fillQuantity;
      
      // Store execution
      await _storeExecution(order, statusResponse);
      
      // Create position
      await _createPosition(order);
      
      // Remove from pending orders
      _pendingOrders.remove(order.id);
      
      // Create stop loss and take profit orders if specified
      if (order.stopLoss != null || order.takeProfit != null) {
        await _createStopAndTargetOrders(order);
      }
      
      AppLogger.instance.trade(
        order.symbol,
        'ORDER_FILLED',
        order.fillQuantity! * order.fillPrice!,
        order.fillPrice,
        metadata: {
          'order_id': order.id,
          'quantity': order.fillQuantity,
          'side': order.side.name,
        },
      );
      
    } catch (e) {
      _logger.e('Error handling filled order ${order.id}: $e');
    }
  }
  
  /// Handle order partially filled
  Future<void> _handleOrderPartiallyFilled(Order order, OrderStatusResponse statusResponse) async {
    try {
      // Store partial execution
      await _storeExecution(order, statusResponse);
      
      AppLogger.instance.trade(
        order.symbol,
        'ORDER_PARTIAL_FILL',
        statusResponse.fillQuantity * statusResponse.fillPrice,
        statusResponse.fillPrice,
        metadata: {
          'order_id': order.id,
          'filled_quantity': statusResponse.fillQuantity,
          'remaining_quantity': order.quantity - statusResponse.fillQuantity,
        },
      );
      
    } catch (e) {
      _logger.e('Error handling partially filled order ${order.id}: $e');
    }
  }
  
  /// Store execution in database
  Future<void> _storeExecution(Order order, OrderStatusResponse statusResponse) async {
    try {
      const insertSql = '''
        INSERT INTO executions (order_id, execution_id, quantity, price, commission, execution_time)
        VALUES (\$1, \$2, \$3, \$4, \$5, \$6)
        ON CONFLICT (execution_id) DO NOTHING
      ''';
      
      await _postgres.execute(insertSql, parameters: [
        order.id,
        statusResponse.executionId ?? '${order.id}_${DateTime.now().millisecondsSinceEpoch}',
        statusResponse.fillQuantity,
        statusResponse.fillPrice,
        statusResponse.commission ?? 0.0,
        DateTime.now(),
      ]);
      
    } catch (e) {
      _logger.e('Error storing execution: $e');
    }
  }
  
  /// Create position from filled order
  Future<void> _createPosition(Order order) async {
    try {
      final position = Position(
        symbol: order.symbol,
        side: order.side,
        quantity: order.fillQuantity!,
        entryPrice: order.fillPrice!,
        stopLoss: order.stopLoss,
        takeProfit: order.takeProfit,
        openedAt: DateTime.now(),
      );
      
      _activePositions[position.symbol] = position;
      
      // Store in database
      const insertSql = '''
        INSERT INTO positions 
        (symbol, side, quantity, entry_price, stop_loss, take_profit, status)
        VALUES (\$1, \$2, \$3, \$4, \$5, \$6, 'open')
      ''';
      
      await _postgres.execute(insertSql, parameters: [
        position.symbol,
        position.side.name,
        position.quantity,
        position.entryPrice,
        position.stopLoss,
        position.takeProfit,
      ]);
      
      // Publish position created event
      await _publishPositionEvent('position_created', position);
      
    } catch (e) {
      _logger.e('Error creating position: $e');
    }
  }
  
  /// Create stop loss and take profit orders
  Future<void> _createStopAndTargetOrders(Order parentOrder) async {
    try {
      final position = _activePositions[parentOrder.symbol];
      if (position == null) return;
      
      // Create stop loss order
      if (parentOrder.stopLoss != null) {
        final stopOrder = Order(
          id: _generateOrderId('stop'),
          symbol: parentOrder.symbol,
          side: _getOppositeOrderSide(parentOrder.side),
          type: OrderType.stopLoss,
          quantity: position.quantity,
          price: parentOrder.stopLoss,
          status: OrderStatus.pending,
          timestamp: DateTime.now(),
        );
        
        await _storeOrder(stopOrder, TradeIntent.fromPosition(position));
        await _submitOrderWithRetry(stopOrder, TradeIntent.fromPosition(position));
      }
      
      // Create take profit order
      if (parentOrder.takeProfit != null) {
        final tpOrder = Order(
          id: _generateOrderId('tp'),
          symbol: parentOrder.symbol,
          side: _getOppositeOrderSide(parentOrder.side),
          type: OrderType.takeProfit,
          quantity: position.quantity,
          price: parentOrder.takeProfit,
          status: OrderStatus.pending,
          timestamp: DateTime.now(),
        );
        
        await _storeOrder(tpOrder, TradeIntent.fromPosition(position));
        await _submitOrderWithRetry(tpOrder, TradeIntent.fromPosition(position));
      }
      
    } catch (e) {
      _logger.e('Error creating stop and target orders: $e');
    }
  }
  
  OrderSide _getOppositeOrderSide(OrderSide side) {
    return side == OrderSide.buy ? OrderSide.sell : OrderSide.buy;
  }
  
  /// Cancel an order
  Future<void> _cancelOrder(Order order, String reason) async {
    try {
      final cancelRequest = CancelOrderRequest(orderId: order.id, reason: reason);
      final response = await _tradingBridge.cancelOrder(cancelRequest);
      
      if (response.success) {
        order.status = OrderStatus.cancelled;
        await _updateOrderStatus(order, reason);
        _pendingOrders.remove(order.id);
        
        _logger.i('Order ${order.id} cancelled: $reason');
      }
      
    } catch (e) {
      _logger.e('Error cancelling order ${order.id}: $e');
    }
  }
  
  /// Publish position event to Redis
  Future<void> _publishPositionEvent(String eventType, Position position) async {
    try {
      final event = {
        'type': eventType,
        'position': position.toJson(),
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      await _redisCommands.send_object(['PUBLISH', 'position_events', jsonEncode(event)]);
      
    } catch (e) {
      _logger.e('Error publishing position event: $e');
    }
  }
  
  String _generateOrderId(String prefix) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = math.Random().nextInt(1000);
    return '${prefix}_${timestamp}_$random';
  }
  
  /// Get execution statistics
  Map<String, dynamic> getExecutionStats() {
    final pendingCount = _pendingOrders.length;
    final positionCount = _activePositions.length;
    
    return {
      'pending_orders': pendingCount,
      'active_positions': positionCount,
      'max_retry_attempts': maxRetryAttempts,
      'order_timeout_minutes': orderTimeout.inMinutes,
      'positions_by_side': {
        'long': _activePositions.values.where((p) => p.side == OrderSide.buy).length,
        'short': _activePositions.values.where((p) => p.side == OrderSide.sell).length,
      },
    };
  }
  
  /// Shutdown the order executor
  Future<void> shutdown() async {
    _logger.i('Shutting down Order Executor...');
    
    await _intentSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _orderStatusTimer?.cancel();
    
    try {
      await _tradingBridgeChannel.shutdown();
    } catch (e) {
      _logger.w('Error shutting down trading bridge channel: $e');
    }
    
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
    _logger.i('Order Executor shutdown complete');
  }
}

/// Order parameters calculated from trade intent
class OrderParameters {
  final String symbol;
  final OrderSide side;
  final OrderType orderType;
  final double quantity;
  final double? entryPrice;
  final double? stopLoss;
  final double? takeProfit;
  final double positionValue;
  final double currentPrice;
  
  OrderParameters({
    required this.symbol,
    required this.side,
    required this.orderType,
    required this.quantity,
    this.entryPrice,
    this.stopLoss,
    this.takeProfit,
    required this.positionValue,
    required this.currentPrice,
  });
}

/// Mock Trading212 Bridge Service
class Trading212BridgeService {
  final ClientChannel _channel;
  
  Trading212BridgeService(this._channel);
  
  Future<void> ping() async {
    // Mock ping implementation
    await Future.delayed(const Duration(milliseconds: 100));
  }
  
  Future<AccountInfoResponse> getAccountInfo() async {
    // Mock account info
    return AccountInfoResponse(
      equity: 100000.0, // $100k mock equity
      cash: 50000.0,
      marginUsed: 0.0,
    );
  }
  
  Future<QuoteResponse> getQuote(String symbol) async {
    // Mock quote - return random price around $100
    final random = math.Random();
    final price = 95.0 + random.nextDouble() * 10.0; // $95-$105
    
    return QuoteResponse(
      symbol: symbol,
      price: price,
      bid: price - 0.01,
      ask: price + 0.01,
    );
  }
  
  Future<SubmitOrderResponse> submitOrder(SubmitOrderRequest request) async {
    // Mock order submission
    await Future.delayed(const Duration(seconds: 1));
    
    // Simulate 95% success rate
    final random = math.Random();
    if (random.nextDouble() < 0.95) {
      return SubmitOrderResponse(
        success: true,
        orderId: request.orderId,
      );
    } else {
      return SubmitOrderResponse(
        success: false,
        errorMessage: 'Mock order rejection for testing',
      );
    }
  }
  
  Future<OrderStatusResponse> getOrderStatus(OrderStatusRequest request) async {
    // Mock order status - simulate progression to filled
    await Future.delayed(const Duration(milliseconds: 200));
    
    // For demo, assume orders fill quickly
    return OrderStatusResponse(
      orderId: request.orderId,
      status: 'filled',
      fillPrice: 100.0,
      fillQuantity: 10.0,
      executionId: '${request.orderId}_exec_${DateTime.now().millisecondsSinceEpoch}',
    );
  }
  
  Future<CancelOrderResponse> cancelOrder(CancelOrderRequest request) async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    return CancelOrderResponse(
      success: true,
      orderId: request.orderId,
    );
  }
}

// Mock gRPC request/response classes
class AccountInfoResponse {
  final double equity;
  final double cash;
  final double marginUsed;
  
  AccountInfoResponse({
    required this.equity,
    required this.cash,
    required this.marginUsed,
  });
}

class QuoteResponse {
  final String symbol;
  final double price;
  final double bid;
  final double ask;
  
  QuoteResponse({
    required this.symbol,
    required this.price,
    required this.bid,
    required this.ask,
  });
}

class SubmitOrderRequest {
  final String orderId;
  final String symbol;
  final String side;
  final String orderType;
  final double quantity;
  final double? price;
  final double? stopLoss;
  final double? takeProfit;
  
  SubmitOrderRequest({
    required this.orderId,
    required this.symbol,
    required this.side,
    required this.orderType,
    required this.quantity,
    this.price,
    this.stopLoss,
    this.takeProfit,
  });
}

class SubmitOrderResponse {
  final bool success;
  final String? orderId;
  final String? errorMessage;
  
  SubmitOrderResponse({
    required this.success,
    this.orderId,
    this.errorMessage,
  });
}

class OrderStatusRequest {
  final String orderId;
  
  OrderStatusRequest({required this.orderId});
}

class OrderStatusResponse {
  final String orderId;
  final String status;
  final double fillPrice;
  final double fillQuantity;
  final String? executionId;
  final double? commission;
  
  OrderStatusResponse({
    required this.orderId,
    required this.status,
    required this.fillPrice,
    required this.fillQuantity,
    this.executionId,
    this.commission,
  });
}

class CancelOrderRequest {
  final String orderId;
  final String reason;
  
  CancelOrderRequest({
    required this.orderId,
    required this.reason,
  });
}

class CancelOrderResponse {
  final bool success;
  final String orderId;
  final String? errorMessage;
  
  CancelOrderResponse({
    required this.success,
    required this.orderId,
    this.errorMessage,
  });
}
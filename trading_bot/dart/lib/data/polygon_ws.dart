import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:logger/logger.dart';
import 'package:redis/redis.dart';
import '../config.dart';
import 'models.dart';

class PolygonWebSocketClient {
  static const String _wsUrl = 'wss://socket.polygon.io/stocks';
  static const int _reconnectDelay = 5000; // ms
  static const int _maxReconnectAttempts = 10;
  
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  RedisConnection? _redis;
  Command? _redisCommands;
  
  final Logger _logger = Logger();
  final StreamController<Bar> _barController = StreamController<Bar>.broadcast();
  final StreamController<Tick> _tickController = StreamController<Tick>.broadcast();
  
  bool _isConnected = false;
  bool _isAuthenticated = false;
  int _reconnectAttempts = 0;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  
  // Public streams
  Stream<Bar> get barStream => _barController.stream;
  Stream<Tick> get tickStream => _tickController.stream;
  
  bool get isConnected => _isConnected;
  bool get isAuthenticated => _isAuthenticated;
  
  Future<void> connect() async {
    try {
      await _initRedis();
      await _connectWebSocket();
    } catch (e) {
      _logger.e('Failed to connect to Polygon WebSocket: $e');
      _scheduleReconnect();
    }
  }
  
  Future<void> _initRedis() async {
    try {
      _redis = RedisConnection();
      _redisCommands = await _redis!.connect(Env.redisHost, Env.redisPort);
      _logger.i('Connected to Redis');
    } catch (e) {
      _logger.e('Failed to connect to Redis: $e');
      rethrow;
    }
  }
  
  Future<void> _connectWebSocket() async {
    try {
      _logger.i('Connecting to Polygon WebSocket...');
      
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );
      
      _isConnected = true;
      _reconnectAttempts = 0;
      _logger.i('Connected to Polygon WebSocket');
      
      // Start heartbeat
      _startHeartbeat();
      
      // Authenticate
      await _authenticate();
      
    } catch (e) {
      _logger.e('WebSocket connection failed: $e');
      _handleError(e);
    }
  }
  
  Future<void> _authenticate() async {
    final authMessage = {
      'action': 'auth',
      'params': Env.polygonApiKey,
    };
    
    _send(authMessage);
    _logger.i('Sent authentication message');
  }
  
  Future<void> _subscribeToMarketData() async {
    if (!_isAuthenticated) {
      _logger.w('Cannot subscribe - not authenticated');
      return;
    }
    
    // Subscribe to minute bars for all stocks
    final subscribeMessage = {
      'action': 'subscribe',
      'params': 'AM.*', // Aggregate (minute bars) for all stocks
    };
    
    _send(subscribeMessage);
    _logger.i('Subscribed to market data');
    
    // Also subscribe to trades for major indices
    final tickSubscribeMessage = {
      'action': 'subscribe', 
      'params': 'T.SPY,T.QQQ,T.IWM,T.DIA', // Trades for major ETFs
    };
    
    _send(tickSubscribeMessage);
    _logger.i('Subscribed to tick data for major ETFs');
  }
  
  void _handleMessage(dynamic message) {
    try {
      final List<dynamic> messages = jsonDecode(message);
      
      for (final msg in messages) {
        if (msg is! Map<String, dynamic>) continue;
        
        final String? eventType = msg['ev'];
        
        switch (eventType) {
          case 'status':
            _handleStatusMessage(msg);
            break;
          case 'AM': // Aggregate Minute Bar
            _handleBarMessage(msg);
            break;
          case 'T': // Trade
            _handleTradeMessage(msg);
            break;
          default:
            _logger.d('Unknown message type: $eventType');
        }
      }
    } catch (e) {
      _logger.e('Error handling message: $e');
    }
  }
  
  void _handleStatusMessage(Map<String, dynamic> msg) {
    final String? status = msg['status'];
    final String? message = msg['message'];
    
    _logger.i('Status: $status - $message');
    
    if (status == 'auth_success') {
      _isAuthenticated = true;
      _logger.i('Authentication successful');
      _subscribeToMarketData();
    } else if (status == 'connected') {
      _logger.i('Connection established');
    } else if (status == 'auth_failed') {
      _logger.e('Authentication failed: $message');
      disconnect();
    }
  }
  
  void _handleBarMessage(Map<String, dynamic> msg) {
    try {
      final bar = Bar(
        symbol: msg['sym'] ?? '',
        open: (msg['o'] ?? 0).toDouble(),
        high: (msg['h'] ?? 0).toDouble(),
        low: (msg['l'] ?? 0).toDouble(),
        close: (msg['c'] ?? 0).toDouble(),
        volume: msg['v'] ?? 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(msg['t'] ?? 0),
        timeframe: '1m',
      );
      
      _barController.add(bar);
      
      // Publish to Redis for other services
      _publishToRedis('bars', bar.toJson());
      
      _logger.d('Bar: ${bar.symbol} ${bar.close}');
      
    } catch (e) {
      _logger.e('Error parsing bar message: $e');
    }
  }
  
  void _handleTradeMessage(Map<String, dynamic> msg) {
    try {
      final tick = Tick(
        symbol: msg['sym'] ?? '',
        price: (msg['p'] ?? 0).toDouble(),
        volume: msg['s'] ?? 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(msg['t'] ?? 0),
        exchange: msg['x']?.toString() ?? '',
      );
      
      _tickController.add(tick);
      
      // Publish to Redis
      _publishToRedis('ticks', tick.toJson());
      
      _logger.d('Tick: ${tick.symbol} ${tick.price}');
      
    } catch (e) {
      _logger.e('Error parsing trade message: $e');
    }
  }
  
  Future<void> _publishToRedis(String channel, Map<String, dynamic> data) async {
    try {
      await _redisCommands?.send_object(['PUBLISH', channel, jsonEncode(data)]);
    } catch (e) {
      _logger.e('Failed to publish to Redis: $e');
    }
  }
  
  void _send(Map<String, dynamic> message) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(message));
    } else {
      _logger.w('Cannot send message - not connected');
    }
  }
  
  void _handleError(dynamic error) {
    _logger.e('WebSocket error: $error');
    _isConnected = false;
    _isAuthenticated = false;
    _scheduleReconnect();
  }
  
  void _handleDisconnect() {
    _logger.w('WebSocket disconnected');
    _isConnected = false;
    _isAuthenticated = false;
    _heartbeatTimer?.cancel();
    _scheduleReconnect();
  }
  
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _logger.e('Max reconnect attempts reached');
      return;
    }
    
    _reconnectAttempts++;
    final delay = _reconnectDelay * _reconnectAttempts;
    
    _logger.i('Scheduling reconnect in ${delay}ms (attempt $_reconnectAttempts)');
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _logger.i('Attempting to reconnect...');
      connect();
    });
  }
  
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        _send({'action': 'ping'});
      } else {
        timer.cancel();
      }
    });
  }
  
  Future<void> subscribeToSymbols(List<String> symbols) async {
    if (!_isAuthenticated) {
      _logger.w('Cannot subscribe to symbols - not authenticated');
      return;
    }
    
    // Subscribe to minute bars for specific symbols
    final barSymbols = symbols.map((s) => 'AM.$s').join(',');
    final subscribeMessage = {
      'action': 'subscribe',
      'params': barSymbols,
    };
    
    _send(subscribeMessage);
    _logger.i('Subscribed to symbols: $symbols');
  }
  
  Future<void> unsubscribeFromSymbols(List<String> symbols) async {
    if (!_isAuthenticated) return;
    
    final barSymbols = symbols.map((s) => 'AM.$s').join(',');
    final unsubscribeMessage = {
      'action': 'unsubscribe',
      'params': barSymbols,
    };
    
    _send(unsubscribeMessage);
    _logger.i('Unsubscribed from symbols: $symbols');
  }
  
  Future<void> disconnect() async {
    _logger.i('Disconnecting from Polygon WebSocket');
    
    _isConnected = false;
    _isAuthenticated = false;
    
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    
    await _subscription?.cancel();
    await _channel?.sink.close();
    
    _redis?.close();
    
    _logger.i('Disconnected');
  }
  
  void dispose() {
    disconnect();
    _barController.close();
    _tickController.close();
  }
}

// Singleton instance
final polygonWsClient = PolygonWebSocketClient();
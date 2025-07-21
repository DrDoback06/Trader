import 'dart:async';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import 'config.dart';
import 'utils/logger.dart';
import 'utils/scheduler.dart';
import 'data/polygon_ws.dart';
import 'data/alpha_vantage_client.dart';
import 'agents/coordinator.dart';
import 'agents/technical_agent.dart';
import 'agents/sentiment_agent.dart';
import 'agents/insider_agent.dart';
import 'agents/risk_agent.dart';
import 'execution/order_executor.dart';
import 'ui/app.dart';

/// Global logger instance
final logger = AppLogger.instance;

/// Global isolate management
class IsolateManager {
  static final Map<String, Isolate> _isolates = {};
  static final Map<String, ReceivePort> _receivePorts = {};
  static final Map<String, SendPort> _sendPorts = {};
  
  static Future<void> startAgent(String agentName, Function entryPoint) async {
    try {
      logger.i('Starting isolate for $agentName');
      
      final receivePort = ReceivePort();
      _receivePorts[agentName] = receivePort;
      
      final isolate = await Isolate.spawn(
        entryPoint,
        receivePort.sendPort,
        debugName: agentName,
      );
      
      _isolates[agentName] = isolate;
      
      // Listen for the SendPort from the isolate
      final completer = Completer<SendPort>();
      late StreamSubscription subscription;
      
      subscription = receivePort.listen((message) {
        if (message is SendPort && !completer.isCompleted) {
          _sendPorts[agentName] = message;
          completer.complete(message);
          subscription.cancel();
        }
      });
      
      await completer.future;
      logger.i('Successfully started $agentName isolate');
      
    } catch (e) {
      logger.e('Failed to start $agentName isolate: $e');
      rethrow;
    }
  }
  
  static SendPort? getSendPort(String agentName) {
    return _sendPorts[agentName];
  }
  
  static void killAll() {
    for (final isolate in _isolates.values) {
      isolate.kill(priority: Isolate.immediate);
    }
    
    for (final port in _receivePorts.values) {
      port.close();
    }
    
    _isolates.clear();
    _receivePorts.clear();
    _sendPorts.clear();
    
    logger.i('All isolates terminated');
  }
}

/// Application lifecycle manager
class AppLifecycleManager with WidgetsBindingObserver {
  static AppLifecycleManager? _instance;
  static AppLifecycleManager get instance => _instance ??= AppLifecycleManager._();
  
  AppLifecycleManager._();
  
  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    logger.i('App lifecycle manager initialized');
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        logger.i('App resumed');
        break;
      case AppLifecycleState.inactive:
        logger.i('App inactive');
        break;
      case AppLifecycleState.paused:
        logger.i('App paused');
        break;
      case AppLifecycleState.detached:
        logger.i('App detached - shutting down');
        shutdown();
        break;
      case AppLifecycleState.hidden:
        logger.i('App hidden');
        break;
    }
  }
  
  void shutdown() {
    logger.i('Shutting down application...');
    
    // Disconnect from data sources
    polygonWsClient.disconnect();
    
    // Kill all isolates
    IsolateManager.killAll();
    
    // Remove observer
    WidgetsBinding.instance.removeObserver(this);
    
    logger.i('Application shutdown complete');
  }
}

/// Main application initialization
class TradingBotApp {
  static bool _isInitialized = false;
  
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      logger.i('Initializing Trading Bot Application...');
      
      // Check market hours
      if (!AppConfig.isMarketHours && !Env.debugMode) {
        logger.w('Market is closed. Running in limited mode.');
      }
      
      // Initialize components
      await _initializeDataSources();
      await _initializeAgents();
      await _initializeScheduler();
      
      // Start monitoring
      _startHealthMonitoring();
      
      _isInitialized = true;
      logger.i('Trading Bot Application initialized successfully');
      
    } catch (e) {
      logger.e('Failed to initialize application: $e');
      rethrow;
    }
  }
  
  static Future<void> _initializeDataSources() async {
    logger.i('Initializing data sources...');
    
    // Start Polygon WebSocket connection
    await polygonWsClient.connect();
    
    // Test Alpha Vantage connection
    try {
      await alphaVantageClient.getCompanyOverview('AAPL');
      logger.i('Alpha Vantage connection verified');
    } catch (e) {
      logger.w('Alpha Vantage connection test failed: $e');
    }
  }
  
  static Future<void> _initializeAgents() async {
    logger.i('Starting trading agents...');
    
    // Start agent isolates
    await IsolateManager.startAgent('technical_agent', TechnicalAgent.isolateEntryPoint);
    await IsolateManager.startAgent('sentiment_agent', SentimentAgent.isolateEntryPoint);
    await IsolateManager.startAgent('insider_agent', InsiderAgent.isolateEntryPoint);
    await IsolateManager.startAgent('risk_agent', RiskAgent.isolateEntryPoint);
    
    // Initialize coordinator (runs in main isolate)
    await AgentCoordinator.instance.initialize();
    
    logger.i('All agents started successfully');
  }
  
  static Future<void> _initializeScheduler() async {
    logger.i('Setting up scheduled tasks...');
    
    // Schedule daily insider data refresh
    AppScheduler.scheduleDaily(
      hour: 9, // 9 AM UTC (before market open)
      minute: 0,
      task: () async {
        final insiderAgentPort = IsolateManager.getSendPort('insider_agent');
        insiderAgentPort?.send({'action': 'refresh_insider_data'});
      },
      taskName: 'refresh_insider_data',
    );
    
    // Schedule market hours check
    AppScheduler.scheduleHourly(
      minute: 0,
      task: () async {
        if (!AppConfig.isMarketHours && polygonWsClient.isConnected) {
          logger.i('Market closed - reducing activity');
          // Could pause certain operations
        } else if (AppConfig.isMarketHours && !polygonWsClient.isConnected) {
          logger.i('Market open - reconnecting data sources');
          await polygonWsClient.connect();
        }
      },
      taskName: 'market_hours_check',
    );
    
    // Schedule daily risk assessment
    AppScheduler.scheduleDaily(
      hour: 8, // Before market open
      minute: 30,
      task: () async {
        final riskAgentPort = IsolateManager.getSendPort('risk_agent');
        riskAgentPort?.send({'action': 'daily_risk_assessment'});
      },
      taskName: 'daily_risk_assessment',
    );
  }
  
  static void _startHealthMonitoring() {
    logger.i('Starting health monitoring...');
    
    Timer.periodic(const Duration(minutes: 5), (timer) {
      _performHealthChecks();
    });
  }
  
  static Future<void> _performHealthChecks() async {
    final healthStatus = <String, bool>{};
    
    // Check WebSocket connection
    healthStatus['polygon_ws'] = polygonWsClient.isConnected;
    
    // Check isolates (basic ping)
    for (final agentName in ['technical_agent', 'sentiment_agent', 'insider_agent', 'risk_agent']) {
      final sendPort = IsolateManager.getSendPort(agentName);
      healthStatus[agentName] = sendPort != null;
    }
    
    // Log unhealthy components
    final unhealthy = healthStatus.entries
        .where((entry) => !entry.value)
        .map((entry) => entry.key)
        .toList();
    
    if (unhealthy.isNotEmpty) {
      logger.w('Unhealthy components: ${unhealthy.join(', ')}');
      
      // Attempt to restart critical components
      for (final component in unhealthy) {
        if (component == 'polygon_ws') {
          logger.i('Attempting to reconnect Polygon WebSocket');
          await polygonWsClient.connect();
        }
      }
    }
  }
}

/// Flutter application widget
class TradingBotWidget extends ConsumerWidget {
  const TradingBotWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Trading Bot Dashboard',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20), // Dark green
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4CAF50), // Green
          brightness: Brightness.dark,
        ),
      ),
      home: const TradingDashboard(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Application entry point
Future<void> main(List<String> args) async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize logger
  AppLogger.initialize(level: Env.debugMode ? Level.debug : Level.info);
  
  // Initialize lifecycle manager
  AppLifecycleManager.instance.initialize();
  
  // Parse command line arguments
  final isBacktest = args.contains('--backtest');
  final isHeadless = args.contains('--headless');
  
  try {
    if (isBacktest) {
      logger.i('Starting in backtest mode');
      await _runBacktest(args);
    } else if (isHeadless) {
      logger.i('Starting in headless mode');
      await _runHeadless();
    } else {
      logger.i('Starting with GUI');
      await _runWithGUI();
    }
  } catch (e, stackTrace) {
    logger.e('Application failed to start: $e', error: e, stackTrace: stackTrace);
    AppLifecycleManager.instance.shutdown();
    rethrow;
  }
}

/// Run the application with GUI
Future<void> _runWithGUI() async {
  // Initialize the trading bot
  await TradingBotApp.initialize();
  
  // Start Flutter app
  runApp(
    const ProviderScope(
      child: TradingBotWidget(),
    ),
  );
}

/// Run the application in headless mode (no GUI)
Future<void> _runHeadless() async {
  logger.i('Running in headless mode - trading agents only');
  
  // Initialize without GUI
  await TradingBotApp.initialize();
  
  // Keep the application running
  await Completer<void>().future;
}

/// Run backtesting
Future<void> _runBacktest(List<String> args) async {
  logger.i('Starting backtest...');
  
  // Parse backtest arguments
  String? fromDate;
  String? toDate;
  String? universe;
  
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--from':
        if (i + 1 < args.length) fromDate = args[i + 1];
        break;
      case '--to':
        if (i + 1 < args.length) toDate = args[i + 1];
        break;
      case '--universe':
        if (i + 1 < args.length) universe = args[i + 1];
        break;
    }
  }
  
  if (fromDate == null || toDate == null) {
    logger.e('Backtest requires --from and --to dates');
    return;
  }
  
  // TODO: Implement backtesting logic
  logger.i('Backtest: $fromDate to $toDate, universe: ${universe ?? 'default'}');
  
  // For now, just run a simple test
  await Future.delayed(const Duration(seconds: 2));
  logger.i('Backtest completed');
}
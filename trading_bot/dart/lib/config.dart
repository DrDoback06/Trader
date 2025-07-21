import 'dart:io';
import 'package:envied/envied.dart';

part 'config.g.dart';

@Envied(path: '../.env')
abstract class Env {
  @EnviedField(varName: 'POLYGON_API_KEY')
  static const String polygonApiKey = _Env.polygonApiKey;
  
  @EnviedField(varName: 'ALPHA_VANTAGE_API_KEY')
  static const String alphaVantageApiKey = _Env.alphaVantageApiKey;
  
  @EnviedField(varName: 'T212_EMAIL')
  static const String t212Email = _Env.t212Email;
  
  @EnviedField(varName: 'T212_PASSWORD')
  static const String t212Password = _Env.t212Password;
  
  @EnviedField(varName: 'T212_MODE', defaultValue: 'demo')
  static const String t212Mode = _Env.t212Mode;
  
  @EnviedField(varName: 'POSTGRES_HOST', defaultValue: 'localhost')
  static const String postgresHost = _Env.postgresHost;
  
  @EnviedField(varName: 'POSTGRES_PORT', defaultValue: 5432)
  static const int postgresPort = _Env.postgresPort;
  
  @EnviedField(varName: 'POSTGRES_DB', defaultValue: 'trading_bot')
  static const String postgresDb = _Env.postgresDb;
  
  @EnviedField(varName: 'POSTGRES_USER', defaultValue: 'trading_user')
  static const String postgresUser = _Env.postgresUser;
  
  @EnviedField(varName: 'POSTGRES_PASSWORD')
  static const String postgresPassword = _Env.postgresPassword;
  
  @EnviedField(varName: 'REDIS_HOST', defaultValue: 'localhost')
  static const String redisHost = _Env.redisHost;
  
  @EnviedField(varName: 'REDIS_PORT', defaultValue: 6379)
  static const int redisPort = _Env.redisPort;
  
  @EnviedField(varName: 'MAX_CONCURRENT_POSITIONS', defaultValue: 5)
  static const int maxConcurrentPositions = _Env.maxConcurrentPositions;
  
  @EnviedField(varName: 'MAX_PORTFOLIO_LEVERAGE', defaultValue: 0.20)
  static const double maxPortfolioLeverage = _Env.maxPortfolioLeverage;
  
  @EnviedField(varName: 'MAX_DAILY_DRAWDOWN', defaultValue: 0.03)
  static const double maxDailyDrawdown = _Env.maxDailyDrawdown;
  
  @EnviedField(varName: 'DEFAULT_POSITION_SIZE', defaultValue: 0.02)
  static const double defaultPositionSize = _Env.defaultPositionSize;
  
  @EnviedField(varName: 'TRAILING_STOP_ATR_MULTIPLE', defaultValue: 1.5)
  static const double trailingStopAtrMultiple = _Env.trailingStopAtrMultiple;
  
  @EnviedField(varName: 'TA_SERVICE_PORT', defaultValue: 50051)
  static const int taServicePort = _Env.taServicePort;
  
  @EnviedField(varName: 'ML_SERVICE_PORT', defaultValue: 50052)
  static const int mlServicePort = _Env.mlServicePort;
  
  @EnviedField(varName: 'TRADING212_BRIDGE_PORT', defaultValue: 50053)
  static const int trading212BridgePort = _Env.trading212BridgePort;
  
  @EnviedField(varName: 'DEBUG_MODE', defaultValue: true)
  static const bool debugMode = _Env.debugMode;
  
  @EnviedField(varName: 'BACKTEST_MODE', defaultValue: false)
  static const bool backtestMode = _Env.backtestMode;
  
  @EnviedField(varName: 'STARTING_EQUITY', defaultValue: 100000.0)
  static const double startingEquity = _Env.startingEquity;
  
  @EnviedField(varName: 'USE_MARKET_ORDERS', defaultValue: false)
  static const bool useMarketOrders = _Env.useMarketOrders;
  
  @EnviedField(varName: 'ALLOW_AFTER_HOURS_TRADING', defaultValue: false)
  static const bool allowAfterHoursTrading = _Env.allowAfterHoursTrading;
  
  @EnviedField(varName: 'TRADING_BRIDGE_PORT', defaultValue: 50053)
  static const int tradingBridgePort = _Env.tradingBridgePort;
}

class AppConfig {
  static const String polygonWsUrl = 'wss://socket.polygon.io/stocks';
  static const String alphaVantageBaseUrl = 'https://www.alphavantage.co/query';
  
  // Market hours (UTC)
  static const int marketOpenHour = 14; // 9:30 AM EST
  static const int marketCloseHour = 21; // 4:00 PM EST
  
  // Technical indicator periods
  static const int rsiPeriod = 14;
  static const int macdFastPeriod = 12;
  static const int macdSlowPeriod = 26;
  static const int macdSignalPeriod = 9;
  static const int bbandsPeriod = 20;
  static const int atrPeriod = 14;
  static const int volumeAvgPeriod = 20;
  
  // Signal thresholds
  static const double rsiOversold = 30.0;
  static const double rsiOverbought = 70.0;
  static const double volumeSpikeMultiple = 2.0;
  static const double sentimentThreshold = 0.25;
  static const double signalConsensusThreshold = 1.2;
  
  // Risk management
  static const double vixThreshold = 25.0;
  static const double lowVolPositionSize = 0.01;
  static const double minStopLoss = 0.01; // 1%
  static const double rewardRiskRatio = 2.0;
  static const double maxDrawdown = 0.03; // 3%
  static const int maxPositions = 10;
  static const double maxPositionSize = 0.05; // 5%
  static const double maxPortfolioHeat = 0.15; // 15%
  
  // Database connection string
  static String get postgresConnectionString => 
    'postgresql://${Env.postgresUser}:${Env.postgresPassword}@${Env.postgresHost}:${Env.postgresPort}/${Env.postgresDb}';
  
  // Redis connection string  
  static String get redisConnectionString => 
    'redis://${Env.redisHost}:${Env.redisPort}';
    
  // gRPC service endpoints
  static String get taServiceEndpoint => 'localhost:${Env.taServicePort}';
  static String get mlServiceEndpoint => 'localhost:${Env.mlServicePort}';
  static String get trading212BridgeEndpoint => 'localhost:${Env.trading212BridgePort}';
  
  // Trading212 is in demo mode?
  static bool get isDemoMode => Env.t212Mode.toLowerCase() == 'demo';
  
  // Market is open?
  static bool get isMarketHours {
    final now = DateTime.now().toUtc();
    final hour = now.hour;
    final isWeekday = now.weekday >= 1 && now.weekday <= 5;
    return isWeekday && hour >= marketOpenHour && hour < marketCloseHour;
  }
  
  /// Initialize app configuration
  static Future<void> initialize() async {
    // Add any async initialization logic here
    await Future.delayed(Duration.zero); // Placeholder
  }
}
// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'config.dart';

// **************************************************************************
// EnviedGenerator
// **************************************************************************

class _Env {
  static const String polygonApiKey = String.fromEnvironment(
    'POLYGON_API_KEY',
    defaultValue: '',
  );

  static const String alphaVantageApiKey = String.fromEnvironment(
    'ALPHA_VANTAGE_API_KEY',
    defaultValue: '',
  );

  static const String t212Email = String.fromEnvironment(
    'T212_EMAIL',
    defaultValue: '',
  );

  static const String t212Password = String.fromEnvironment(
    'T212_PASSWORD',
    defaultValue: '',
  );

  static const String t212Mode = String.fromEnvironment(
    'T212_MODE',
    defaultValue: 'demo',
  );

  static const String postgresHost = String.fromEnvironment(
    'POSTGRES_HOST',
    defaultValue: 'localhost',
  );

  static const int postgresPort = int.fromEnvironment(
    'POSTGRES_PORT',
    defaultValue: 5432,
  );

  static const String postgresDb = String.fromEnvironment(
    'POSTGRES_DB',
    defaultValue: 'trading_bot',
  );

  static const String postgresUser = String.fromEnvironment(
    'POSTGRES_USER',
    defaultValue: 'trading_user',
  );

  static const String postgresPassword = String.fromEnvironment(
    'POSTGRES_PASSWORD',
    defaultValue: '',
  );

  static const String redisHost = String.fromEnvironment(
    'REDIS_HOST',
    defaultValue: 'localhost',
  );

  static const int redisPort = int.fromEnvironment(
    'REDIS_PORT',
    defaultValue: 6379,
  );

  static const int maxConcurrentPositions = int.fromEnvironment(
    'MAX_CONCURRENT_POSITIONS',
    defaultValue: 5,
  );

  static const double maxPortfolioLeverage = 0.20;
  static const double maxDailyDrawdown = 0.03;
  static const double defaultPositionSize = 0.02;
  static const double trailingStopAtrMultiple = 1.5;

  static const int taServicePort = int.fromEnvironment(
    'TA_SERVICE_PORT',
    defaultValue: 50051,
  );

  static const int mlServicePort = int.fromEnvironment(
    'ML_SERVICE_PORT',
    defaultValue: 50052,
  );

  static const int trading212BridgePort = int.fromEnvironment(
    'TRADING212_BRIDGE_PORT',
    defaultValue: 50053,
  );

  static const bool debugMode = bool.fromEnvironment(
    'DEBUG_MODE',
    defaultValue: true,
  );

  static const bool backtestMode = bool.fromEnvironment(
    'BACKTEST_MODE',
    defaultValue: false,
  );

  static const double startingEquity = 100000.0;

  static const bool useMarketOrders = bool.fromEnvironment(
    'USE_MARKET_ORDERS',
    defaultValue: false,
  );

  static const bool allowAfterHoursTrading = bool.fromEnvironment(
    'ALLOW_AFTER_HOURS_TRADING',
    defaultValue: false,
  );

  static const int tradingBridgePort = int.fromEnvironment(
    'TRADING_BRIDGE_PORT',
    defaultValue: 50053,
  );
}
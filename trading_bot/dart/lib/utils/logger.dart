import 'dart:io';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';

/// Custom logger for the trading bot application
class AppLogger {
  static AppLogger? _instance;
  static AppLogger get instance => _instance ??= AppLogger._();
  
  late final Logger _logger;
  late final File? _logFile;
  
  AppLogger._();
  
  /// Initialize the logger with specified configuration
  static void initialize({
    Level level = Level.info,
    bool writeToFile = true,
    String? logFilePath,
  }) {
    final logger = AppLogger.instance;
    
    // Setup log file if needed
    if (writeToFile) {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      final fileName = logFilePath ?? 'logs/trading_bot_$dateStr.log';
      
      final logFile = File(fileName);
      logFile.parent.createSync(recursive: true);
      logger._logFile = logFile;
    }
    
    logger._logger = Logger(
      filter: ProductionFilter(),
      printer: _createPrinter(),
      output: _createOutput(logger._logFile),
      level: level,
    );
  }
  
  static LogPrinter _createPrinter() {
    return PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      printTime: true,
      noBoxingByDefault: false,
    );
  }
  
  static LogOutput _createOutput(File? logFile) {
    if (logFile != null) {
      return MultiOutput([
        ConsoleOutput(),
        FileOutput(file: logFile),
      ]);
    } else {
      return ConsoleOutput();
    }
  }
  
  // Logging methods
  void t(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.t(message, error: error, stackTrace: stackTrace);
  }
  
  void d(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }
  
  void i(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }
  
  void w(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }
  
  void e(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }
  
  void f(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.f(message, error: error, stackTrace: stackTrace);
  }
  
  // Specialized logging methods for trading
  void trade(String symbol, String action, double quantity, double? price, {Map<String, dynamic>? metadata}) {
    final priceStr = price != null ? '@${price.toStringAsFixed(2)}' : 'MARKET';
    final metaStr = metadata != null ? ' | ${metadata.toString()}' : '';
    i('TRADE: $action $quantity $symbol $priceStr$metaStr');
  }
  
  void signal(String agent, String symbol, String type, double strength, {String? reason}) {
    final reasonStr = reason != null ? ' - $reason' : '';
    i('SIGNAL: [$agent] $symbol $type (${(strength * 100).toStringAsFixed(1)}%)$reasonStr');
  }
  
  void risk(String message, {String? symbol, double? value}) {
    final context = symbol != null ? '[$symbol]' : '';
    final valueStr = value != null ? ' | Value: ${value.toStringAsFixed(4)}' : '';
    w('RISK: $context $message$valueStr');
  }
  
  void performance(String metric, double value, {String? symbol, String? timeframe}) {
    final context = symbol ?? 'PORTFOLIO';
    final timeStr = timeframe != null ? ' ($timeframe)' : '';
    i('PERF: [$context] $metric: ${value.toStringAsFixed(4)}$timeStr');
  }
  
  void connection(String service, bool connected, {String? details}) {
    final status = connected ? 'CONNECTED' : 'DISCONNECTED';
    final detailStr = details != null ? ' - $details' : '';
    final logMethod = connected ? i : w;
    logMethod('CONN: $service $status$detailStr');
  }
  
  void market(String symbol, double price, int volume, {String? exchange}) {
    final exchangeStr = exchange != null ? ' [$exchange]' : '';
    d('MARKET: $symbol ${price.toStringAsFixed(2)} | Vol: $volume$exchangeStr');
  }
}

/// Custom file output that handles log rotation
class FileOutput extends LogOutput {
  final File file;
  final int maxFileSizeBytes;
  final int maxFiles;
  
  IOSink? _sink;
  
  FileOutput({
    required this.file,
    this.maxFileSizeBytes = 10 * 1024 * 1024, // 10MB
    this.maxFiles = 5,
  });
  
  @override
  void init() {
    super.init();
    _rotateLogsIfNeeded();
    _sink = file.openWrite(mode: FileMode.append);
  }
  
  @override
  void output(OutputEvent event) {
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
    
    for (final line in event.lines) {
      _sink?.writeln('[$timestamp] $line');
    }
    _sink?.flush();
    
    // Check if rotation is needed
    if (file.lengthSync() > maxFileSizeBytes) {
      _rotateLogsIfNeeded();
    }
  }
  
  @override
  void destroy() {
    super.destroy();
    _sink?.close();
  }
  
  void _rotateLogsIfNeeded() {
    if (!file.existsSync() || file.lengthSync() < maxFileSizeBytes) {
      return;
    }
    
    final baseName = file.path.replaceAll('.log', '');
    
    // Rotate existing files
    for (int i = maxFiles - 1; i >= 1; i--) {
      final oldFile = File('$baseName.${i}.log');
      final newFile = File('$baseName.${i + 1}.log');
      
      if (oldFile.existsSync()) {
        if (i == maxFiles - 1) {
          oldFile.deleteSync(); // Delete oldest
        } else {
          oldFile.renameSync(newFile.path);
        }
      }
    }
    
    // Move current file to .1
    if (file.existsSync()) {
      file.renameSync('$baseName.1.log');
    }
    
    // Create new file
    file.createSync();
    _sink?.close();
    _sink = file.openWrite(mode: FileMode.append);
  }
}

/// Filter that enables different log levels based on environment
class ProductionFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    // Always log warnings and errors
    if (event.level.index >= Level.warning.index) {
      return true;
    }
    
    // In debug mode, log everything
    if (const bool.fromEnvironment('dart.vm.product') == false) {
      return true;
    }
    
    // In production, only log info and above
    return event.level.index >= Level.info.index;
  }
}

/// Utility for creating structured log contexts
class LogContext {
  final Map<String, dynamic> _context = {};
  
  LogContext add(String key, dynamic value) {
    _context[key] = value;
    return this;
  }
  
  LogContext addSymbol(String symbol) => add('symbol', symbol);
  LogContext addAgent(String agent) => add('agent', agent);
  LogContext addAction(String action) => add('action', action);
  LogContext addValue(String key, double value) => add(key, value.toStringAsFixed(4));
  
  String format(String message) {
    if (_context.isEmpty) return message;
    
    final contextStr = _context.entries
        .map((e) => '${e.key}=${e.value}')
        .join(' ');
    
    return '$message | $contextStr';
  }
  
  @override
  String toString() => _context.toString();
}
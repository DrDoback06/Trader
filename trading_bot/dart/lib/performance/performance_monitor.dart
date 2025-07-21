import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:http/http.dart' as http;

class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();

  final Logger _logger = Logger();
  final Map<String, PerformanceMetric> _metrics = {};
  final List<LatencyMeasurement> _latencyHistory = [];
  final List<MemoryMeasurement> _memoryHistory = [];
  
  Timer? _metricsTimer;
  Timer? _reportingTimer;
  
  bool _isEnabled = true;
  bool _isInitialized = false;

  /// Initialize performance monitoring
  Future<void> initialize({
    bool enableReporting = true,
    Duration metricsInterval = const Duration(seconds: 1),
    Duration reportingInterval = const Duration(minutes: 5),
  }) async {
    if (_isInitialized) return;

    try {
      _logger.i('Initializing performance monitor');
      
      // Start metrics collection
      _metricsTimer = Timer.periodic(metricsInterval, (_) => _collectMetrics());
      
      // Start reporting (if enabled)
      if (enableReporting) {
        _reportingTimer = Timer.periodic(reportingInterval, (_) => _sendReport());
      }
      
      _isInitialized = true;
      _logger.i('Performance monitor initialized');
      
    } catch (e) {
      _logger.e('Failed to initialize performance monitor: $e');
    }
  }

  /// Start measuring latency for an operation
  LatencyMeasurement startLatencyMeasurement(String operation) {
    if (!_isEnabled) return LatencyMeasurement._dummy();
    
    return LatencyMeasurement(operation);
  }

  /// Record a completed latency measurement
  void recordLatency(LatencyMeasurement measurement) {
    if (!_isEnabled || !measurement.isCompleted) return;

    try {
      _latencyHistory.add(measurement);
      
      // Keep only recent measurements (last 1000)
      if (_latencyHistory.length > 1000) {
        _latencyHistory.removeRange(0, _latencyHistory.length - 1000);
      }

      // Update metrics
      final metric = _metrics.putIfAbsent(
        'latency_${measurement.operation}',
        () => PerformanceMetric('latency_${measurement.operation}'),
      );
      
      metric.addValue(measurement.durationMs.toDouble());

      // Log slow operations
      if (measurement.durationMs > 300) {
        _logger.w('Slow operation detected: ${measurement.operation} took ${measurement.durationMs}ms');
      }

    } catch (e) {
      _logger.e('Error recording latency: $e');
    }
  }

  /// Record custom metric
  void recordMetric(String name, double value, {String? unit}) {
    if (!_isEnabled) return;

    try {
      final metric = _metrics.putIfAbsent(name, () => PerformanceMetric(name, unit: unit));
      metric.addValue(value);
    } catch (e) {
      _logger.e('Error recording metric $name: $e');
    }
  }

  /// Record frame timing
  void recordFrameTiming(Duration frameDuration) {
    if (!_isEnabled) return;

    final frameTimeMs = frameDuration.inMicroseconds / 1000.0;
    recordMetric('frame_time_ms', frameTimeMs, unit: 'ms');
    
    // Check for jank (>16.67ms for 60fps)
    if (frameTimeMs > 16.67) {
      recordMetric('jank_frames', 1, unit: 'count');
    }
  }

  /// Record WebSocket message latency
  void recordWebSocketLatency(Duration latency) {
    recordMetric('websocket_latency_ms', latency.inMilliseconds.toDouble(), unit: 'ms');
  }

  /// Record Redis operation latency
  void recordRedisLatency(String operation, Duration latency) {
    recordMetric('redis_${operation}_latency_ms', latency.inMilliseconds.toDouble(), unit: 'ms');
  }

  /// Record gRPC call latency
  void recordGrpcLatency(String method, Duration latency) {
    recordMetric('grpc_${method}_latency_ms', latency.inMilliseconds.toDouble(), unit: 'ms');
  }

  /// Record UI update latency (from data received to UI painted)
  void recordUiUpdateLatency(String component, Duration latency) {
    recordMetric('ui_update_${component}_ms', latency.inMilliseconds.toDouble(), unit: 'ms');
  }

  /// Get current performance summary
  PerformanceSummary getSummary() {
    final now = DateTime.now();
    final recentLatencies = _latencyHistory
        .where((l) => now.difference(l.timestamp).inMinutes < 5)
        .toList();

    // Calculate percentiles for recent latencies
    final latencies = recentLatencies.map((l) => l.durationMs).toList()..sort();
    
    double getPercentile(List<int> values, double percentile) {
      if (values.isEmpty) return 0;
      final index = (values.length * percentile / 100).floor();
      return values[min(index, values.length - 1)].toDouble();
    }

    return PerformanceSummary(
      timestamp: now,
      totalOperations: _latencyHistory.length,
      recentOperations: recentLatencies.length,
      averageLatencyMs: latencies.isEmpty ? 0 : latencies.reduce((a, b) => a + b) / latencies.length,
      p50LatencyMs: getPercentile(latencies, 50),
      p95LatencyMs: getPercentile(latencies, 95),
      p99LatencyMs: getPercentile(latencies, 99),
      slowOperations: recentLatencies.where((l) => l.durationMs > 300).length,
      metrics: Map.fromEntries(_metrics.entries.map((e) => MapEntry(e.key, e.value.summary))),
    );
  }

  /// Get detailed metrics for specific operation
  MetricSummary? getMetricSummary(String metricName) {
    return _metrics[metricName]?.summary;
  }

  /// Test end-to-end latency (signal to UI update)
  Future<LatencyTestResult> testEndToEndLatency({
    int iterations = 10,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_isEnabled) {
      return LatencyTestResult(
        success: false,
        error: 'Performance monitoring disabled',
        results: [],
      );
    }

    final results = <EndToEndLatency>[];
    
    try {
      _logger.i('Starting end-to-end latency test with $iterations iterations');
      
      for (int i = 0; i < iterations; i++) {
        final testStartTime = DateTime.now();
        final measurement = startLatencyMeasurement('e2e_test_$i');
        
        // Simulate signal generation and processing
        await _simulateSignalFlow();
        
        measurement.complete();
        recordLatency(measurement);
        
        results.add(EndToEndLatency(
          iteration: i + 1,
          totalLatencyMs: measurement.durationMs,
          timestamp: testStartTime,
        ));
        
        // Wait between iterations
        if (i < iterations - 1) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      
      final avgLatency = results.map((r) => r.totalLatencyMs).reduce((a, b) => a + b) / results.length;
      
      _logger.i('End-to-end latency test completed. Average: ${avgLatency.toStringAsFixed(2)}ms');
      
      return LatencyTestResult(
        success: true,
        results: results,
        averageLatencyMs: avgLatency,
      );
      
    } catch (e) {
      _logger.e('End-to-end latency test failed: $e');
      return LatencyTestResult(
        success: false,
        error: e.toString(),
        results: results,
      );
    }
  }

  /// Test with high data volume
  Future<VolumeTestResult> testHighVolumePerformance({
    int signalsPerSecond = 100,
    Duration duration = const Duration(minutes: 1),
  }) async {
    if (!_isEnabled) {
      return VolumeTestResult(
        success: false,
        error: 'Performance monitoring disabled',
      );
    }

    try {
      _logger.i('Starting high volume test: $signalsPerSecond signals/sec for ${duration.inSeconds}s');
      
      final startTime = DateTime.now();
      int processedCount = 0;
      int droppedCount = 0;
      final latencies = <int>[];
      
      final timer = Timer.periodic(Duration(milliseconds: 1000 ~/ signalsPerSecond), (timer) {
        final measurement = startLatencyMeasurement('volume_test_signal');
        
        // Simulate signal processing
        _simulateSignalProcessing().then((_) {
          measurement.complete();
          latencies.add(measurement.durationMs);
          processedCount++;
          
          // Check for dropped signals (latency > 100ms indicates potential drop)
          if (measurement.durationMs > 100) {
            droppedCount++;
          }
        }).catchError((e) {
          droppedCount++;
        });
      });
      
      // Wait for test duration
      await Future.delayed(duration);
      timer.cancel();
      
      // Wait for any pending operations
      await Future.delayed(const Duration(milliseconds: 500));
      
      final actualDuration = DateTime.now().difference(startTime);
      final actualSignalsPerSecond = processedCount / actualDuration.inSeconds;
      final dropRate = droppedCount / (processedCount + droppedCount);
      
      _logger.i('Volume test completed: processed $processedCount, dropped $droppedCount');
      
      return VolumeTestResult(
        success: dropRate < 0.05, // Success if drop rate < 5%
        processedCount: processedCount,
        droppedCount: droppedCount,
        dropRate: dropRate,
        actualSignalsPerSecond: actualSignalsPerSecond,
        averageLatencyMs: latencies.isEmpty ? 0 : latencies.reduce((a, b) => a + b) / latencies.length,
      );
      
    } catch (e) {
      _logger.e('Volume test failed: $e');
      return VolumeTestResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  // Private methods

  Future<void> _collectMetrics() async {
    if (!_isEnabled) return;

    try {
      // Collect memory usage
      if (kDebugMode) {
        // In debug mode, we can access some memory info
        final memoryUsage = await _getMemoryUsage();
        if (memoryUsage != null) {
          _memoryHistory.add(memoryUsage);
          if (_memoryHistory.length > 1000) {
            _memoryHistory.removeAt(0);
          }
          
          recordMetric('memory_usage_mb', memoryUsage.usedMemoryMB.toDouble(), unit: 'MB');
        }
      }

      // Collect frame rate info (would need platform-specific implementation)
      
    } catch (e) {
      _logger.e('Error collecting metrics: $e');
    }
  }

  Future<MemoryMeasurement?> _getMemoryUsage() async {
    try {
      // This would need platform-specific implementation
      // For now, return a mock measurement
      return MemoryMeasurement(
        timestamp: DateTime.now(),
        usedMemoryMB: 50 + Random().nextDouble() * 20, // Mock data
        totalMemoryMB: 100,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> _sendReport() async {
    if (!_isEnabled) return;

    try {
      final summary = getSummary();
      
      // In a real implementation, send to analytics service
      _logger.d('Performance report: avg latency ${summary.averageLatencyMs.toStringAsFixed(2)}ms, '
               'operations: ${summary.recentOperations}');
      
      // Could send to external service:
      // await http.post(
      //   Uri.parse('https://analytics.yourdomain.com/metrics'),
      //   body: jsonEncode(summary.toJson()),
      // );
      
    } catch (e) {
      _logger.e('Error sending performance report: $e');
    }
  }

  Future<void> _simulateSignalFlow() async {
    // Simulate the flow: Redis → Processing → UI Update
    await Future.delayed(const Duration(milliseconds: 10)); // Redis latency
    await Future.delayed(const Duration(milliseconds: 5));  // Processing
    await Future.delayed(const Duration(milliseconds: 2));  // UI update
  }

  Future<void> _simulateSignalProcessing() async {
    await Future.delayed(const Duration(milliseconds: 1 + Random().nextInt(5)));
  }

  /// Enable/disable monitoring
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    _logger.i('Performance monitoring ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Dispose resources
  void dispose() {
    _metricsTimer?.cancel();
    _reportingTimer?.cancel();
    _metrics.clear();
    _latencyHistory.clear();
    _memoryHistory.clear();
  }
}

// Data classes
class LatencyMeasurement {
  final String operation;
  final DateTime timestamp;
  final Stopwatch _stopwatch;
  bool _isCompleted = false;

  LatencyMeasurement(this.operation)
      : timestamp = DateTime.now(),
        _stopwatch = Stopwatch()..start();

  LatencyMeasurement._dummy()
      : operation = '',
        timestamp = DateTime.now(),
        _stopwatch = Stopwatch();

  void complete() {
    if (!_isCompleted) {
      _stopwatch.stop();
      _isCompleted = true;
    }
  }

  int get durationMs => _stopwatch.elapsedMilliseconds;
  bool get isCompleted => _isCompleted;
}

class PerformanceMetric {
  final String name;
  final String? unit;
  final List<double> _values = [];
  final List<DateTime> _timestamps = [];

  PerformanceMetric(this.name, {this.unit});

  void addValue(double value) {
    _values.add(value);
    _timestamps.add(DateTime.now());
    
    // Keep only recent values (last 1000)
    if (_values.length > 1000) {
      _values.removeAt(0);
      _timestamps.removeAt(0);
    }
  }

  MetricSummary get summary {
    if (_values.isEmpty) {
      return MetricSummary(
        name: name,
        unit: unit,
        count: 0,
        average: 0,
        min: 0,
        max: 0,
        latest: 0,
      );
    }

    return MetricSummary(
      name: name,
      unit: unit,
      count: _values.length,
      average: _values.reduce((a, b) => a + b) / _values.length,
      min: _values.reduce((a, b) => a < b ? a : b),
      max: _values.reduce((a, b) => a > b ? a : b),
      latest: _values.last,
    );
  }
}

class MemoryMeasurement {
  final DateTime timestamp;
  final double usedMemoryMB;
  final double totalMemoryMB;

  MemoryMeasurement({
    required this.timestamp,
    required this.usedMemoryMB,
    required this.totalMemoryMB,
  });

  double get usagePercent => (usedMemoryMB / totalMemoryMB) * 100;
}

class PerformanceSummary {
  final DateTime timestamp;
  final int totalOperations;
  final int recentOperations;
  final double averageLatencyMs;
  final double p50LatencyMs;
  final double p95LatencyMs;
  final double p99LatencyMs;
  final int slowOperations;
  final Map<String, MetricSummary> metrics;

  PerformanceSummary({
    required this.timestamp,
    required this.totalOperations,
    required this.recentOperations,
    required this.averageLatencyMs,
    required this.p50LatencyMs,
    required this.p95LatencyMs,
    required this.p99LatencyMs,
    required this.slowOperations,
    required this.metrics,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'total_operations': totalOperations,
    'recent_operations': recentOperations,
    'average_latency_ms': averageLatencyMs,
    'p50_latency_ms': p50LatencyMs,
    'p95_latency_ms': p95LatencyMs,
    'p99_latency_ms': p99LatencyMs,
    'slow_operations': slowOperations,
    'metrics': metrics.map((k, v) => MapEntry(k, v.toJson())),
  };
}

class MetricSummary {
  final String name;
  final String? unit;
  final int count;
  final double average;
  final double min;
  final double max;
  final double latest;

  MetricSummary({
    required this.name,
    required this.unit,
    required this.count,
    required this.average,
    required this.min,
    required this.max,
    required this.latest,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'unit': unit,
    'count': count,
    'average': average,
    'min': min,
    'max': max,
    'latest': latest,
  };
}

class LatencyTestResult {
  final bool success;
  final String? error;
  final List<EndToEndLatency> results;
  final double? averageLatencyMs;

  LatencyTestResult({
    required this.success,
    this.error,
    required this.results,
    this.averageLatencyMs,
  });
}

class EndToEndLatency {
  final int iteration;
  final int totalLatencyMs;
  final DateTime timestamp;

  EndToEndLatency({
    required this.iteration,
    required this.totalLatencyMs,
    required this.timestamp,
  });
}

class VolumeTestResult {
  final bool success;
  final String? error;
  final int processedCount;
  final int droppedCount;
  final double dropRate;
  final double actualSignalsPerSecond;
  final double averageLatencyMs;

  VolumeTestResult({
    required this.success,
    this.error,
    this.processedCount = 0,
    this.droppedCount = 0,
    this.dropRate = 0,
    this.actualSignalsPerSecond = 0,
    this.averageLatencyMs = 0,
  });
}

// Extension for easy performance monitoring in widgets
extension PerformanceWidgetExtension on Widget {
  Widget withPerformanceMonitoring(String operationName) {
    return PerformanceWrapper(
      operationName: operationName,
      child: this,
    );
  }
}

class PerformanceWrapper extends StatefulWidget {
  final String operationName;
  final Widget child;

  const PerformanceWrapper({
    Key? key,
    required this.operationName,
    required this.child,
  }) : super(key: key);

  @override
  State<PerformanceWrapper> createState() => _PerformanceWrapperState();
}

class _PerformanceWrapperState extends State<PerformanceWrapper> {
  late LatencyMeasurement _measurement;

  @override
  void initState() {
    super.initState();
    _measurement = PerformanceMonitor().startLatencyMeasurement('widget_${widget.operationName}');
  }

  @override
  void didUpdateWidget(PerformanceWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.operationName != widget.operationName) {
      _measurement.complete();
      PerformanceMonitor().recordLatency(_measurement);
      _measurement = PerformanceMonitor().startLatencyMeasurement('widget_${widget.operationName}');
    }
  }

  @override
  void dispose() {
    _measurement.complete();
    PerformanceMonitor().recordLatency(_measurement);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
import 'dart:async';
import 'dart:math' as math;
import 'package:logger/logger.dart';
import '../config.dart';

/// Task execution scheduler with cron-like functionality
class AppScheduler {
  static final Map<String, ScheduledTask> _tasks = {};
  static final Map<String, Timer> _timers = {};
  static final Logger _logger = Logger();
  
  /// Schedule a task to run daily at a specific time
  static void scheduleDaily({
    required int hour,
    required int minute,
    required Future<void> Function() task,
    required String taskName,
    bool marketHoursOnly = false,
    int second = 0,
  }) {
    final scheduledTask = ScheduledTask(
      name: taskName,
      schedule: DailySchedule(hour: hour, minute: minute, second: second),
      task: task,
      marketHoursOnly: marketHoursOnly,
    );
    
    _scheduleTask(scheduledTask);
  }
  
  /// Schedule a task to run hourly at a specific minute
  static void scheduleHourly({
    required int minute,
    required Future<void> Function() task,
    required String taskName,
    bool marketHoursOnly = false,
    int second = 0,
  }) {
    final scheduledTask = ScheduledTask(
      name: taskName,
      schedule: HourlySchedule(minute: minute, second: second),
      task: task,
      marketHoursOnly: marketHoursOnly,
    );
    
    _scheduleTask(scheduledTask);
  }
  
  /// Schedule a task to run at regular intervals
  static void scheduleInterval({
    required Duration interval,
    required Future<void> Function() task,
    required String taskName,
    bool marketHoursOnly = false,
    Duration? initialDelay,
  }) {
    final scheduledTask = ScheduledTask(
      name: taskName,
      schedule: IntervalSchedule(
        interval: interval,
        initialDelay: initialDelay,
      ),
      task: task,
      marketHoursOnly: marketHoursOnly,
    );
    
    _scheduleTask(scheduledTask);
  }
  
  /// Schedule a task using cron expression
  static void scheduleCron({
    required String cronExpression,
    required Future<void> Function() task,
    required String taskName,
    bool marketHoursOnly = false,
  }) {
    final scheduledTask = ScheduledTask(
      name: taskName,
      schedule: CronSchedule(cronExpression),
      task: task,
      marketHoursOnly: marketHoursOnly,
    );
    
    _scheduleTask(scheduledTask);
  }
  
  /// Schedule a one-time task
  static void scheduleOnce({
    required DateTime when,
    required Future<void> Function() task,
    required String taskName,
  }) {
    final delay = when.difference(DateTime.now());
    
    if (delay.isNegative) {
      _logger.w('Cannot schedule task "$taskName" in the past');
      return;
    }
    
    final timer = Timer(delay, () async {
      try {
        _logger.i('Executing one-time task: $taskName');
        await task();
        _logger.i('Completed one-time task: $taskName');
      } catch (e) {
        _logger.e('One-time task "$taskName" failed: $e');
      } finally {
        _timers.remove(taskName);
      }
    });
    
    _timers[taskName] = timer;
    _logger.i('Scheduled one-time task "$taskName" for ${when.toIso8601String()}');
  }
  
  /// Cancel a scheduled task
  static void cancelTask(String taskName) {
    _timers[taskName]?.cancel();
    _timers.remove(taskName);
    _tasks.remove(taskName);
    _logger.i('Cancelled task: $taskName');
  }
  
  /// Cancel all scheduled tasks
  static void cancelAllTasks() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _tasks.clear();
    _logger.i('Cancelled all scheduled tasks');
  }
  
  /// Get list of active tasks
  static List<String> getActiveTasks() {
    return _tasks.keys.toList();
  }
  
  /// Get task details
  static ScheduledTask? getTask(String taskName) {
    return _tasks[taskName];
  }
  
  static void _scheduleTask(ScheduledTask scheduledTask) {
    // Cancel existing task with same name
    cancelTask(scheduledTask.name);
    
    _tasks[scheduledTask.name] = scheduledTask;
    
    final nextExecution = scheduledTask.schedule.nextExecution();
    final delay = nextExecution.difference(DateTime.now());
    
    final timer = Timer(delay, () => _executeTask(scheduledTask));
    _timers[scheduledTask.name] = timer;
    
    _logger.i('Scheduled task "${scheduledTask.name}" for ${nextExecution.toIso8601String()}');
  }
  
  static Future<void> _executeTask(ScheduledTask scheduledTask) async {
    try {
      // Check market hours if required
      if (scheduledTask.marketHoursOnly && !AppConfig.isMarketHours) {
        _logger.d('Skipping task "${scheduledTask.name}" - market closed');
        _scheduleNextExecution(scheduledTask);
        return;
      }
      
      _logger.i('Executing task: ${scheduledTask.name}');
      final stopwatch = Stopwatch()..start();
      
      await scheduledTask.task();
      
      stopwatch.stop();
      _logger.i('Completed task "${scheduledTask.name}" in ${stopwatch.elapsedMilliseconds}ms');
      
      scheduledTask._lastExecution = DateTime.now();
      scheduledTask._executionCount++;
      
    } catch (e, stackTrace) {
      _logger.e('Task "${scheduledTask.name}" failed: $e', stackTrace: stackTrace);
      scheduledTask._failureCount++;
      
      // Exponential backoff for failed tasks
      if (scheduledTask._failureCount > 3) {
        final backoffSeconds = math.min(300, math.pow(2, scheduledTask._failureCount).toInt());
        _logger.w('Task "${scheduledTask.name}" has failed ${scheduledTask._failureCount} times. Next execution delayed by ${backoffSeconds}s');
        
        Timer(Duration(seconds: backoffSeconds), () => _scheduleNextExecution(scheduledTask));
        return;
      }
    }
    
    _scheduleNextExecution(scheduledTask);
  }
  
  static void _scheduleNextExecution(ScheduledTask scheduledTask) {
    final nextExecution = scheduledTask.schedule.nextExecution();
    final delay = nextExecution.difference(DateTime.now());
    
    final timer = Timer(delay, () => _executeTask(scheduledTask));
    _timers[scheduledTask.name] = timer;
    
    _logger.d('Next execution of "${scheduledTask.name}" scheduled for ${nextExecution.toIso8601String()}');
  }
}

/// Represents a scheduled task
class ScheduledTask {
  final String name;
  final Schedule schedule;
  final Future<void> Function() task;
  final bool marketHoursOnly;
  
  DateTime? _lastExecution;
  int _executionCount = 0;
  int _failureCount = 0;
  
  ScheduledTask({
    required this.name,
    required this.schedule,
    required this.task,
    this.marketHoursOnly = false,
  });
  
  DateTime? get lastExecution => _lastExecution;
  int get executionCount => _executionCount;
  int get failureCount => _failureCount;
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'schedule': schedule.toString(),
    'marketHoursOnly': marketHoursOnly,
    'lastExecution': _lastExecution?.toIso8601String(),
    'executionCount': _executionCount,
    'failureCount': _failureCount,
  };
}

/// Base class for schedules
abstract class Schedule {
  DateTime nextExecution();
  
  @override
  String toString();
}

/// Daily schedule
class DailySchedule extends Schedule {
  final int hour;
  final int minute;
  final int second;
  
  DailySchedule({
    required this.hour,
    required this.minute,
    this.second = 0,
  }) {
    if (hour < 0 || hour > 23) throw ArgumentError('Hour must be between 0 and 23');
    if (minute < 0 || minute > 59) throw ArgumentError('Minute must be between 0 and 59');
    if (second < 0 || second > 59) throw ArgumentError('Second must be between 0 and 59');
  }
  
  @override
  DateTime nextExecution() {
    final now = DateTime.now().toUtc();
    var next = DateTime.utc(now.year, now.month, now.day, hour, minute, second);
    
    if (next.isBefore(now) || next.isAtSameMomentAs(now)) {
      next = next.add(const Duration(days: 1));
    }
    
    return next;
  }
  
  @override
  String toString() => 'Daily at ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')} UTC';
}

/// Hourly schedule
class HourlySchedule extends Schedule {
  final int minute;
  final int second;
  
  HourlySchedule({
    required this.minute,
    this.second = 0,
  }) {
    if (minute < 0 || minute > 59) throw ArgumentError('Minute must be between 0 and 59');
    if (second < 0 || second > 59) throw ArgumentError('Second must be between 0 and 59');
  }
  
  @override
  DateTime nextExecution() {
    final now = DateTime.now().toUtc();
    var next = DateTime.utc(now.year, now.month, now.day, now.hour, minute, second);
    
    if (next.isBefore(now) || next.isAtSameMomentAs(now)) {
      next = next.add(const Duration(hours: 1));
    }
    
    return next;
  }
  
  @override
  String toString() => 'Hourly at :${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
}

/// Interval schedule
class IntervalSchedule extends Schedule {
  final Duration interval;
  final Duration? initialDelay;
  DateTime? _lastExecution;
  
  IntervalSchedule({
    required this.interval,
    this.initialDelay,
  });
  
  @override
  DateTime nextExecution() {
    final now = DateTime.now().toUtc();
    
    if (_lastExecution == null) {
      return now.add(initialDelay ?? Duration.zero);
    }
    
    return _lastExecution!.add(interval);
  }
  
  void _markExecuted() {
    _lastExecution = DateTime.now().toUtc();
  }
  
  @override
  String toString() => 'Every ${interval.inSeconds}s${initialDelay != null ? ' (initial delay: ${initialDelay!.inSeconds}s)' : ''}';
}

/// Cron-like schedule
class CronSchedule extends Schedule {
  final String expression;
  late final CronExpression _cron;
  
  CronSchedule(this.expression) {
    _cron = CronExpression.parse(expression);
  }
  
  @override
  DateTime nextExecution() {
    return _cron.next(DateTime.now().toUtc());
  }
  
  @override
  String toString() => 'Cron: $expression';
}

/// Simple cron expression parser
class CronExpression {
  final List<int>? minutes;
  final List<int>? hours;
  final List<int>? daysOfMonth;
  final List<int>? months;
  final List<int>? daysOfWeek;
  
  CronExpression({
    this.minutes,
    this.hours,
    this.daysOfMonth,
    this.months,
    this.daysOfWeek,
  });
  
  static CronExpression parse(String expression) {
    final parts = expression.split(' ');
    if (parts.length != 5) {
      throw ArgumentError('Cron expression must have 5 parts: minute hour day month day-of-week');
    }
    
    return CronExpression(
      minutes: _parseField(parts[0], 0, 59),
      hours: _parseField(parts[1], 0, 23),
      daysOfMonth: _parseField(parts[2], 1, 31),
      months: _parseField(parts[3], 1, 12),
      daysOfWeek: _parseField(parts[4], 0, 6),
    );
  }
  
  static List<int>? _parseField(String field, int min, int max) {
    if (field == '*') return null;
    
    final values = <int>[];
    
    for (final part in field.split(',')) {
      if (part.contains('/')) {
        final stepParts = part.split('/');
        final range = stepParts[0] == '*' ? '$min-$max' : stepParts[0];
        final step = int.parse(stepParts[1]);
        
        if (range.contains('-')) {
          final rangeParts = range.split('-');
          final start = int.parse(rangeParts[0]);
          final end = int.parse(rangeParts[1]);
          
          for (int i = start; i <= end; i += step) {
            values.add(i);
          }
        } else {
          final start = int.parse(range);
          for (int i = start; i <= max; i += step) {
            values.add(i);
          }
        }
      } else if (part.contains('-')) {
        final rangeParts = part.split('-');
        final start = int.parse(rangeParts[0]);
        final end = int.parse(rangeParts[1]);
        
        for (int i = start; i <= end; i++) {
          values.add(i);
        }
      } else {
        values.add(int.parse(part));
      }
    }
    
    return values.isEmpty ? null : values;
  }
  
  DateTime next(DateTime from) {
    var candidate = DateTime.utc(
      from.year,
      from.month,
      from.day,
      from.hour,
      from.minute,
    ).add(const Duration(minutes: 1));
    
    // Find next valid time (brute force, but efficient for reasonable timeframes)
    for (int i = 0; i < 366 * 24 * 60; i++) { // Search up to 1 year
      if (_matches(candidate)) {
        return candidate;
      }
      candidate = candidate.add(const Duration(minutes: 1));
    }
    
    throw StateError('Could not find next execution time within 1 year');
  }
  
  bool _matches(DateTime time) {
    if (minutes != null && !minutes!.contains(time.minute)) return false;
    if (hours != null && !hours!.contains(time.hour)) return false;
    if (daysOfMonth != null && !daysOfMonth!.contains(time.day)) return false;
    if (months != null && !months!.contains(time.month)) return false;
    if (daysOfWeek != null && !daysOfWeek!.contains(time.weekday % 7)) return false;
    
    return true;
  }
}
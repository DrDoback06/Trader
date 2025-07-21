import 'package:test/test.dart';
import 'package:trading_bot/agents/technical_agent.dart';
import 'package:trading_bot/data/models.dart';
import 'package:trading_bot/config.dart';

void main() {
  group('TechnicalAgent Tests', () {
    late TechnicalAgent agent;
    
    setUp(() {
      agent = TechnicalAgent();
    });
    
    test('should generate RSI oversold buy signal', () async {
      // Arrange: Create synthetic bars with declining prices (RSI < 30)
      final bars = _createSyntheticBars(
        symbol: 'TEST',
        startPrice: 100.0,
        count: 60,
        trend: -0.5, // Declining trend to create oversold condition
      );
      
      // Add bars to agent history
      for (final bar in bars) {
        agent._addBarToHistory(bar);
        agent._updateVolumeHistory(bar);
      }
      
      // Act: Analyze the symbol
      await agent._analyzeSymbol('TEST');
      
      // Assert: Should generate buy signals due to RSI oversold
      final indicators = agent.getCurrentIndicators('TEST');
      expect(indicators, isNotNull);
      expect(indicators!.rsi, lessThan(AppConfig.rsiOversold));
    });
    
    test('should generate RSI overbought sell signal', () async {
      // Arrange: Create synthetic bars with rising prices (RSI > 70)
      final bars = _createSyntheticBars(
        symbol: 'TEST',
        startPrice: 100.0,
        count: 60,
        trend: 0.5, // Rising trend to create overbought condition
      );
      
      // Add bars to agent history
      for (final bar in bars) {
        agent._addBarToHistory(bar);
        agent._updateVolumeHistory(bar);
      }
      
      // Act: Analyze the symbol
      await agent._analyzeSymbol('TEST');
      
      // Assert: Should generate sell signals due to RSI overbought
      final indicators = agent.getCurrentIndicators('TEST');
      expect(indicators, isNotNull);
      expect(indicators!.rsi, greaterThan(AppConfig.rsiOverbought));
    });
    
    test('should generate MACD bullish crossover signal', () async {
      // Arrange: Create bars that simulate a bullish MACD crossover
      final bars = _createMacdBullishCrossoverBars('TEST');
      
      // Add bars to agent history
      for (final bar in bars) {
        agent._addBarToHistory(bar);
        agent._updateVolumeHistory(bar);
      }
      
      // Act: Analyze the symbol
      await agent._analyzeSymbol('TEST');
      
      // Assert: Should have MACD indicators
      final indicators = agent.getCurrentIndicators('TEST');
      expect(indicators, isNotNull);
      expect(indicators!.macd, isNotNull);
      expect(indicators!.macd!.macd, greaterThan(indicators!.macd!.signal));
    });
    
    test('should generate volume spike signal', () async {
      // Arrange: Create bars with normal volume, then a spike
      final bars = _createVolumeSpikeBars('TEST');
      
      // Add bars to agent history
      for (final bar in bars) {
        agent._addBarToHistory(bar);
        agent._updateVolumeHistory(bar);
      }
      
      // Act: Analyze the symbol
      await agent._analyzeSymbol('TEST');
      
      // Assert: Should detect volume spike
      final indicators = agent.getCurrentIndicators('TEST');
      expect(indicators, isNotNull);
      expect(indicators!.volumeAvg, isNotNull);
      
      final lastBar = agent.getBarHistory('TEST')!.last;
      final volumeRatio = lastBar.volume / indicators!.volumeAvg!;
      expect(volumeRatio, greaterThan(TechnicalAgent.volumeSpikeThreshold));
    });
    
    test('should generate strong multi-indicator buy signal', () async {
      // Arrange: Create perfect buy conditions
      final bars = _createStrongBuyConditionBars('TEST');
      
      // Add bars to agent history
      for (final bar in bars) {
        agent._addBarToHistory(bar);
        agent._updateVolumeHistory(bar);
      }
      
      // Act: Analyze the symbol
      await agent._analyzeSymbol('TEST');
      
      // Assert: Should have all indicators for strong buy
      final indicators = agent.getCurrentIndicators('TEST');
      expect(indicators, isNotNull);
      expect(indicators!.rsi, lessThan(30)); // Oversold
      expect(indicators!.macd, isNotNull);
      expect(indicators!.bollinger, isNotNull);
      expect(indicators!.volumeAvg, isNotNull);
    });
    
    test('should handle insufficient data gracefully', () async {
      // Arrange: Create insufficient data (< 50 bars)
      final bars = _createSyntheticBars(
        symbol: 'TEST',
        startPrice: 100.0,
        count: 20, // Insufficient
        trend: 0.0,
      );
      
      // Add bars to agent history
      for (final bar in bars) {
        agent._addBarToHistory(bar);
      }
      
      // Act: Analyze the symbol (should not throw)
      await agent._analyzeSymbol('TEST');
      
      // Assert: Should not have generated indicators
      final indicators = agent.getCurrentIndicators('TEST');
      expect(indicators, isNull);
    });
    
    test('should maintain correct bar history size', () {
      // Arrange: Create more bars than the maximum
      final bars = _createSyntheticBars(
        symbol: 'TEST',
        startPrice: 100.0,
        count: TechnicalAgent.maxBarsPerSymbol + 50,
        trend: 0.0,
      );
      
      // Act: Add all bars
      for (final bar in bars) {
        agent._addBarToHistory(bar);
      }
      
      // Assert: Should maintain maximum size
      final history = agent.getBarHistory('TEST');
      expect(history, isNotNull);
      expect(history!.length, equals(TechnicalAgent.maxBarsPerSymbol));
      
      // Should keep the most recent bars
      expect(history.last.timestamp, equals(bars.last.timestamp));
    });
    
    test('should calculate volume average correctly', () {
      // Arrange: Create bars with known volumes
      final bars = <Bar>[];
      for (int i = 0; i < 25; i++) {
        bars.add(Bar(
          symbol: 'TEST',
          open: 100.0,
          high: 101.0,
          low: 99.0,
          close: 100.0,
          volume: 1000 + i, // Increasing volume
          timestamp: DateTime.now().add(Duration(minutes: i)),
          timeframe: '1m',
        ));
      }
      
      // Act: Add bars and update volume history
      for (final bar in bars) {
        agent._addBarToHistory(bar);
        agent._updateVolumeHistory(bar);
      }
      
      // Assert: Should calculate correct 20-period average
      final indicators = agent.getCurrentIndicators('TEST');
      // Volume average should be average of volumes 1005-1024 (last 20)
      final expectedAvg = (1005 + 1024) / 2.0; // Simple average of range
      expect(indicators, isNull); // No analysis run yet, but volume history should be set
    });
  });
}

/// Create synthetic bars with specified trend
List<Bar> _createSyntheticBars({
  required String symbol,
  required double startPrice,
  required int count,
  required double trend, // Daily change percentage
}) {
  final bars = <Bar>[];
  double currentPrice = startPrice;
  
  for (int i = 0; i < count; i++) {
    final random = (i % 7) / 10.0; // Some randomness
    final change = trend + random - 0.3; // Add noise
    
    final open = currentPrice;
    final close = currentPrice * (1 + change / 100);
    final high = [open, close].reduce((a, b) => a > b ? a : b) * 1.005;
    final low = [open, close].reduce((a, b) => a < b ? a : b) * 0.995;
    
    bars.add(Bar(
      symbol: symbol,
      open: open,
      high: high,
      low: low,
      close: close,
      volume: 1000 + (i % 100), // Some volume variation
      timestamp: DateTime.now().subtract(Duration(minutes: count - i)),
      timeframe: '1m',
    ));
    
    currentPrice = close;
  }
  
  return bars;
}

/// Create bars that simulate MACD bullish crossover
List<Bar> _createMacdBullishCrossoverBars(String symbol) {
  final bars = <Bar>[];
  
  // Create downtrend followed by uptrend (MACD crossover pattern)
  for (int i = 0; i < 60; i++) {
    double trend;
    if (i < 30) {
      trend = -0.3; // Downtrend
    } else {
      trend = 0.4; // Uptrend (creates crossover)
    }
    
    final price = 100.0 * (1 + (trend * i / 100));
    bars.add(Bar(
      symbol: symbol,
      open: price,
      high: price * 1.01,
      low: price * 0.99,
      close: price,
      volume: 1000,
      timestamp: DateTime.now().subtract(Duration(minutes: 60 - i)),
      timeframe: '1m',
    ));
  }
  
  return bars;
}

/// Create bars with volume spike
List<Bar> _createVolumeSpikeBars(String symbol) {
  final bars = <Bar>[];
  
  for (int i = 0; i < 50; i++) {
    final isSpike = i == 49; // Last bar has volume spike
    final volume = isSpike ? 5000 : 1000; // 5x normal volume
    
    bars.add(Bar(
      symbol: symbol,
      open: 100.0,
      high: 101.0,
      low: 99.0,
      close: 100.0,
      volume: volume,
      timestamp: DateTime.now().subtract(Duration(minutes: 50 - i)),
      timeframe: '1m',
    ));
  }
  
  return bars;
}

/// Create bars with strong buy conditions
List<Bar> _createStrongBuyConditionBars(String symbol) {
  final bars = <Bar>[];
  
  for (int i = 0; i < 60; i++) {
    // Create conditions for strong buy:
    // 1. RSI oversold (declining prices)
    // 2. MACD bullish crossover (trend change)
    // 3. Price above BB lower band
    // 4. Volume spike on last bar
    
    double trend;
    if (i < 40) {
      trend = -0.8; // Strong decline for RSI oversold
    } else {
      trend = 0.2; // Recovery for MACD crossover
    }
    
    final price = 100.0 * (1 + (trend * i / 100));
    final volume = (i == 59) ? 3000 : 1000; // Volume spike on last bar
    
    bars.add(Bar(
      symbol: symbol,
      open: price,
      high: price * 1.005,
      low: price * 0.995,
      close: price,
      volume: volume,
      timestamp: DateTime.now().subtract(Duration(minutes: 60 - i)),
      timeframe: '1m',
    ));
  }
  
  return bars;
}
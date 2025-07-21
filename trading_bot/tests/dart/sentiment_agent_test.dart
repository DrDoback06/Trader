import 'package:test/test.dart';
import 'package:trading_bot/agents/sentiment_agent.dart';
import 'package:trading_bot/data/models.dart';

void main() {
  group('SentimentAgent Tests', () {
    late SentimentAgent agent;
    
    setUp(() {
      agent = SentimentAgent();
    });
    
    test('should generate buy signal for bullish sentiment', () {
      // Arrange: Bullish sentiment (>= 0.25)
      const symbol = 'TEST';
      const sentiment = 0.35;
      
      // Act: Generate signals
      final signals = agent._generateSentimentSignals(symbol, sentiment);
      
      // Assert: Should generate buy signal
      expect(signals, hasLength(1));
      expect(signals.first.type, equals(SignalType.buy));
      expect(signals.first.symbol, equals(symbol));
      expect(signals.first.strength, greaterThan(0.0));
      expect(signals.first.metadata['sentiment'], equals(sentiment));
      expect(signals.first.metadata['reason'], contains('Bullish sentiment'));
    });
    
    test('should generate strong buy signal for strong bullish sentiment', () {
      // Arrange: Strong bullish sentiment (>= 0.6)
      const symbol = 'TEST';
      const sentiment = 0.7;
      
      // Act: Generate signals
      final signals = agent._generateSentimentSignals(symbol, sentiment);
      
      // Assert: Should generate strong buy signal
      expect(signals, hasLength(1));
      expect(signals.first.type, equals(SignalType.buy));
      expect(signals.first.strength, equals(0.8));
      expect(signals.first.metadata['reason'], contains('Strong bullish sentiment'));
    });
    
    test('should generate sell signal for bearish sentiment', () {
      // Arrange: Bearish sentiment (<= -0.4)
      const symbol = 'TEST';
      const sentiment = -0.5;
      
      // Act: Generate signals
      final signals = agent._generateSentimentSignals(symbol, sentiment);
      
      // Assert: Should generate sell signal
      expect(signals, hasLength(1));
      expect(signals.first.type, equals(SignalType.sell));
      expect(signals.first.symbol, equals(symbol));
      expect(signals.first.strength, greaterThan(0.0));
      expect(signals.first.metadata['sentiment'], equals(sentiment));
      expect(signals.first.metadata['reason'], contains('Bearish sentiment'));
    });
    
    test('should generate block signal for strong bearish sentiment', () {
      // Arrange: Strong bearish sentiment (<= -0.6)
      const symbol = 'TEST';
      const sentiment = -0.8;
      
      // Act: Generate signals
      final signals = agent._generateSentimentSignals(symbol, sentiment);
      
      // Assert: Should generate block signal
      expect(signals, hasLength(1));
      expect(signals.first.type, equals(SignalType.sell));
      expect(signals.first.strength, equals(0.9));
      expect(signals.first.metadata['reason'], contains('Strong bearish sentiment'));
      expect(signals.first.metadata['block_trading'], equals(true));
    });
    
    test('should not generate signals for neutral sentiment', () {
      // Arrange: Neutral sentiment (between -0.4 and 0.25)
      const symbol = 'TEST';
      const sentiment = 0.1;
      
      // Act: Generate signals
      final signals = agent._generateSentimentSignals(symbol, sentiment);
      
      // Assert: Should not generate any signals
      expect(signals, isEmpty);
    });
    
    test('should calculate proper strength for bullish sentiment', () {
      // Arrange: Test different bullish sentiment levels
      const symbol = 'TEST';
      
      // Test minimum bullish threshold
      final signalsMin = agent._generateSentimentSignals(symbol, 0.25);
      expect(signalsMin.first.strength, greaterThanOrEqualTo(0.2));
      expect(signalsMin.first.strength, lessThan(0.6));
      
      // Test maximum bullish (before strong threshold)
      final signalsMax = agent._generateSentimentSignals(symbol, 0.59);
      expect(signalsMax.first.strength, lessThanOrEqualTo(0.6));
    });
    
    test('should calculate proper strength for bearish sentiment', () {
      // Arrange: Test different bearish sentiment levels
      const symbol = 'TEST';
      
      // Test minimum bearish threshold
      final signalsMin = agent._generateSentimentSignals(symbol, -0.4);
      expect(signalsMin.first.strength, greaterThanOrEqualTo(0.2));
      expect(signalsMin.first.strength, lessThan(0.5));
      
      // Test maximum bearish (before strong threshold)
      final signalsMax = agent._generateSentimentSignals(symbol, -0.59);
      expect(signalsMax.first.strength, lessThanOrEqualTo(0.5));
    });
    
    test('should cache sentiment scores with timestamps', () {
      // Arrange
      const symbol = 'TEST';
      const sentiment = 0.5;
      
      // Act: Cache sentiment
      agent._cacheSentiment(symbol, sentiment);
      
      // Assert: Should be cached
      final cached = agent.getCurrentSentiment(symbol);
      expect(cached, equals(sentiment));
    });
    
    test('should return cached sentiment if still valid', () {
      // Arrange: Cache a sentiment score
      const symbol = 'TEST';
      const sentiment = 0.3;
      agent._cacheSentiment(symbol, sentiment);
      
      // Act: Get cached sentiment
      final cached = agent._getCachedSentiment(symbol);
      
      // Assert: Should return cached value
      expect(cached, equals(sentiment));
    });
    
    test('should not return expired cached sentiment', () {
      // Arrange: Cache a sentiment score with old timestamp
      const symbol = 'TEST';
      const sentiment = 0.3;
      
      // Manually set old timestamp
      agent._sentimentCache[symbol] = sentiment;
      agent._cacheTimestamps[symbol] = DateTime.now().subtract(
        const Duration(minutes: 10), // Older than cache duration
      );
      
      // Act: Try to get cached sentiment
      final cached = agent._getCachedSentiment(symbol);
      
      // Assert: Should return null for expired cache
      expect(cached, isNull);
      expect(agent.getCurrentSentiment(symbol), isNull);
    });
    
    test('should provide accurate cache statistics', () {
      // Arrange: Add some cached entries
      agent._cacheSentiment('AAPL', 0.5);
      agent._cacheSentiment('MSFT', 0.3);
      agent._cacheSentiment('GOOGL', -0.2);
      
      // Add one expired entry
      agent._sentimentCache['OLD'] = 0.1;
      agent._cacheTimestamps['OLD'] = DateTime.now().subtract(
        const Duration(minutes: 10),
      );
      
      // Act: Get cache stats
      final stats = agent.getCacheStats();
      
      // Assert: Should show correct statistics
      expect(stats['total_cached'], equals(4));
      expect(stats['valid_entries'], equals(3)); // Excluding expired
      expect(stats['cache_duration_minutes'], equals(5));
    });
    
    test('should clean up expired cache entries', () {
      // Arrange: Add valid and expired entries
      agent._cacheSentiment('VALID', 0.5);
      
      // Add expired entries manually
      agent._sentimentCache['EXPIRED1'] = 0.1;
      agent._sentimentCache['EXPIRED2'] = 0.2;
      agent._cacheTimestamps['EXPIRED1'] = DateTime.now().subtract(
        const Duration(minutes: 10),
      );
      agent._cacheTimestamps['EXPIRED2'] = DateTime.now().subtract(
        const Duration(minutes: 15),
      );
      
      expect(agent._sentimentCache.length, equals(3));
      
      // Act: Clean up cache
      agent._cleanupCache();
      
      // Assert: Should remove expired entries
      expect(agent._sentimentCache.length, equals(1));
      expect(agent._sentimentCache.containsKey('VALID'), isTrue);
      expect(agent._sentimentCache.containsKey('EXPIRED1'), isFalse);
      expect(agent._sentimentCache.containsKey('EXPIRED2'), isFalse);
    });
    
    test('should handle edge case sentiment values', () {
      const symbol = 'TEST';
      
      // Test exact threshold values
      final signalsExactBullish = agent._generateSentimentSignals(symbol, 0.25);
      expect(signalsExactBullish, hasLength(1));
      expect(signalsExactBullish.first.type, equals(SignalType.buy));
      
      final signalsExactBearish = agent._generateSentimentSignals(symbol, -0.4);
      expect(signalsExactBearish, hasLength(1));
      expect(signalsExactBearish.first.type, equals(SignalType.sell));
      
      final signalsExactStrongBullish = agent._generateSentimentSignals(symbol, 0.6);
      expect(signalsExactStrongBullish, hasLength(1));
      expect(signalsExactStrongBullish.first.strength, equals(0.8));
      
      final signalsExactStrongBearish = agent._generateSentimentSignals(symbol, -0.6);
      expect(signalsExactStrongBearish, hasLength(1));
      expect(signalsExactStrongBearish.first.strength, equals(0.9));
    });
    
    test('should handle extreme sentiment values', () {
      const symbol = 'TEST';
      
      // Test extreme positive sentiment
      final signalsMax = agent._generateSentimentSignals(symbol, 1.0);
      expect(signalsMax, hasLength(1));
      expect(signalsMax.first.type, equals(SignalType.buy));
      expect(signalsMax.first.strength, equals(0.8));
      
      // Test extreme negative sentiment
      final signalsMin = agent._generateSentimentSignals(symbol, -1.0);
      expect(signalsMin, hasLength(1));
      expect(signalsMin.first.type, equals(SignalType.sell));
      expect(signalsMin.first.strength, equals(0.9));
      expect(signalsMin.first.metadata['block_trading'], equals(true));
    });
    
    test('should include proper metadata in signals', () {
      const symbol = 'TEST';
      const sentiment = 0.4;
      
      final signals = agent._generateSentimentSignals(symbol, sentiment);
      final signal = signals.first;
      
      expect(signal.metadata, containsPair('sentiment', sentiment));
      expect(signal.metadata, containsPair('threshold', SentimentAgent.bullishThreshold));
      expect(signal.metadata, contains('reason'));
      expect(signal.source, equals(SentimentAgent.agentName));
    });
  });
  
  group('SentimentAgent Integration Tests', () {
    test('should handle sentiment analysis workflow', () async {
      // This test would require mocking the Alpha Vantage client
      // For now, we'll test the workflow structure
      final agent = SentimentAgent();
      
      // The workflow should be:
      // 1. Get sentiment score (from cache or API)
      // 2. Generate signals based on sentiment
      // 3. Publish signals to Redis
      
      // This would be implemented with proper mocking in a real test environment
      expect(agent.agentName, equals('sentiment_agent'));
    });
  });
}
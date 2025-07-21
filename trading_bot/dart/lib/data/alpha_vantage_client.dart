import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../config.dart';
import 'models.dart';

class AlphaVantageClient {
  late final Dio _dio;
  final Logger _logger = Logger();
  
  // Rate limiting
  static const int _requestsPerMinute = 5; // Free tier limit
  final Queue<DateTime> _requestTimes = Queue<DateTime>();
  
  AlphaVantageClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.alphaVantageBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 2),
    ));
    
    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      logPrint: (obj) => _logger.d(obj),
    ));
  }
  
  Future<void> _checkRateLimit() async {
    final now = DateTime.now();
    
    // Remove requests older than 1 minute
    while (_requestTimes.isNotEmpty && 
           now.difference(_requestTimes.first).inMinutes >= 1) {
      _requestTimes.removeFirst();
    }
    
    // If we've made too many requests, wait
    if (_requestTimes.length >= _requestsPerMinute) {
      final oldestRequest = _requestTimes.first;
      final waitTime = const Duration(minutes: 1) - now.difference(oldestRequest);
      
      if (waitTime.inMilliseconds > 0) {
        _logger.i('Rate limit reached, waiting ${waitTime.inSeconds} seconds');
        await Future.delayed(waitTime);
      }
    }
    
    _requestTimes.add(now);
  }
  
  Future<Map<String, dynamic>> _makeRequest(Map<String, String> params) async {
    await _checkRateLimit();
    
    final queryParams = {
      'apikey': Env.alphaVantageApiKey,
      ...params,
    };
    
    try {
      final response = await _dio.get('', queryParameters: queryParams);
      
      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        
        // Check for API errors
        if (data.containsKey('Error Message')) {
          throw AlphaVantageException(data['Error Message']);
        }
        
        if (data.containsKey('Note')) {
          throw AlphaVantageException('Rate limit exceeded: ${data['Note']}');
        }
        
        return data;
      } else {
        throw AlphaVantageException('Invalid response format');
      }
    } on DioException catch (e) {
      _logger.e('API request failed: ${e.message}');
      throw AlphaVantageException('Request failed: ${e.message}');
    }
  }
  
  /// Get intraday data for a symbol
  Future<List<Bar>> getIntradayData(String symbol, {
    String interval = '1min',
    String outputSize = 'compact',
  }) async {
    _logger.i('Fetching intraday data for $symbol');
    
    final data = await _makeRequest({
      'function': 'TIME_SERIES_INTRADAY',
      'symbol': symbol,
      'interval': interval,
      'outputsize': outputSize,
    });
    
    final timeSeriesKey = 'Time Series ($interval)';
    final timeSeries = data[timeSeriesKey] as Map<String, dynamic>?;
    
    if (timeSeries == null) {
      throw AlphaVantageException('No time series data found for $symbol');
    }
    
    final bars = <Bar>[];
    
    for (final entry in timeSeries.entries) {
      final timestamp = DateTime.parse(entry.key);
      final ohlcv = entry.value as Map<String, dynamic>;
      
      bars.add(Bar(
        symbol: symbol,
        open: double.parse(ohlcv['1. open']),
        high: double.parse(ohlcv['2. high']),
        low: double.parse(ohlcv['3. low']),
        close: double.parse(ohlcv['4. close']),
        volume: int.parse(ohlcv['5. volume']),
        timestamp: timestamp,
        timeframe: interval,
      ));
    }
    
    // Sort by timestamp ascending
    bars.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    _logger.i('Retrieved ${bars.length} bars for $symbol');
    return bars;
  }
  
  /// Get daily data for a symbol
  Future<List<Bar>> getDailyData(String symbol, {
    String outputSize = 'compact',
  }) async {
    _logger.i('Fetching daily data for $symbol');
    
    final data = await _makeRequest({
      'function': 'TIME_SERIES_DAILY',
      'symbol': symbol,
      'outputsize': outputSize,
    });
    
    final timeSeries = data['Time Series (Daily)'] as Map<String, dynamic>?;
    
    if (timeSeries == null) {
      throw AlphaVantageException('No daily data found for $symbol');
    }
    
    final bars = <Bar>[];
    
    for (final entry in timeSeries.entries) {
      final timestamp = DateTime.parse(entry.key);
      final ohlcv = entry.value as Map<String, dynamic>;
      
      bars.add(Bar(
        symbol: symbol,
        open: double.parse(ohlcv['1. open']),
        high: double.parse(ohlcv['2. high']),
        low: double.parse(ohlcv['3. low']),
        close: double.parse(ohlcv['4. close']),
        volume: int.parse(ohlcv['5. volume']),
        timestamp: timestamp,
        timeframe: '1d',
      ));
    }
    
    bars.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    _logger.i('Retrieved ${bars.length} daily bars for $symbol');
    return bars;
  }
  
  /// Get insider trading data
  Future<List<InsiderTransaction>> getInsiderTrading(String symbol) async {
    _logger.i('Fetching insider trading data for $symbol');
    
    try {
      final data = await _makeRequest({
        'function': 'INSIDER_TRANSACTIONS',
        'symbol': symbol,
      });
      
      final transactions = <InsiderTransaction>[];
      final transactionData = data['data'] as List<dynamic>?;
      
      if (transactionData != null) {
        for (final transaction in transactionData) {
          final tx = transaction as Map<String, dynamic>;
          
          transactions.add(InsiderTransaction(
            symbol: symbol,
            insiderName: tx['name'] ?? '',
            title: tx['title'] ?? '',
            transactionType: _parseTransactionType(tx['transaction']),
            shares: double.tryParse(tx['shares']?.toString() ?? '0') ?? 0,
            price: double.tryParse(tx['price']?.toString()),
            value: double.tryParse(tx['value']?.toString()),
            filingDate: DateTime.tryParse(tx['filing_date'] ?? '') ?? DateTime.now(),
            transactionDate: DateTime.tryParse(tx['transaction_date'] ?? '') ?? DateTime.now(),
          ));
        }
      }
      
      _logger.i('Retrieved ${transactions.length} insider transactions for $symbol');
      return transactions;
      
    } catch (e) {
      _logger.w('Failed to fetch insider data for $symbol: $e');
      return [];
    }
  }
  
  /// Get news sentiment for a symbol
  Future<List<NewsItem>> getNewsSentiment(String symbol, {
    int limit = 50,
  }) async {
    _logger.i('Fetching news sentiment for $symbol');
    
    try {
      final data = await _makeRequest({
        'function': 'NEWS_SENTIMENT',
        'tickers': symbol,
        'limit': limit.toString(),
      });
      
      final newsItems = <NewsItem>[];
      final feed = data['feed'] as List<dynamic>?;
      
      if (feed != null) {
        for (final item in feed) {
          final newsData = item as Map<String, dynamic>;
          
          // Extract symbols from ticker sentiment
          final symbols = <String>[];
          final tickerSentiment = newsData['ticker_sentiment'] as List<dynamic>?;
          if (tickerSentiment != null) {
            for (final sentiment in tickerSentiment) {
              final ticker = sentiment['ticker'];
              if (ticker != null) symbols.add(ticker);
            }
          }
          
          // Calculate overall sentiment score
          double? sentimentScore;
          if (tickerSentiment != null && tickerSentiment.isNotEmpty) {
            final scores = tickerSentiment
                .map((s) => double.tryParse(s['relevance_score']?.toString() ?? '0') ?? 0)
                .where((score) => score > 0)
                .toList();
            
            if (scores.isNotEmpty) {
              sentimentScore = scores.reduce((a, b) => a + b) / scores.length;
              // Normalize to -1 to 1 range (assuming relevance score is 0-1)
              sentimentScore = (sentimentScore - 0.5) * 2;
            }
          }
          
          newsItems.add(NewsItem(
            id: newsData['url'] ?? '',
            title: newsData['title'] ?? '',
            summary: newsData['summary'] ?? '',
            content: null,
            source: newsData['source'] ?? '',
            publishedAt: DateTime.tryParse(newsData['time_published'] ?? '') ?? DateTime.now(),
            symbols: symbols,
            sentimentScore: sentimentScore,
            category: newsData['category_within_source'],
          ));
        }
      }
      
      _logger.i('Retrieved ${newsItems.length} news items for $symbol');
      return newsItems;
      
    } catch (e) {
      _logger.w('Failed to fetch news sentiment for $symbol: $e');
      return [];
    }
  }
  
  /// Get company overview
  Future<Map<String, dynamic>?> getCompanyOverview(String symbol) async {
    _logger.i('Fetching company overview for $symbol');
    
    try {
      final data = await _makeRequest({
        'function': 'OVERVIEW',
        'symbol': symbol,
      });
      
      if (data.isEmpty || data.containsKey('Error Message')) {
        return null;
      }
      
      return data;
      
    } catch (e) {
      _logger.w('Failed to fetch company overview for $symbol: $e');
      return null;
    }
  }
  
  /// Get earnings data
  Future<Map<String, dynamic>?> getEarnings(String symbol) async {
    _logger.i('Fetching earnings data for $symbol');
    
    try {
      final data = await _makeRequest({
        'function': 'EARNINGS',
        'symbol': symbol,
      });
      
      if (data.isEmpty || data.containsKey('Error Message')) {
        return null;
      }
      
      return data;
      
    } catch (e) {
      _logger.w('Failed to fetch earnings for $symbol: $e');
      return null;
    }
  }
  
  /// Get economic indicators (VIX, etc.)
  Future<List<Bar>> getEconomicIndicator(String indicator) async {
    _logger.i('Fetching economic indicator: $indicator');
    
    try {
      final data = await _makeRequest({
        'function': 'TIME_SERIES_DAILY',
        'symbol': indicator,
      });
      
      final timeSeries = data['Time Series (Daily)'] as Map<String, dynamic>?;
      
      if (timeSeries == null) {
        return [];
      }
      
      final bars = <Bar>[];
      
      for (final entry in timeSeries.entries) {
        final timestamp = DateTime.parse(entry.key);
        final values = entry.value as Map<String, dynamic>;
        
        final close = double.tryParse(values['4. close'] ?? '0') ?? 0;
        
        bars.add(Bar(
          symbol: indicator,
          open: close,
          high: close,
          low: close,
          close: close,
          volume: 0,
          timestamp: timestamp,
          timeframe: '1d',
        ));
      }
      
      bars.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return bars;
      
    } catch (e) {
      _logger.w('Failed to fetch economic indicator $indicator: $e');
      return [];
    }
  }
  
  TransactionType _parseTransactionType(String? transaction) {
    if (transaction == null) return TransactionType.buy;
    
    final lower = transaction.toLowerCase();
    if (lower.contains('sell') || lower.contains('sale')) {
      return TransactionType.sell;
    } else if (lower.contains('exercise')) {
      return TransactionType.optionExercise;
    } else {
      return TransactionType.buy;
    }
  }
}

class AlphaVantageException implements Exception {
  final String message;
  
  const AlphaVantageException(this.message);
  
  @override
  String toString() => 'AlphaVantageException: $message';
}

// Singleton instance
final alphaVantageClient = AlphaVantageClient();
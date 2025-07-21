import 'package:grpc/grpc.dart';
import 'package:logger/logger.dart';

// Generated protobuf imports (these would be generated from the .proto files)
// For now, we'll create simplified versions of the required classes

/// gRPC client for Technical Analysis Service
class TechnicalAnalysisService {
  final ClientChannel _channel;
  final Logger _logger = Logger();
  
  TechnicalAnalysisService(this._channel);
  
  /// Get all technical indicators for a symbol
  Future<AllIndicatorsResponse> getAllIndicators(AllIndicatorsRequest request) async {
    try {
      _logger.d('Getting indicators for ${request.symbol}');
      
      // In a real implementation, this would make a gRPC call
      // For now, we'll create a mock response
      return _createMockResponse(request);
      
    } catch (e) {
      _logger.e('Error getting indicators: $e');
      rethrow;
    }
  }
  
  /// Shutdown the service
  Future<void> shutdown() async {
    await _channel.shutdown();
  }
  
  /// Create a mock response for testing
  AllIndicatorsResponse _createMockResponse(AllIndicatorsRequest request) {
    final prices = request.prices.close;
    if (prices.isEmpty) {
      return AllIndicatorsResponse(
        rsi: RSIResponse(currentRsi: 0),
        macd: MACDResponse(
          currentMacd: 0,
          currentSignal: 0,
          currentHistogram: 0,
          bullishCrossover: false,
          bearishCrossover: false,
        ),
        bollinger: BollingerBandsResponse(
          currentUpper: 0,
          currentMiddle: 0,
          currentLower: 0,
          bandwidth: 0,
        ),
        atr: ATRResponse(currentAtr: 0),
        movingAverages: MovingAveragesResponse(results: {}),
      );
    }
    
    // Simple mock calculations
    final currentPrice = prices.last;
    final avgPrice = prices.reduce((a, b) => a + b) / prices.length;
    
    // Mock RSI (simplified)
    final rsi = _calculateMockRsi(prices);
    
    // Mock MACD
    final macd = _calculateMockMacd(prices);
    
    // Mock Bollinger Bands
    final bollinger = _calculateMockBollinger(prices);
    
    // Mock ATR
    final atr = currentPrice * 0.02; // 2% of price
    
    // Mock moving averages
    final ma20 = prices.length >= 20 
        ? prices.skip(prices.length - 20).reduce((a, b) => a + b) / 20
        : avgPrice;
    final ma50 = prices.length >= 50
        ? prices.skip(prices.length - 50).reduce((a, b) => a + b) / 50
        : avgPrice;
    
    return AllIndicatorsResponse(
      rsi: RSIResponse(currentRsi: rsi),
      macd: macd,
      bollinger: bollinger,
      atr: ATRResponse(currentAtr: atr),
      movingAverages: MovingAveragesResponse(results: {
        20: MovingAverageResult(currentValue: ma20),
        50: MovingAverageResult(currentValue: ma50),
      }),
    );
  }
  
  double _calculateMockRsi(List<double> prices) {
    if (prices.length < 14) return 50.0;
    
    final recent = prices.skip(prices.length - 14).toList();
    double gains = 0;
    double losses = 0;
    
    for (int i = 1; i < recent.length; i++) {
      final change = recent[i] - recent[i - 1];
      if (change > 0) {
        gains += change;
      } else {
        losses += change.abs();
      }
    }
    
    if (losses == 0) return 100.0;
    if (gains == 0) return 0.0;
    
    final avgGain = gains / 13;
    final avgLoss = losses / 13;
    final rs = avgGain / avgLoss;
    
    return 100 - (100 / (1 + rs));
  }
  
  MACDResponse _calculateMockMacd(List<double> prices) {
    if (prices.length < 26) {
      return MACDResponse(
        currentMacd: 0,
        currentSignal: 0,
        currentHistogram: 0,
        bullishCrossover: false,
        bearishCrossover: false,
      );
    }
    
    // Simple EMA calculation
    final ema12 = _calculateEma(prices, 12);
    final ema26 = _calculateEma(prices, 26);
    final macdLine = ema12 - ema26;
    
    // Mock signal line (would be EMA of MACD)
    final signalLine = macdLine * 0.9; // Simplified
    final histogram = macdLine - signalLine;
    
    return MACDResponse(
      currentMacd: macdLine,
      currentSignal: signalLine,
      currentHistogram: histogram,
      bullishCrossover: histogram > 0 && macdLine > signalLine,
      bearishCrossover: histogram < 0 && macdLine < signalLine,
    );
  }
  
  BollingerBandsResponse _calculateMockBollinger(List<double> prices) {
    if (prices.length < 20) {
      final price = prices.isNotEmpty ? prices.last : 100.0;
      return BollingerBandsResponse(
        currentUpper: price * 1.02,
        currentMiddle: price,
        currentLower: price * 0.98,
        bandwidth: 4.0,
      );
    }
    
    final recent = prices.skip(prices.length - 20).toList();
    final sma = recent.reduce((a, b) => a + b) / 20;
    
    // Calculate standard deviation
    final variance = recent.map((p) => (p - sma) * (p - sma)).reduce((a, b) => a + b) / 20;
    final stdDev = variance < 0 ? 0 : variance; // Simplified sqrt
    
    return BollingerBandsResponse(
      currentUpper: sma + (2 * stdDev),
      currentMiddle: sma,
      currentLower: sma - (2 * stdDev),
      bandwidth: (4 * stdDev / sma) * 100,
    );
  }
  
  double _calculateEma(List<double> prices, int period) {
    if (prices.isEmpty) return 0.0;
    
    final multiplier = 2.0 / (period + 1);
    double ema = prices.first;
    
    for (int i = 1; i < prices.length; i++) {
      ema = (prices[i] * multiplier) + (ema * (1 - multiplier));
    }
    
    return ema;
  }
}

// Simplified protobuf-like classes (in real implementation these would be generated)

class PriceData {
  final List<double> open;
  final List<double> high;
  final List<double> low;
  final List<double> close;
  final List<int> volume;
  final List<int> timestamp;
  
  PriceData({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.timestamp,
  });
}

class AllIndicatorsRequest {
  final String symbol;
  final PriceData prices;
  
  AllIndicatorsRequest({
    required this.symbol,
    required this.prices,
  });
}

class AllIndicatorsResponse {
  final RSIResponse rsi;
  final MACDResponse macd;
  final BollingerBandsResponse bollinger;
  final ATRResponse atr;
  final MovingAveragesResponse movingAverages;
  
  AllIndicatorsResponse({
    required this.rsi,
    required this.macd,
    required this.bollinger,
    required this.atr,
    required this.movingAverages,
  });
}

class RSIResponse {
  final double currentRsi;
  
  RSIResponse({required this.currentRsi});
}

class MACDResponse {
  final double currentMacd;
  final double currentSignal;
  final double currentHistogram;
  final bool bullishCrossover;
  final bool bearishCrossover;
  
  MACDResponse({
    required this.currentMacd,
    required this.currentSignal,
    required this.currentHistogram,
    required this.bullishCrossover,
    required this.bearishCrossover,
  });
}

class BollingerBandsResponse {
  final double currentUpper;
  final double currentMiddle;
  final double currentLower;
  final double bandwidth;
  
  BollingerBandsResponse({
    required this.currentUpper,
    required this.currentMiddle,
    required this.currentLower,
    required this.bandwidth,
  });
}

class ATRResponse {
  final double currentAtr;
  
  ATRResponse({required this.currentAtr});
}

class MovingAveragesResponse {
  final Map<int, MovingAverageResult> results;
  
  MovingAveragesResponse({required this.results});
}

class MovingAverageResult {
  final double currentValue;
  
  MovingAverageResult({required this.currentValue});
}
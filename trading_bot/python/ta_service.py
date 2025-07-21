#!/usr/bin/env python3
"""
Technical Analysis gRPC Service

Provides technical indicators using TA-Lib library.
"""

import sys
import time
import logging
import traceback
from concurrent import futures
from typing import List, Tuple, Dict, Any

import grpc
import numpy as np
import talib
from grpc_reflection.v1alpha import reflection

# Import generated protobuf classes
sys.path.append('../proto')
import ta_service_pb2
import ta_service_pb2_grpc

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class TechnicalAnalysisService(ta_service_pb2_grpc.TechnicalAnalysisServiceServicer):
    """Technical Analysis gRPC Service Implementation"""
    
    def __init__(self):
        logger.info("Initializing Technical Analysis Service")
        
    def _safe_array_conversion(self, data: List[float]) -> np.ndarray:
        """Safely convert list to numpy array with proper NaN handling"""
        if not data:
            return np.array([])
        
        arr = np.array(data, dtype=np.float64)
        # Replace infinite values with NaN
        arr[np.isinf(arr)] = np.nan
        return arr
    
    def _get_current_value(self, arr: np.ndarray) -> float:
        """Get the most recent non-NaN value from array"""
        if len(arr) == 0:
            return 0.0
        
        # Find last non-NaN value
        valid_indices = ~np.isnan(arr)
        if not np.any(valid_indices):
            return 0.0
        
        return float(arr[valid_indices][-1])
    
    def GetRSI(self, request, context):
        """Calculate RSI (Relative Strength Index)"""
        try:
            logger.debug(f"Calculating RSI with period {request.period}")
            
            close_prices = self._safe_array_conversion(request.prices.close)
            period = request.period if request.period > 0 else 14
            
            if len(close_prices) < period + 1:
                context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
                context.set_details(f"Insufficient data: need at least {period + 1} prices")
                return ta_service_pb2.RSIResponse()
            
            rsi_values = talib.RSI(close_prices, timeperiod=period)
            current_rsi = self._get_current_value(rsi_values)
            
            # Filter out NaN values for response
            clean_rsi = [float(val) if not np.isnan(val) else 0.0 for val in rsi_values]
            
            return ta_service_pb2.RSIResponse(
                rsi=clean_rsi,
                current_rsi=current_rsi
            )
            
        except Exception as e:
            logger.error(f"Error calculating RSI: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"RSI calculation failed: {str(e)}")
            return ta_service_pb2.RSIResponse()
    
    def GetMACD(self, request, context):
        """Calculate MACD (Moving Average Convergence Divergence)"""
        try:
            logger.debug("Calculating MACD")
            
            close_prices = self._safe_array_conversion(request.prices.close)
            fast_period = request.fast_period if request.fast_period > 0 else 12
            slow_period = request.slow_period if request.slow_period > 0 else 26
            signal_period = request.signal_period if request.signal_period > 0 else 9
            
            min_length = slow_period + signal_period
            if len(close_prices) < min_length:
                context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
                context.set_details(f"Insufficient data: need at least {min_length} prices")
                return ta_service_pb2.MACDResponse()
            
            macd_line, signal_line, histogram = talib.MACD(
                close_prices, 
                fastperiod=fast_period,
                slowperiod=slow_period, 
                signalperiod=signal_period
            )
            
            current_macd = self._get_current_value(macd_line)
            current_signal = self._get_current_value(signal_line)
            current_histogram = self._get_current_value(histogram)
            
            # Detect crossovers
            bullish_crossover = False
            bearish_crossover = False
            
            if len(histogram) >= 2:
                prev_hist = histogram[-2] if not np.isnan(histogram[-2]) else 0
                curr_hist = current_histogram
                
                if prev_hist <= 0 and curr_hist > 0:
                    bullish_crossover = True
                elif prev_hist >= 0 and curr_hist < 0:
                    bearish_crossover = True
            
            # Clean arrays for response
            clean_macd = [float(val) if not np.isnan(val) else 0.0 for val in macd_line]
            clean_signal = [float(val) if not np.isnan(val) else 0.0 for val in signal_line]
            clean_histogram = [float(val) if not np.isnan(val) else 0.0 for val in histogram]
            
            return ta_service_pb2.MACDResponse(
                macd=clean_macd,
                signal=clean_signal,
                histogram=clean_histogram,
                current_macd=current_macd,
                current_signal=current_signal,
                current_histogram=current_histogram,
                bullish_crossover=bullish_crossover,
                bearish_crossover=bearish_crossover
            )
            
        except Exception as e:
            logger.error(f"Error calculating MACD: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"MACD calculation failed: {str(e)}")
            return ta_service_pb2.MACDResponse()
    
    def GetBollingerBands(self, request, context):
        """Calculate Bollinger Bands"""
        try:
            logger.debug("Calculating Bollinger Bands")
            
            close_prices = self._safe_array_conversion(request.prices.close)
            period = request.period if request.period > 0 else 20
            std_dev = request.std_dev if request.std_dev > 0 else 2.0
            
            if len(close_prices) < period:
                context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
                context.set_details(f"Insufficient data: need at least {period} prices")
                return ta_service_pb2.BollingerBandsResponse()
            
            upper_band, middle_band, lower_band = talib.BBANDS(
                close_prices, 
                timeperiod=period,
                nbdevup=std_dev,
                nbdevdn=std_dev,
                matype=0  # Simple Moving Average
            )
            
            current_upper = self._get_current_value(upper_band)
            current_middle = self._get_current_value(middle_band)
            current_lower = self._get_current_value(lower_band)
            current_price = close_prices[-1] if len(close_prices) > 0 else 0
            
            # Calculate %B and Bandwidth
            bandwidth = ((current_upper - current_lower) / current_middle) * 100 if current_middle != 0 else 0
            percent_b = ((current_price - current_lower) / (current_upper - current_lower)) if (current_upper - current_lower) != 0 else 0.5
            
            # Clean arrays
            clean_upper = [float(val) if not np.isnan(val) else 0.0 for val in upper_band]
            clean_middle = [float(val) if not np.isnan(val) else 0.0 for val in middle_band]
            clean_lower = [float(val) if not np.isnan(val) else 0.0 for val in lower_band]
            
            return ta_service_pb2.BollingerBandsResponse(
                upper=clean_upper,
                middle=clean_middle,
                lower=clean_lower,
                current_upper=current_upper,
                current_middle=current_middle,
                current_lower=current_lower,
                bandwidth=bandwidth,
                percent_b=percent_b
            )
            
        except Exception as e:
            logger.error(f"Error calculating Bollinger Bands: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Bollinger Bands calculation failed: {str(e)}")
            return ta_service_pb2.BollingerBandsResponse()
    
    def GetATR(self, request, context):
        """Calculate ATR (Average True Range)"""
        try:
            logger.debug("Calculating ATR")
            
            high_prices = self._safe_array_conversion(request.prices.high)
            low_prices = self._safe_array_conversion(request.prices.low)
            close_prices = self._safe_array_conversion(request.prices.close)
            period = request.period if request.period > 0 else 14
            
            if len(high_prices) < period or len(low_prices) < period or len(close_prices) < period:
                context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
                context.set_details(f"Insufficient data: need at least {period} OHLC prices")
                return ta_service_pb2.ATRResponse()
            
            atr_values = talib.ATR(high_prices, low_prices, close_prices, timeperiod=period)
            current_atr = self._get_current_value(atr_values)
            
            clean_atr = [float(val) if not np.isnan(val) else 0.0 for val in atr_values]
            
            return ta_service_pb2.ATRResponse(
                atr=clean_atr,
                current_atr=current_atr
            )
            
        except Exception as e:
            logger.error(f"Error calculating ATR: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"ATR calculation failed: {str(e)}")
            return ta_service_pb2.ATRResponse()
    
    def GetMovingAverages(self, request, context):
        """Calculate various moving averages"""
        try:
            logger.debug("Calculating Moving Averages")
            
            close_prices = self._safe_array_conversion(request.prices.close)
            periods = list(request.periods) if request.periods else [20, 50, 200]
            ma_type = request.ma_type.upper() if request.ma_type else "SMA"
            
            results = {}
            
            for period in periods:
                if len(close_prices) < period:
                    continue
                
                if ma_type == "EMA":
                    ma_values = talib.EMA(close_prices, timeperiod=period)
                elif ma_type == "WMA":
                    ma_values = talib.WMA(close_prices, timeperiod=period)
                else:  # Default to SMA
                    ma_values = talib.SMA(close_prices, timeperiod=period)
                
                current_value = self._get_current_value(ma_values)
                clean_values = [float(val) if not np.isnan(val) else 0.0 for val in ma_values]
                
                results[period] = ta_service_pb2.MovingAverageResult(
                    values=clean_values,
                    current_value=current_value
                )
            
            return ta_service_pb2.MovingAveragesResponse(results=results)
            
        except Exception as e:
            logger.error(f"Error calculating Moving Averages: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Moving Averages calculation failed: {str(e)}")
            return ta_service_pb2.MovingAveragesResponse()
    
    def GetAllIndicators(self, request, context):
        """Calculate all indicators for a symbol"""
        try:
            logger.debug(f"Calculating all indicators for {request.symbol}")
            
            # Calculate individual indicators
            rsi_response = self.GetRSI(
                ta_service_pb2.RSIRequest(prices=request.prices, period=14), 
                context
            )
            
            macd_response = self.GetMACD(
                ta_service_pb2.MACDRequest(
                    prices=request.prices, 
                    fast_period=12, 
                    slow_period=26, 
                    signal_period=9
                ), 
                context
            )
            
            bollinger_response = self.GetBollingerBands(
                ta_service_pb2.BollingerBandsRequest(
                    prices=request.prices, 
                    period=20, 
                    std_dev=2.0
                ), 
                context
            )
            
            atr_response = self.GetATR(
                ta_service_pb2.ATRRequest(prices=request.prices, period=14), 
                context
            )
            
            ma_response = self.GetMovingAverages(
                ta_service_pb2.MovingAveragesRequest(
                    prices=request.prices, 
                    periods=[20, 50, 200], 
                    ma_type="SMA"
                ), 
                context
            )
            
            return ta_service_pb2.AllIndicatorsResponse(
                rsi=rsi_response,
                macd=macd_response,
                bollinger=bollinger_response,
                atr=atr_response,
                moving_averages=ma_response
            )
            
        except Exception as e:
            logger.error(f"Error calculating all indicators: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"All indicators calculation failed: {str(e)}")
            return ta_service_pb2.AllIndicatorsResponse()
    
    def GetSignals(self, request, context):
        """Generate trading signals based on technical indicators"""
        try:
            logger.debug(f"Generating signals for {request.symbol}")
            
            signals = []
            current_price = request.current_price
            volume = request.volume
            volume_avg = request.volume_avg
            
            # Get all indicators first
            all_indicators = self.GetAllIndicators(
                ta_service_pb2.AllIndicatorsRequest(
                    symbol=request.symbol,
                    prices=request.prices
                ),
                context
            )
            
            # RSI signals
            if all_indicators.rsi.current_rsi > 0:
                if all_indicators.rsi.current_rsi < 30:
                    signals.append(ta_service_pb2.TradingSignal(
                        indicator="RSI",
                        direction="BUY",
                        strength=min((30 - all_indicators.rsi.current_rsi) / 30, 1.0),
                        reason=f"RSI oversold at {all_indicators.rsi.current_rsi:.2f}",
                        metadata={"rsi": all_indicators.rsi.current_rsi}
                    ))
                elif all_indicators.rsi.current_rsi > 70:
                    signals.append(ta_service_pb2.TradingSignal(
                        indicator="RSI",
                        direction="SELL",
                        strength=min((all_indicators.rsi.current_rsi - 70) / 30, 1.0),
                        reason=f"RSI overbought at {all_indicators.rsi.current_rsi:.2f}",
                        metadata={"rsi": all_indicators.rsi.current_rsi}
                    ))
            
            # MACD signals
            if all_indicators.macd.bullish_crossover:
                signals.append(ta_service_pb2.TradingSignal(
                    indicator="MACD",
                    direction="BUY",
                    strength=0.7,
                    reason="MACD bullish crossover",
                    metadata={"macd": all_indicators.macd.current_macd, "signal": all_indicators.macd.current_signal}
                ))
            elif all_indicators.macd.bearish_crossover:
                signals.append(ta_service_pb2.TradingSignal(
                    indicator="MACD",
                    direction="SELL",
                    strength=0.7,
                    reason="MACD bearish crossover",
                    metadata={"macd": all_indicators.macd.current_macd, "signal": all_indicators.macd.current_signal}
                ))
            
            # Bollinger Bands signals
            if (all_indicators.bollinger.current_lower > 0 and 
                current_price < all_indicators.bollinger.current_lower):
                signals.append(ta_service_pb2.TradingSignal(
                    indicator="BOLLINGER",
                    direction="BUY",
                    strength=0.6,
                    reason="Price below lower Bollinger Band",
                    metadata={"price": current_price, "lower_band": all_indicators.bollinger.current_lower}
                ))
            elif (all_indicators.bollinger.current_upper > 0 and 
                  current_price > all_indicators.bollinger.current_upper):
                signals.append(ta_service_pb2.TradingSignal(
                    indicator="BOLLINGER",
                    direction="SELL",
                    strength=0.6,
                    reason="Price above upper Bollinger Band",
                    metadata={"price": current_price, "upper_band": all_indicators.bollinger.current_upper}
                ))
            
            # Volume spike signal
            if volume_avg > 0 and volume > volume_avg * 2:
                volume_strength = min(volume / volume_avg / 2, 1.0) * 0.3  # Max 0.3 strength
                signals.append(ta_service_pb2.TradingSignal(
                    indicator="VOLUME",
                    direction="BUY",  # Volume spikes often precede upward moves
                    strength=volume_strength,
                    reason=f"Volume spike: {volume/volume_avg:.2f}x average",
                    metadata={"volume": volume, "volume_avg": volume_avg}
                ))
            
            # Calculate overall signal
            buy_strength = sum(s.strength for s in signals if s.direction == "BUY")
            sell_strength = sum(s.strength for s in signals if s.direction == "SELL")
            
            overall_strength = abs(buy_strength - sell_strength)
            overall_direction = "BUY" if buy_strength > sell_strength else "SELL" if sell_strength > buy_strength else "HOLD"
            
            return ta_service_pb2.SignalsResponse(
                signals=signals,
                overall_strength=min(overall_strength, 1.0),
                overall_direction=overall_direction
            )
            
        except Exception as e:
            logger.error(f"Error generating signals: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Signal generation failed: {str(e)}")
            return ta_service_pb2.SignalsResponse()

def serve():
    """Start the gRPC server"""
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    
    # Add the service
    ta_service_pb2_grpc.add_TechnicalAnalysisServiceServicer_to_server(
        TechnicalAnalysisService(), server
    )
    
    # Enable reflection for debugging
    SERVICE_NAMES = (
        ta_service_pb2.DESCRIPTOR.services_by_name['TechnicalAnalysisService'].full_name,
        reflection.SERVICE_NAME,
    )
    reflection.enable_server_reflection(SERVICE_NAMES, server)
    
    # Start server
    listen_addr = '[::]:50051'
    server.add_insecure_port(listen_addr)
    server.start()
    
    logger.info(f"Technical Analysis Service started on {listen_addr}")
    
    try:
        while True:
            time.sleep(86400)  # Sleep for a day
    except KeyboardInterrupt:
        logger.info("Shutting down Technical Analysis Service")
        server.stop(0)

if __name__ == '__main__':
    serve()
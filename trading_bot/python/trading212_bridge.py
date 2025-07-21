#!/usr/bin/env python3
"""
Trading212 Bridge gRPC Service

Wraps pytrading212 Selenium library to provide trading functionality via gRPC.
"""

import sys
import os
import time
import logging
import traceback
import uuid
from concurrent import futures
from typing import Dict, List, Optional
from datetime import datetime, timezone

import grpc
from grpc_reflection.v1alpha import reflection
from pytrading212 import Trading212, Mode
from selenium.common.exceptions import WebDriverException, TimeoutException

# Import generated protobuf classes
sys.path.append('../proto')
import trading212_service_pb2
import trading212_service_pb2_grpc

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class Trading212BridgeService(trading212_service_pb2_grpc.Trading212ServiceServicer):
    """Trading212 Bridge gRPC Service Implementation"""
    
    def __init__(self):
        logger.info("Initializing Trading212 Bridge Service")
        self.trading212 = None
        self.is_connected = False
        self.last_connection_attempt = 0
        self.connection_retry_delay = 60  # seconds
        
        # Load credentials from environment
        self.email = os.getenv('T212_EMAIL')
        self.password = os.getenv('T212_PASSWORD')
        self.mode = Mode.DEMO if os.getenv('T212_MODE', 'demo').lower() == 'demo' else Mode.LIVE
        
        if not self.email or not self.password:
            logger.error("Trading212 credentials not found in environment variables")
            raise ValueError("Missing T212_EMAIL or T212_PASSWORD environment variables")
        
        # Initialize connection
        self._connect()
    
    def _connect(self):
        """Connect to Trading212"""
        current_time = time.time()
        
        # Avoid too frequent connection attempts
        if current_time - self.last_connection_attempt < self.connection_retry_delay:
            return
        
        self.last_connection_attempt = current_time
        
        try:
            logger.info(f"Connecting to Trading212 in {self.mode.value} mode...")
            
            # Configure Chrome options for headless operation
            chrome_options = [
                '--headless',
                '--no-sandbox',
                '--disable-dev-shm-usage',
                '--disable-gpu',
                '--window-size=1920,1080',
                '--disable-extensions',
                '--disable-plugins',
                '--disable-images',
                '--disable-javascript-console',
                '--silent'
            ]
            
            self.trading212 = Trading212(
                email=self.email,
                password=self.password,
                mode=self.mode,
                chrome_options=chrome_options,
                timeout=30
            )
            
            # Test connection with account info
            account_info = self.trading212.get_account_info()
            self.is_connected = True
            
            logger.info(f"Successfully connected to Trading212 ({self.mode.value})")
            logger.info(f"Account balance: {account_info.get('total_cash', 'N/A')}")
            
        except Exception as e:
            logger.error(f"Failed to connect to Trading212: {e}")
            self.is_connected = False
            self.trading212 = None
    
    def _ensure_connected(self):
        """Ensure connection to Trading212 is established"""
        if not self.is_connected or self.trading212 is None:
            self._connect()
        
        if not self.is_connected:
            raise Exception("Unable to connect to Trading212")
    
    def _convert_order_side(self, side: int) -> str:
        """Convert gRPC order side to Trading212 format"""
        return "BUY" if side == trading212_service_pb2.BUY else "SELL"
    
    def _convert_order_status(self, status: str) -> int:
        """Convert Trading212 order status to gRPC format"""
        status_map = {
            'pending': trading212_service_pb2.PENDING,
            'filled': trading212_service_pb2.FILLED,
            'partially_filled': trading212_service_pb2.PARTIALLY_FILLED,
            'cancelled': trading212_service_pb2.CANCELLED,
            'rejected': trading212_service_pb2.REJECTED,
        }
        return status_map.get(status.lower(), trading212_service_pb2.PENDING)
    
    def PlaceMarketOrder(self, request, context):
        """Place a market order"""
        try:
            self._ensure_connected()
            
            logger.info(f"Placing market order: {request.symbol} {self._convert_order_side(request.side)} {request.quantity}")
            
            order_result = self.trading212.place_order(
                instrument_code=request.symbol,
                quantity=request.quantity,
                side=self._convert_order_side(request.side),
                order_type="MARKET"
            )
            
            return trading212_service_pb2.OrderResponse(
                success=order_result.get('success', False),
                message=order_result.get('message', ''),
                order_id=order_result.get('order_id', ''),
                client_order_id=request.client_order_id,
                status=self._convert_order_status(order_result.get('status', 'pending')),
                filled_quantity=order_result.get('filled_quantity', 0.0),
                filled_price=order_result.get('filled_price', 0.0),
                timestamp=int(datetime.now(timezone.utc).timestamp() * 1000)
            )
            
        except Exception as e:
            logger.error(f"Error placing market order: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Market order failed: {str(e)}")
            return trading212_service_pb2.OrderResponse(
                success=False,
                message=str(e)
            )
    
    def PlaceLimitOrder(self, request, context):
        """Place a limit order"""
        try:
            self._ensure_connected()
            
            logger.info(f"Placing limit order: {request.symbol} {self._convert_order_side(request.side)} {request.quantity} @ {request.price}")
            
            order_result = self.trading212.place_order(
                instrument_code=request.symbol,
                quantity=request.quantity,
                side=self._convert_order_side(request.side),
                order_type="LIMIT",
                limit_price=request.price
            )
            
            return trading212_service_pb2.OrderResponse(
                success=order_result.get('success', False),
                message=order_result.get('message', ''),
                order_id=order_result.get('order_id', ''),
                client_order_id=request.client_order_id,
                status=self._convert_order_status(order_result.get('status', 'pending')),
                filled_quantity=order_result.get('filled_quantity', 0.0),
                filled_price=order_result.get('filled_price', 0.0),
                timestamp=int(datetime.now(timezone.utc).timestamp() * 1000)
            )
            
        except Exception as e:
            logger.error(f"Error placing limit order: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Limit order failed: {str(e)}")
            return trading212_service_pb2.OrderResponse(
                success=False,
                message=str(e)
            )
    
    def PlaceStopOrder(self, request, context):
        """Place a stop order"""
        try:
            self._ensure_connected()
            
            logger.info(f"Placing stop order: {request.symbol} {self._convert_order_side(request.side)} {request.quantity} @ {request.stop_price}")
            
            order_result = self.trading212.place_order(
                instrument_code=request.symbol,
                quantity=request.quantity,
                side=self._convert_order_side(request.side),
                order_type="STOP",
                stop_price=request.stop_price
            )
            
            return trading212_service_pb2.OrderResponse(
                success=order_result.get('success', False),
                message=order_result.get('message', ''),
                order_id=order_result.get('order_id', ''),
                client_order_id=request.client_order_id,
                status=self._convert_order_status(order_result.get('status', 'pending')),
                filled_quantity=order_result.get('filled_quantity', 0.0),
                filled_price=order_result.get('filled_price', 0.0),
                timestamp=int(datetime.now(timezone.utc).timestamp() * 1000)
            )
            
        except Exception as e:
            logger.error(f"Error placing stop order: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Stop order failed: {str(e)}")
            return trading212_service_pb2.OrderResponse(
                success=False,
                message=str(e)
            )
    
    def PlaceBracketOrder(self, request, context):
        """Place a bracket order (entry + stop loss + take profit)"""
        try:
            self._ensure_connected()
            
            logger.info(f"Placing bracket order: {request.symbol} {self._convert_order_side(request.side)} {request.quantity}")
            
            # Place entry order
            if request.entry_price > 0:
                # Limit entry order
                entry_result = self.trading212.place_order(
                    instrument_code=request.symbol,
                    quantity=request.quantity,
                    side=self._convert_order_side(request.side),
                    order_type="LIMIT",
                    limit_price=request.entry_price
                )
            else:
                # Market entry order
                entry_result = self.trading212.place_order(
                    instrument_code=request.symbol,
                    quantity=request.quantity,
                    side=self._convert_order_side(request.side),
                    order_type="MARKET"
                )
            
            if not entry_result.get('success', False):
                return trading212_service_pb2.BracketOrderResponse(
                    success=False,
                    message=f"Entry order failed: {entry_result.get('message', '')}",
                    client_order_id=request.client_order_id
                )
            
            entry_order_id = entry_result.get('order_id', '')
            
            # For bracket orders, we would typically need to wait for the entry to fill
            # then place the stop loss and take profit orders
            # This is a simplified implementation
            
            stop_loss_order_id = ""
            take_profit_order_id = ""
            
            try:
                # Place stop loss order (opposite side)
                stop_side = "SELL" if request.side == trading212_service_pb2.BUY else "BUY"
                stop_result = self.trading212.place_order(
                    instrument_code=request.symbol,
                    quantity=request.quantity,
                    side=stop_side,
                    order_type="STOP",
                    stop_price=request.stop_loss_price
                )
                stop_loss_order_id = stop_result.get('order_id', '')
                
                # Place take profit order (opposite side)
                tp_result = self.trading212.place_order(
                    instrument_code=request.symbol,
                    quantity=request.quantity,
                    side=stop_side,
                    order_type="LIMIT",
                    limit_price=request.take_profit_price
                )
                take_profit_order_id = tp_result.get('order_id', '')
                
            except Exception as e:
                logger.warning(f"Failed to place stop/TP orders: {e}")
            
            return trading212_service_pb2.BracketOrderResponse(
                success=True,
                message="Bracket order placed successfully",
                entry_order_id=entry_order_id,
                stop_loss_order_id=stop_loss_order_id,
                take_profit_order_id=take_profit_order_id,
                client_order_id=request.client_order_id
            )
            
        except Exception as e:
            logger.error(f"Error placing bracket order: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Bracket order failed: {str(e)}")
            return trading212_service_pb2.BracketOrderResponse(
                success=False,
                message=str(e),
                client_order_id=request.client_order_id
            )
    
    def CancelOrder(self, request, context):
        """Cancel an order"""
        try:
            self._ensure_connected()
            
            logger.info(f"Cancelling order: {request.order_id}")
            
            result = self.trading212.cancel_order(request.order_id)
            
            return trading212_service_pb2.CancelOrderResponse(
                success=result.get('success', False),
                message=result.get('message', ''),
                order_id=request.order_id
            )
            
        except Exception as e:
            logger.error(f"Error cancelling order: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Cancel order failed: {str(e)}")
            return trading212_service_pb2.CancelOrderResponse(
                success=False,
                message=str(e),
                order_id=request.order_id
            )
    
    def GetOrderStatus(self, request, context):
        """Get order status"""
        try:
            self._ensure_connected()
            
            order_info = self.trading212.get_order_status(request.order_id)
            
            return trading212_service_pb2.OrderStatusResponse(
                success=True,
                order_id=request.order_id,
                status=self._convert_order_status(order_info.get('status', 'pending')),
                filled_quantity=order_info.get('filled_quantity', 0.0),
                filled_price=order_info.get('filled_price', 0.0),
                remaining_quantity=order_info.get('remaining_quantity', 0.0),
                created_at=order_info.get('created_at', 0),
                updated_at=order_info.get('updated_at', 0)
            )
            
        except Exception as e:
            logger.error(f"Error getting order status: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Get order status failed: {str(e)}")
            return trading212_service_pb2.OrderStatusResponse(
                success=False
            )
    
    def GetAccountInfo(self, request, context):
        """Get account information"""
        try:
            self._ensure_connected()
            
            account_info = self.trading212.get_account_info()
            
            return trading212_service_pb2.AccountInfoResponse(
                success=True,
                message="Account info retrieved successfully",
                total_equity=account_info.get('total_cash', 0.0),
                available_cash=account_info.get('available_cash', 0.0),
                used_margin=account_info.get('used_margin', 0.0),
                free_margin=account_info.get('free_margin', 0.0),
                unrealized_pnl=account_info.get('unrealized_pnl', 0.0),
                realized_pnl=account_info.get('realized_pnl', 0.0),
                currency=account_info.get('currency', 'USD'),
                is_demo=(self.mode == Mode.DEMO)
            )
            
        except Exception as e:
            logger.error(f"Error getting account info: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Get account info failed: {str(e)}")
            return trading212_service_pb2.AccountInfoResponse(
                success=False,
                message=str(e)
            )
    
    def GetPositions(self, request, context):
        """Get current positions"""
        try:
            self._ensure_connected()
            
            positions_data = self.trading212.get_open_positions()
            positions = []
            
            for pos in positions_data:
                position = trading212_service_pb2.Position(
                    symbol=pos.get('instrument_code', ''),
                    side=trading212_service_pb2.BUY if pos.get('side', '').upper() == 'BUY' else trading212_service_pb2.SELL,
                    quantity=pos.get('quantity', 0.0),
                    average_price=pos.get('average_price', 0.0),
                    current_price=pos.get('current_price', 0.0),
                    unrealized_pnl=pos.get('unrealized_pnl', 0.0),
                    unrealized_pnl_percent=pos.get('unrealized_pnl_percent', 0.0),
                    opened_at=pos.get('opened_at', 0),
                    position_id=pos.get('position_id', ''),
                    stop_loss=pos.get('stop_loss', 0.0),
                    take_profit=pos.get('take_profit', 0.0)
                )
                positions.append(position)
            
            return trading212_service_pb2.PositionsResponse(
                success=True,
                message="Positions retrieved successfully",
                positions=positions
            )
            
        except Exception as e:
            logger.error(f"Error getting positions: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Get positions failed: {str(e)}")
            return trading212_service_pb2.PositionsResponse(
                success=False,
                message=str(e)
            )
    
    def GetPortfolio(self, request, context):
        """Get portfolio summary"""
        try:
            self._ensure_connected()
            
            account_info = self.trading212.get_account_info()
            positions_data = self.trading212.get_open_positions()
            
            positions = []
            for pos in positions_data:
                position = trading212_service_pb2.Position(
                    symbol=pos.get('instrument_code', ''),
                    side=trading212_service_pb2.BUY if pos.get('side', '').upper() == 'BUY' else trading212_service_pb2.SELL,
                    quantity=pos.get('quantity', 0.0),
                    average_price=pos.get('average_price', 0.0),
                    current_price=pos.get('current_price', 0.0),
                    unrealized_pnl=pos.get('unrealized_pnl', 0.0),
                    unrealized_pnl_percent=pos.get('unrealized_pnl_percent', 0.0),
                    opened_at=pos.get('opened_at', 0),
                    position_id=pos.get('position_id', ''),
                    stop_loss=pos.get('stop_loss', 0.0),
                    take_profit=pos.get('take_profit', 0.0)
                )
                positions.append(position)
            
            total_equity = account_info.get('total_cash', 0.0)
            total_pnl = account_info.get('total_pnl', 0.0)
            daily_pnl = account_info.get('daily_pnl', 0.0)
            
            return trading212_service_pb2.PortfolioResponse(
                success=True,
                message="Portfolio retrieved successfully",
                total_equity=total_equity,
                total_pnl=total_pnl,
                daily_pnl=daily_pnl,
                total_pnl_percent=(total_pnl / total_equity * 100) if total_equity > 0 else 0.0,
                daily_pnl_percent=(daily_pnl / total_equity * 100) if total_equity > 0 else 0.0,
                open_positions=len(positions),
                positions=positions
            )
            
        except Exception as e:
            logger.error(f"Error getting portfolio: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Get portfolio failed: {str(e)}")
            return trading212_service_pb2.PortfolioResponse(
                success=False,
                message=str(e)
            )
    
    def UpdateStopLoss(self, request, context):
        """Update stop loss for a position"""
        try:
            self._ensure_connected()
            
            result = self.trading212.update_stop_loss(
                position_id=request.position_id,
                stop_loss_price=request.stop_loss_price
            )
            
            return trading212_service_pb2.UpdateStopLossResponse(
                success=result.get('success', False),
                message=result.get('message', ''),
                position_id=request.position_id,
                new_stop_loss=request.stop_loss_price
            )
            
        except Exception as e:
            logger.error(f"Error updating stop loss: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Update stop loss failed: {str(e)}")
            return trading212_service_pb2.UpdateStopLossResponse(
                success=False,
                message=str(e),
                position_id=request.position_id
            )
    
    def UpdateTakeProfit(self, request, context):
        """Update take profit for a position"""
        try:
            self._ensure_connected()
            
            result = self.trading212.update_take_profit(
                position_id=request.position_id,
                take_profit_price=request.take_profit_price
            )
            
            return trading212_service_pb2.UpdateTakeProfitResponse(
                success=result.get('success', False),
                message=result.get('message', ''),
                position_id=request.position_id,
                new_take_profit=request.take_profit_price
            )
            
        except Exception as e:
            logger.error(f"Error updating take profit: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Update take profit failed: {str(e)}")
            return trading212_service_pb2.UpdateTakeProfitResponse(
                success=False,
                message=str(e),
                position_id=request.position_id
            )
    
    def GetMarketData(self, request, context):
        """Get market data for a symbol"""
        try:
            self._ensure_connected()
            
            market_data = self.trading212.get_market_data(request.symbol)
            
            return trading212_service_pb2.MarketDataResponse(
                success=True,
                message="Market data retrieved successfully",
                symbol=request.symbol,
                current_price=market_data.get('current_price', 0.0),
                bid=market_data.get('bid', 0.0),
                ask=market_data.get('ask', 0.0),
                daily_change=market_data.get('daily_change', 0.0),
                daily_change_percent=market_data.get('daily_change_percent', 0.0),
                volume=market_data.get('volume', 0),
                timestamp=int(datetime.now(timezone.utc).timestamp() * 1000)
            )
            
        except Exception as e:
            logger.error(f"Error getting market data: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Get market data failed: {str(e)}")
            return trading212_service_pb2.MarketDataResponse(
                success=False,
                message=str(e),
                symbol=request.symbol
            )
    
    def __del__(self):
        """Cleanup on destruction"""
        if hasattr(self, 'trading212') and self.trading212:
            try:
                self.trading212.close()
            except:
                pass

def serve():
    """Start the gRPC server"""
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    
    # Add the service
    trading212_service_pb2_grpc.add_Trading212ServiceServicer_to_server(
        Trading212BridgeService(), server
    )
    
    # Enable reflection for debugging
    SERVICE_NAMES = (
        trading212_service_pb2.DESCRIPTOR.services_by_name['Trading212Service'].full_name,
        reflection.SERVICE_NAME,
    )
    reflection.enable_server_reflection(SERVICE_NAMES, server)
    
    # Start server
    listen_addr = '[::]:50053'
    server.add_insecure_port(listen_addr)
    server.start()
    
    logger.info(f"Trading212 Bridge Service started on {listen_addr}")
    
    try:
        while True:
            time.sleep(86400)  # Sleep for a day
    except KeyboardInterrupt:
        logger.info("Shutting down Trading212 Bridge Service")
        server.stop(0)

if __name__ == '__main__':
    serve()
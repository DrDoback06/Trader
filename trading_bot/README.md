# Multi-Agent Day Trading Platform

A fully-automated, multi-agent day-trading platform that scans hundreds of equities in real time, decides when and how much to buy, and submits bracket orders to Trading212 while enforcing portfolio-level risk rules.

## Architecture

- **Core**: Dart 3 with Flutter for dashboard
- **Data**: Polygon.io WebSocket + Alpha Vantage REST
- **Analysis**: Python microservices (TA-Lib, sklearn, PyTorch) via gRPC
- **Execution**: pytrading212 Selenium wrapper in Docker
- **Storage**: PostgreSQL + Redis
- **Deployment**: Docker Compose with CI/CD

## Quick Start

1. **Environment Setup**
   ```bash
   cp .env.example .env
   # Fill in your API keys and credentials
   ```

2. **Dependencies**
   ```bash
   # Install Dart SDK
   brew install dart protobuf grpcurl
   
   # Install Python deps
   pip install ta-lib grpcio grpcio-tools pytrading212
   ```

3. **Run Services**
   ```bash
   docker-compose up -d
   ```

4. **Launch Dashboard**
   ```bash
   cd dart
   flutter run -d web
   ```

## Key Features

- **Real-time market scanning** across hundreds of tickers
- **Multi-agent consensus** (technical, sentiment, insider signals)
- **Automated risk management** with trailing stops
- **Bracket order execution** (entry + stop + take-profit)
- **Live P&L dashboard** with interactive charts

## Risk Controls

- Hard stop-loss on every trade
- Trailing stop activation at 2:1 reward/risk
- Max 5 concurrent positions, 20% total leverage
- Multi-timeframe confirmation (price > daily 50-MA)
- Circuit-breaker at 3% daily drawdown

## Development Flow

1. Real-time data ingest (Polygon WebSocket)
2. Technical analysis microservice (gRPC)
3. Multi-agent signal generation
4. Risk management and position sizing
5. Order execution via Trading212
6. Live dashboard and monitoring

## License

MIT License - See LICENSE file for details
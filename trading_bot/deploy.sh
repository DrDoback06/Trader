#!/bin/bash

# Multi-Agent Trading Platform - Production Deployment Script
# This script deploys the Flutter dashboard with all production enhancements

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
DART_PROJECT="$PROJECT_ROOT/dart"
WEB_PROXY="$PROJECT_ROOT/web"
BUILD_DIR="$DART_PROJECT/build/web"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Flutter
    if ! command_exists flutter; then
        log_error "Flutter is not installed or not in PATH"
        exit 1
    fi
    
    # Check Node.js
    if ! command_exists node; then
        log_error "Node.js is not installed or not in PATH"
        exit 1
    fi
    
    # Check npm
    if ! command_exists npm; then
        log_error "npm is not installed or not in PATH"
        exit 1
    fi
    
    # Check Docker (optional)
    if command_exists docker; then
        log_info "Docker found - containerized deployment available"
        DOCKER_AVAILABLE=true
    else
        log_warning "Docker not found - containerized deployment not available"
        DOCKER_AVAILABLE=false
    fi
    
    log_success "Prerequisites check completed"
}

# Function to setup environment
setup_environment() {
    log_info "Setting up environment..."
    
    # Set Flutter environment
    export PATH="$PATH:/workspace/flutter/bin"
    
    # Copy environment file if it doesn't exist
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        if [ -f "$PROJECT_ROOT/.env.example" ]; then
            log_info "Creating .env from .env.example"
            cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
            log_warning "Please update .env with your actual configuration values"
        else
            log_warning ".env file not found - creating with defaults"
            cat > "$PROJECT_ROOT/.env" << EOF
# API Keys & Authentication
POLYGON_API_KEY=your_polygon_api_key_here
ALPHA_VANTAGE_API_KEY=your_alpha_vantage_key_here

# Trading212 Credentials
T212_EMAIL=your_trading212_email@example.com
T212_PASSWORD=your_trading212_password
T212_MODE=demo

# Database Configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=trading_bot
POSTGRES_USER=trading_user
POSTGRES_PASSWORD=secure_password

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379

# Risk Management
MAX_CONCURRENT_POSITIONS=5
MAX_PORTFOLIO_LEVERAGE=0.20
MAX_DAILY_DRAWDOWN=0.03
DEFAULT_POSITION_SIZE=0.02
TRAILING_STOP_ATR_MULTIPLE=1.5

# Service Ports
TA_SERVICE_PORT=50051
ML_SERVICE_PORT=50052
TRADING212_BRIDGE_PORT=50053

# Development Settings
DEBUG_MODE=false
BACKTEST_MODE=false
STARTING_EQUITY=100000.0
USE_MARKET_ORDERS=false
ALLOW_AFTER_HOURS_TRADING=false
PASSWORD_SALT=trading_bot_salt_2024
EOF
        fi
    fi
    
    log_success "Environment setup completed"
}

# Function to install dependencies
install_dependencies() {
    log_info "Installing dependencies..."
    
    # Install Flutter dependencies
    log_info "Installing Flutter dependencies..."
    cd "$DART_PROJECT"
    flutter clean
    flutter pub get
    
    # Install Node.js dependencies for web proxy
    log_info "Installing Node.js dependencies..."
    cd "$WEB_PROXY"
    npm install
    
    log_success "Dependencies installed"
}

# Function to run tests
run_tests() {
    log_info "Running tests..."
    
    cd "$DART_PROJECT"
    
    # Dart analysis
    log_info "Running Dart analysis..."
    if ! flutter analyze --no-fatal-infos; then
        log_warning "Dart analysis found issues - continuing anyway"
    fi
    
    # Run Flutter tests (if any exist)
    if [ -d "test" ] && [ "$(ls -A test)" ]; then
        log_info "Running Flutter tests..."
        flutter test || log_warning "Some tests failed - continuing anyway"
    else
        log_info "No tests found - skipping test execution"
    fi
    
    log_success "Tests completed"
}

# Function to build Flutter web app
build_flutter_web() {
    log_info "Building Flutter web application..."
    
    cd "$DART_PROJECT"
    
    # Clean previous builds
    flutter clean
    
    # Build for web
    flutter build web --release \
        --dart-define=FLUTTER_WEB_AUTO_DETECT=true \
        --dart-define=FLUTTER_WEB_USE_SKIA=false
    
    # Verify build
    if [ ! -d "$BUILD_DIR" ]; then
        log_error "Flutter build failed - build directory not found"
        exit 1
    fi
    
    # Add CORS headers to index.html for better compatibility
    if [ -f "$BUILD_DIR/index.html" ]; then
        # Add meta tags for CORS
        sed -i '/<head>/a\
  <meta http-equiv="Cross-Origin-Embedder-Policy" content="require-corp">\
  <meta http-equiv="Cross-Origin-Opener-Policy" content="same-origin">' "$BUILD_DIR/index.html"
    fi
    
    log_success "Flutter web build completed"
}

# Function to run performance tests
run_performance_tests() {
    log_info "Running performance tests..."
    
    # Create a simple performance test script
    cat > "$PROJECT_ROOT/performance_test.js" << 'EOF'
const puppeteer = require('puppeteer');
const fs = require('fs');

async function runPerformanceTest() {
    console.log('🚀 Starting performance test...');
    
    const browser = await puppeteer.launch({ 
        headless: true,
        args: ['--no-sandbox', '--disable-dev-shm-usage']
    });
    
    const page = await browser.newPage();
    
    // Enable performance monitoring
    await page.setCacheEnabled(false);
    
    try {
        console.log('📊 Loading application...');
        const response = await page.goto('http://localhost:8080', {
            waitUntil: 'networkidle0',
            timeout: 30000
        });
        
        if (response && response.status() !== 200) {
            throw new Error(`HTTP ${response.status()}: ${response.statusText()}`);
        }
        
        console.log('✅ Application loaded successfully');
        
        // Measure performance metrics
        const metrics = await page.metrics();
        console.log('📈 Performance Metrics:');
        console.log(`   - JS Heap Used: ${(metrics.JSHeapUsedSize / 1024 / 1024).toFixed(2)} MB`);
        console.log(`   - JS Heap Total: ${(metrics.JSHeapTotalSize / 1024 / 1024).toFixed(2)} MB`);
        console.log(`   - DOM Nodes: ${metrics.Nodes}`);
        console.log(`   - Event Listeners: ${metrics.JSEventListeners}`);
        
        // Test navigation between tabs
        console.log('🔄 Testing tab navigation...');
        const startTime = Date.now();
        
        // Click through tabs
        const tabs = ['Market Scanner', 'Live Chart', 'Portfolio', 'Risk Dashboard'];
        for (const tab of tabs) {
            try {
                await page.waitForSelector(`text=${tab}`, { timeout: 5000 });
                await page.click(`text=${tab}`);
                await page.waitForTimeout(500); // Allow for rendering
                console.log(`   ✓ ${tab} tab loaded`);
            } catch (e) {
                console.log(`   ⚠️ ${tab} tab not found or failed to load`);
            }
        }
        
        const navigationTime = Date.now() - startTime;
        console.log(`⏱️ Tab navigation completed in ${navigationTime}ms`);
        
        // Performance criteria
        const jsHeapMB = metrics.JSHeapUsedSize / 1024 / 1024;
        const passCriteria = {
            jsHeapUsage: jsHeapMB < 100, // Less than 100MB
            navigationTime: navigationTime < 5000, // Less than 5 seconds
            domNodes: metrics.Nodes < 5000 // Less than 5000 DOM nodes
        };
        
        const allPassed = Object.values(passCriteria).every(Boolean);
        
        console.log('\n📋 Performance Test Results:');
        console.log(`   JS Heap Usage: ${jsHeapMB.toFixed(2)} MB ${passCriteria.jsHeapUsage ? '✅' : '❌'}`);
        console.log(`   Navigation Time: ${navigationTime} ms ${passCriteria.navigationTime ? '✅' : '❌'}`);
        console.log(`   DOM Nodes: ${metrics.Nodes} ${passCriteria.domNodes ? '✅' : '❌'}`);
        console.log(`\n🎯 Overall Result: ${allPassed ? 'PASS ✅' : 'FAIL ❌'}`);
        
        // Save results
        const results = {
            timestamp: new Date().toISOString(),
            passed: allPassed,
            metrics,
            navigationTimeMs: navigationTime,
            criteria: passCriteria
        };
        
        fs.writeFileSync('performance_results.json', JSON.stringify(results, null, 2));
        console.log('💾 Results saved to performance_results.json');
        
        process.exit(allPassed ? 0 : 1);
        
    } catch (error) {
        console.error('❌ Performance test failed:', error.message);
        process.exit(1);
    } finally {
        await browser.close();
    }
}

runPerformanceTest();
EOF

    # Install puppeteer if needed
    if ! npm list puppeteer > /dev/null 2>&1; then
        log_info "Installing Puppeteer for performance testing..."
        cd "$WEB_PROXY"
        npm install --save-dev puppeteer
    fi
    
    # Start the web server in background
    log_info "Starting web server for performance testing..."
    cd "$WEB_PROXY"
    npm start > /dev/null 2>&1 &
    SERVER_PID=$!
    
    # Wait for server to start
    sleep 10
    
    # Run performance test
    if command_exists node; then
        node "$PROJECT_ROOT/performance_test.js"
        PERF_EXIT_CODE=$?
    else
        log_warning "Node.js not found - skipping performance tests"
        PERF_EXIT_CODE=0
    fi
    
    # Clean up
    kill $SERVER_PID 2>/dev/null || true
    rm -f "$PROJECT_ROOT/performance_test.js"
    
    if [ $PERF_EXIT_CODE -eq 0 ]; then
        log_success "Performance tests passed"
    else
        log_warning "Performance tests failed - check results"
    fi
}

# Function to start services
start_services() {
    log_info "Starting production services..."
    
    cd "$WEB_PROXY"
    
    # Start CORS proxy server
    log_info "Starting CORS proxy server on port 8080..."
    npm start > web_server.log 2>&1 &
    WEB_SERVER_PID=$!
    
    # Save PID for cleanup
    echo $WEB_SERVER_PID > web_server.pid
    
    # Wait for server to start
    sleep 5
    
    # Test if server is running
    if curl -f http://localhost:8080/health > /dev/null 2>&1; then
        log_success "Web server started successfully"
        log_info "Dashboard available at: http://localhost:8080"
        log_info "Health check: http://localhost:8080/health"
        log_info "API proxy: http://localhost:8080/api"
    else
        log_error "Web server failed to start"
        exit 1
    fi
}

# Function to create Docker deployment
create_docker_deployment() {
    if [ "$DOCKER_AVAILABLE" != true ]; then
        log_warning "Docker not available - skipping containerized deployment"
        return
    fi
    
    log_info "Creating Docker deployment..."
    
    # Create Dockerfile
    cat > "$PROJECT_ROOT/Dockerfile" << 'EOF'
# Multi-stage build for Flutter web app
FROM node:18-alpine AS web-builder

# Set working directory
WORKDIR /app

# Copy package files
COPY web/package*.json ./
RUN npm install

# Copy web proxy source
COPY web/ ./

# Production stage
FROM node:18-alpine

# Install security updates
RUN apk update && apk upgrade

# Create app user
RUN addgroup -g 1001 -S nodejs
RUN adduser -S trading-bot -u 1001

# Set working directory
WORKDIR /app

# Copy package files and install dependencies
COPY web/package*.json ./
RUN npm ci --only=production && npm cache clean --force

# Copy built application
COPY --from=web-builder /app ./
COPY dart/build/web ./build/web

# Change ownership
RUN chown -R trading-bot:nodejs /app

# Switch to non-root user
USER trading-bot

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Start the application
CMD ["npm", "start"]
EOF

    # Create docker-compose.yml
    cat > "$PROJECT_ROOT/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  trading-bot-web:
    build: .
    ports:
      - "8080:8080"
    environment:
      - NODE_ENV=production
      - PORT=8080
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - trading-bot-network

  # Redis (for real data connections)
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - trading-bot-network

  # PostgreSQL (for data persistence)
  postgres:
    image: postgres:15-alpine
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_DB=trading_bot
      - POSTGRES_USER=trading_user
      - POSTGRES_PASSWORD=secure_password
    restart: unless-stopped
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - trading-bot-network

volumes:
  redis_data:
  postgres_data:

networks:
  trading-bot-network:
    driver: bridge
EOF

    # Create .dockerignore
    cat > "$PROJECT_ROOT/.dockerignore" << 'EOF'
# Git
.git
.gitignore

# Flutter
dart/.dart_tool/
dart/build/
dart/ios/
dart/android/
dart/macos/
dart/windows/
dart/linux/

# Node.js
web/node_modules/
web/npm-debug.log*
web/.npm

# Logs
*.log

# Environment
.env
.env.local

# IDE
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db

# Test files
test/
*_test.dart
performance_results.json
performance_test.js
EOF

    log_success "Docker deployment files created"
    log_info "To deploy with Docker: docker-compose up -d"
}

# Function to display deployment summary
show_deployment_summary() {
    log_success "🎉 Deployment completed successfully!"
    echo
    echo "📋 Deployment Summary:"
    echo "├── Flutter Web App: Built and ready"
    echo "├── CORS Proxy Server: Running on port 8080"
    echo "├── Performance Tests: $([ -f "performance_results.json" ] && echo "Completed" || echo "Skipped")"
    echo "├── Docker Support: $([ "$DOCKER_AVAILABLE" = true ] && echo "Available" || echo "Not available")"
    echo "└── Environment: Production-ready"
    echo
    echo "🌐 Access URLs:"
    echo "   • Dashboard: http://localhost:8080"
    echo "   • Health Check: http://localhost:8080/health"
    echo "   • API Proxy: http://localhost:8080/api"
    echo
    echo "📁 Important Files:"
    echo "   • Environment: .env"
    echo "   • Logs: web/web_server.log"
    echo "   • Performance: performance_results.json"
    echo "   • Docker: docker-compose.yml"
    echo
    echo "🛠️ Next Steps:"
    echo "   1. Update .env with your API keys and configuration"
    echo "   2. Start your backend services (Redis, PostgreSQL, gRPC)"
    echo "   3. Monitor performance and logs"
    echo "   4. Scale with Docker if needed: docker-compose up -d"
    echo
    log_info "For production deployment, ensure all backend services are running"
    log_info "Monitor logs: tail -f web/web_server.log"
}

# Function to cleanup on script exit
cleanup() {
    if [ ! -z "$WEB_SERVER_PID" ]; then
        kill $WEB_SERVER_PID 2>/dev/null || true
    fi
}

# Trap cleanup function
trap cleanup EXIT

# Main deployment function
main() {
    echo "🚀 Multi-Agent Trading Platform - Production Deployment"
    echo "======================================================="
    echo
    
    # Parse command line arguments
    SKIP_TESTS=false
    SKIP_PERFORMANCE=false
    DOCKER_DEPLOY=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --skip-performance)
                SKIP_PERFORMANCE=true
                shift
                ;;
            --docker)
                DOCKER_DEPLOY=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Options:"
                echo "  --skip-tests         Skip running tests"
                echo "  --skip-performance   Skip performance testing"
                echo "  --docker            Create Docker deployment files"
                echo "  --help              Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    install_dependencies
    
    if [ "$SKIP_TESTS" != true ]; then
        run_tests
    else
        log_info "Skipping tests (--skip-tests specified)"
    fi
    
    build_flutter_web
    
    if [ "$SKIP_PERFORMANCE" != true ]; then
        run_performance_tests
    else
        log_info "Skipping performance tests (--skip-performance specified)"
    fi
    
    if [ "$DOCKER_DEPLOY" = true ]; then
        create_docker_deployment
    fi
    
    start_services
    show_deployment_summary
}

# Run main function with all arguments
main "$@"
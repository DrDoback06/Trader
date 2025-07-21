import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import 'screens/market_scanner_screen.dart';
import 'screens/live_chart_screen.dart';
import 'screens/portfolio_screen.dart';
import 'screens/risk_dashboard_screen.dart';
import '../providers/app_providers.dart';
import '../data/models.dart';

class DashboardApp extends ConsumerStatefulWidget {
  @override
  ConsumerState<DashboardApp> createState() => _DashboardAppState();
}

class _DashboardAppState extends ConsumerState<DashboardApp>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionStatus = ref.watch(connectionStatusProvider);
    final manualPause = ref.watch(manualPauseProvider);
    final manualPositions = ref.watch(portfolioProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.trending_up, color: Colors.green),
            Gap(8),
            Text(
              'Multi-Agent Trading Platform',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          // Connection status
          _buildConnectionStatus(connectionStatus),
          Gap(16),
          // Manual pause switch
          _buildManualPauseSwitch(manualPause),
          Gap(16),
          // Portfolio value
          _buildPortfolioValue(manualPositions),
          Gap(16),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: Icon(Icons.radar),
              text: 'Market Scanner',
            ),
            Tab(
              icon: Icon(Icons.candlestick_chart),
              text: 'Live Charts',
            ),
            Tab(
              icon: Icon(Icons.account_balance_wallet),
              text: 'Portfolio',
            ),
            Tab(
              icon: Icon(Icons.security),
              text: 'Risk Dashboard',
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TabBarView(
          controller: _tabController,
          children: [
            MarketScannerScreen(),
            LiveChartScreen(),
            PortfolioScreen(),
            RiskDashboardScreen(),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus(ConnectionStatus status) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: status.isConnected 
            ? Colors.green.withOpacity(0.2) 
            : Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: status.isConnected ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: status.isConnected ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          Gap(6),
          Text(
            status.isConnected ? 'CONNECTED' : 'DISCONNECTED',
            style: TextStyle(
              color: status.isConnected ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualPauseSwitch(bool isPaused) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isPaused 
            ? Colors.orange.withOpacity(0.2) 
            : Colors.blue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPaused ? Colors.orange : Colors.blue,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPaused ? Icons.pause_circle : Icons.play_circle,
            color: isPaused ? Colors.orange : Colors.blue,
            size: 20,
          ),
          Gap(4),
          Text(
            isPaused ? 'PAUSED' : 'ACTIVE',
            style: TextStyle(
              color: isPaused ? Colors.orange : Colors.blue,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          Gap(4),
          Switch(
            value: !isPaused,
            onChanged: (value) {
              ref.read(manualPauseProvider.notifier).toggle();
            },
            activeColor: Colors.blue,
            inactiveThumbColor: Colors.orange,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioValue(List<ManualPosition> positions) {
    final totalValue = positions.fold<double>(0, (sum, pos) => sum + (pos.currentPrice * pos.quantity));
    final totalPnL = positions.fold<double>(0, (sum, pos) => sum + pos.unrealizedPnl);
    final baseEquity = 100000.0; // Starting equity
    final currentEquity = baseEquity + totalPnL;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.purple,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '\$${currentEquity.toStringAsFixed(2)}',
            style: TextStyle(
              color: Colors.purple,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          if (totalPnL != 0)
            Text(
              '${totalPnL >= 0 ? '+' : ''}\$${totalPnL.toStringAsFixed(2)}',
              style: TextStyle(
                color: totalPnL >= 0 ? Colors.green : Colors.red,
                fontWeight: FontWeight.w500,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }
}
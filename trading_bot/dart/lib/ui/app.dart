import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import 'screens/market_scanner_screen.dart';
import 'screens/live_chart_screen.dart';
import 'screens/portfolio_screen.dart';
import 'screens/risk_dashboard_screen.dart';
import '../providers/app_providers.dart';

class DashboardApp extends ConsumerStatefulWidget {
  @override
  ConsumerState<DashboardApp> createState() => _DashboardAppState();
}

class _DashboardAppState extends ConsumerState<DashboardApp>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentIndex = _tabController.index;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionStatus = ref.watch(connectionStatusProvider);
    final riskMetrics = ref.watch(riskMetricsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.trending_up, color: Colors.green),
            Gap(8),
            Text(
              'Multi-Agent Trading Platform',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Spacer(),
            _buildConnectionStatus(connectionStatus),
            Gap(16),
            _buildManualPauseSwitch(),
            Gap(16),
            _buildEquityDisplay(riskMetrics),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: Icon(Icons.search),
              text: 'Market Scanner',
            ),
            Tab(
              icon: Icon(Icons.show_chart),
              text: 'Live Chart',
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
      body: TabBarView(
        controller: _tabController,
        children: [
          MarketScannerScreen(),
          LiveChartScreen(),
          PortfolioScreen(),
          RiskDashboardScreen(),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus(AsyncValue<ConnectionStatus> connectionStatus) {
    return connectionStatus.when(
      data: (status) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status.isConnected ? Icons.wifi : Icons.wifi_off,
            color: status.isConnected ? Colors.green : Colors.red,
            size: 16,
          ),
          Gap(4),
          Text(
            status.isConnected ? 'Connected' : 'Disconnected',
            style: TextStyle(
              color: status.isConnected ? Colors.green : Colors.red,
              fontSize: 12,
            ),
          ),
        ],
      ),
      loading: () => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          Gap(4),
          Text('Connecting...', style: TextStyle(fontSize: 12)),
        ],
      ),
      error: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error, color: Colors.red, size: 16),
          Gap(4),
          Text('Error', style: TextStyle(color: Colors.red, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildManualPauseSwitch() {
    final isManualPause = ref.watch(manualPauseProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Manual Pause',
          style: TextStyle(fontSize: 12),
        ),
        Gap(4),
        Switch(
          value: isManualPause,
          onChanged: (value) {
            ref.read(manualPauseProvider.notifier).toggle();
          },
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  Widget _buildEquityDisplay(AsyncValue<RiskMetrics> riskMetrics) {
    return riskMetrics.when(
      data: (metrics) => Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Equity',
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
            Text(
              '\$${metrics.equity.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: metrics.drawdown > 0 ? Colors.red : Colors.green,
              ),
            ),
            if (metrics.drawdown > 0)
              Text(
                '-${metrics.drawdown.toStringAsFixed(2)}%',
                style: TextStyle(fontSize: 10, color: Colors.red),
              ),
          ],
        ),
      ),
      loading: () => Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SizedBox(
          width: 80,
          height: 20,
          child: LinearProgressIndicator(),
        ),
      ),
      error: (_, __) => Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          'Error',
          style: TextStyle(color: Colors.red, fontSize: 12),
        ),
      ),
    );
  }
}
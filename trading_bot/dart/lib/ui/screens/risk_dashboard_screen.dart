import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../providers/app_providers.dart';
import '../../data/models.dart';

class RiskDashboardScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riskMetrics = ref.watch(riskMetricsProvider);
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          Gap(16),
          Expanded(
            child: riskMetrics.when(
              data: (metrics) => _buildRiskContent(context, metrics),
              loading: () => Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error, size: 48, color: Colors.red),
                    Gap(16),
                    Text('Error loading risk metrics: $error'),
                    Gap(16),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(riskMetricsProvider),
                      child: Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.security, size: 28),
        Gap(12),
        Text(
          'Risk Dashboard',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Spacer(),
        _buildCircuitBreakerIndicator(),
      ],
    );
  }

  Widget _buildCircuitBreakerIndicator() {
    return Consumer(
      builder: (context, ref, child) {
        final riskMetrics = ref.watch(riskMetricsProvider);
        
        return riskMetrics.when(
          data: (metrics) => Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: metrics.circuitBreakerActive ? Colors.red : Colors.green,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  metrics.circuitBreakerActive ? Icons.warning : Icons.check_circle,
                  color: Colors.white,
                  size: 16,
                ),
                Gap(4),
                Text(
                  metrics.circuitBreakerActive ? 'CIRCUIT BREAKER ACTIVE' : 'SYSTEM OPERATIONAL',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          loading: () => Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, __) => Container(),
        );
      },
    );
  }

  Widget _buildRiskContent(BuildContext context, RiskMetrics metrics) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Top row - circular progress indicators
          Row(
            children: [
              Expanded(
                child: _buildPortfolioHeatGauge(context, metrics),
              ),
              Gap(16),
              Expanded(
                child: _buildDrawdownGauge(context, metrics),
              ),
            ],
          ),
          Gap(24),
          // Middle row - risk metrics cards
          _buildRiskMetricsCards(context, metrics),
          Gap(24),
          // Bottom row - drawdown history chart
          _buildDrawdownHistoryChart(context),
        ],
      ),
    );
  }

  Widget _buildPortfolioHeatGauge(BuildContext context, RiskMetrics metrics) {
    final heatRatio = metrics.portfolioHeat / metrics.maxPortfolioHeat;
    final heatColor = _getHeatColor(heatRatio);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text(
              'Portfolio Heat',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Gap(16),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: heatRatio,
                    strokeWidth: 12,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(heatColor),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${metrics.portfolioHeat.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: heatColor,
                      ),
                    ),
                    Text(
                      'of ${metrics.maxPortfolioHeat.toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            Gap(12),
            Text(
              'Risk exposure across all positions',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawdownGauge(BuildContext context, RiskMetrics metrics) {
    final drawdownRatio = metrics.drawdown / 10.0; // Assume max 10% for visualization
    final drawdownColor = metrics.drawdown > 3.0 ? Colors.red : 
                         metrics.drawdown > 1.5 ? Colors.orange : Colors.green;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text(
              'Current Drawdown',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Gap(16),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: drawdownRatio.clamp(0.0, 1.0),
                    strokeWidth: 12,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(drawdownColor),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${metrics.drawdown.toStringAsFixed(2)}%',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: drawdownColor,
                      ),
                    ),
                    Text(
                      'Max: ${metrics.maxDrawdown.toStringAsFixed(2)}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            Gap(12),
            Text(
              'Peak-to-current equity decline',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskMetricsCards(BuildContext context, RiskMetrics metrics) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            context,
            'Value at Risk (95%)',
            metrics.valueAtRisk95 != null 
                ? '\$${metrics.valueAtRisk95!.toStringAsFixed(0)}'
                : 'N/A',
            Icons.trending_down,
            Colors.purple,
            'Potential 1-day loss at 95% confidence',
          ),
        ),
        Gap(16),
        Expanded(
          child: _buildMetricCard(
            context,
            'Portfolio Beta',
            metrics.portfolioBeta?.toStringAsFixed(2) ?? 'N/A',
            Icons.compare_arrows,
            Colors.blue,
            'Correlation with market movements',
          ),
        ),
        Gap(16),
        Expanded(
          child: _buildMetricCard(
            context,
            'Open Positions',
            '${metrics.openPositions} / ${metrics.maxPositions}',
            Icons.inventory,
            _getPositionColor(metrics.openPositions, metrics.maxPositions),
            'Current vs maximum allowed positions',
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
    String description,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                Gap(8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Gap(12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Gap(8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawdownHistoryChart(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Drawdown History (30 Days)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Gap(16),
            SizedBox(
              height: 200,
              child: SfCartesianChart(
                primaryXAxis: DateTimeAxis(
                  majorGridLines: MajorGridLines(width: 0.5),
                  axisLabelFormatter: (AxisLabelRenderDetails details) {
                    final date = DateTime.fromMillisecondsSinceEpoch(details.value.toInt());
                    return ChartAxisLabel(
                      '${date.day}/${date.month}',
                      TextStyle(fontSize: 10),
                    );
                  },
                ),
                primaryYAxis: NumericAxis(
                  title: AxisTitle(text: 'Drawdown %'),
                  majorGridLines: MajorGridLines(width: 0.5),
                  labelFormat: '{value}%',
                ),
                tooltipBehavior: TooltipBehavior(enable: true),
                series: <CartesianSeries>[
                  AreaSeries<DrawdownPoint, DateTime>(
                    dataSource: _generateMockDrawdownData(),
                    xValueMapper: (DrawdownPoint point, _) => point.date,
                    yValueMapper: (DrawdownPoint point, _) => point.drawdown,
                    name: 'Drawdown',
                    color: Colors.red.withOpacity(0.3),
                    borderColor: Colors.red,
                    borderWidth: 2,
                  ),
                ],
                plotAreaBorderWidth: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getHeatColor(double ratio) {
    if (ratio > 0.8) return Colors.red;
    if (ratio > 0.6) return Colors.orange;
    if (ratio > 0.4) return Colors.yellow[700]!;
    return Colors.green;
  }

  Color _getPositionColor(int current, int max) {
    final ratio = current / max;
    if (ratio > 0.8) return Colors.red;
    if (ratio > 0.6) return Colors.orange;
    return Colors.green;
  }

  List<DrawdownPoint> _generateMockDrawdownData() {
    final now = DateTime.now();
    final data = <DrawdownPoint>[];
    
    for (int i = 30; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final drawdown = (i % 7) * 0.3 + (i % 3) * 0.1; // Mock varying drawdown
      data.add(DrawdownPoint(date, drawdown));
    }
    
    return data;
  }
}

class DrawdownPoint {
  final DateTime date;
  final double drawdown;
  
  DrawdownPoint(this.date, this.drawdown);
}
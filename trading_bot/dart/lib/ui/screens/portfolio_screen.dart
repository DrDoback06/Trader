import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../providers/app_providers.dart';
import '../../data/models.dart';

class PortfolioScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positionsAsync = ref.watch(positionsProvider);
    final riskMetrics = ref.watch(riskMetricsProvider);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          Gap(16),
          _buildSummaryCards(context, riskMetrics),
          Gap(16),
          Expanded(
            child: positionsAsync.when(
              data: (positions) => _buildPositionsList(context, ref, positions),
              loading: () => Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error, size: 48, color: Colors.red),
                    Gap(16),
                    Text('Error loading positions: $error'),
                    Gap(16),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(positionsProvider),
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
        Icon(Icons.account_balance_wallet, size: 28),
        Gap(12),
        Text(
          'Portfolio',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Spacer(),
        _buildRefreshButton(),
      ],
    );
  }

  Widget _buildRefreshButton() {
    return IconButton(
      onPressed: () {
        // Refresh positions data
      },
      icon: Icon(Icons.refresh),
      tooltip: 'Refresh positions',
    );
  }

  Widget _buildSummaryCards(BuildContext context, AsyncValue<RiskMetrics> riskMetrics) {
    return riskMetrics.when(
      data: (metrics) => Row(
        children: [
          Expanded(
            child: _buildSummaryCard(
              context,
              'Total Equity',
              '\$100,000.00',
              Icons.account_balance,
              Colors.blue,
            ),
          ),
          Gap(16),
          Expanded(
            child: _buildSummaryCard(
              context,
              'Open Positions',
              '${metrics.openPositions}',
              Icons.trending_up,
              Colors.green,
            ),
          ),
          Gap(16),
          Expanded(
            child: _buildSummaryCard(
              context,
              'Portfolio Heat',
              '${metrics.portfolioHeat.toStringAsFixed(1)}%',
              Icons.local_fire_department,
              _getHeatColor(metrics.portfolioHeat, 15.0),
            ),
          ),
          Gap(16),
          Expanded(
            child: _buildSummaryCard(
              context,
              'Drawdown',
              '${metrics.currentDrawdown.toStringAsFixed(2)}%',
              Icons.trending_down,
              metrics.currentDrawdown > 0 ? Colors.red : Colors.grey,
            ),
          ),
        ],
      ),
      loading: () => Row(
        children: List.generate(4, (index) => 
          Expanded(
            child: Container(
              margin: EdgeInsets.only(right: index < 3 ? 16 : 0),
              child: Card(
                child: Container(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
          ),
        ),
      ),
      error: (_, __) => Container(),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
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
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            Gap(8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getHeatColor(double current, double max) {
    final ratio = current / max;
    if (ratio > 0.8) return Colors.red;
    if (ratio > 0.6) return Colors.orange;
    if (ratio > 0.4) return Colors.yellow;
    return Colors.green;
  }

  Widget _buildPositionsList(
    BuildContext context,
    WidgetRef ref,
    List<Position> positions,
  ) {
    if (positions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet, size: 48, color: Colors.grey),
            Gap(16),
            Text(
              'No open positions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Gap(8),
            Text(
              'Your portfolio is currently empty. Positions will appear here when trades are executed.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: positions.length,
      itemBuilder: (context, index) {
        final position = positions[index];
        return _buildPositionCard(context, ref, position);
      },
    );
  }

  Widget _buildPositionCard(
    BuildContext context,
    WidgetRef ref,
    Position position,
  ) {
    final unrealizedPnl = position.unrealizedPnl ?? 0.0;
    final unrealizedPnlPercent = (unrealizedPnl / (position.quantity * position.entryPrice)) * 100;
    final isProfit = unrealizedPnl >= 0;

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                // Symbol and side
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            position.symbol,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Gap(8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: position.side == OrderSide.buy 
                                  ? Colors.green.withOpacity(0.2)
                                  : Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              position.side == OrderSide.buy ? 'LONG' : 'SHORT',
                              style: TextStyle(
                                color: position.side == OrderSide.buy ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Gap(4),
                      Text(
                        'Qty: ${position.quantity.toStringAsFixed(6)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // Entry price
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Entry',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        '\$${position.entryPrice.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                // Current price
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        '\$${(position.currentPrice ?? position.entryPrice).toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                // P&L
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'P&L',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        '\$${unrealizedPnl.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isProfit ? Colors.green : Colors.red,
                        ),
                      ),
                      Text(
                        '${isProfit ? '+' : ''}${unrealizedPnlPercent.toStringAsFixed(2)}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isProfit ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (position.stopLoss != null || position.takeProfit != null) ...[
              Gap(12),
              Divider(),
              Gap(8),
              Row(
                children: [
                  if (position.stopLoss != null) ...[
                    Icon(Icons.stop, size: 16, color: Colors.red),
                    Gap(4),
                    Text(
                      'Stop: \$${position.stopLoss!.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  if (position.stopLoss != null && position.takeProfit != null)
                    Gap(16),
                  if (position.takeProfit != null) ...[
                    Icon(Icons.flag, size: 16, color: Colors.green),
                    Gap(4),
                    Text(
                      'Target: \$${position.takeProfit!.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.green, fontSize: 12),
                    ),
                  ],
                  Spacer(),
                  Text(
                    'Opened ${_formatDate(position.openTime)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
            Gap(8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showPositionDetails(context, position),
                    icon: Icon(Icons.info_outline, size: 16),
                    label: Text('Details'),
                  ),
                ),
                Gap(8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showClosePositionDialog(context, ref, position),
                    icon: Icon(Icons.close, size: 16),
                    label: Text('Close'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPositionDetails(BuildContext context, Position position) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Position Details - ${position.symbol}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Symbol', position.symbol),
            _buildDetailRow('Side', position.side == OrderSide.buy ? 'Long' : 'Short'),
            _buildDetailRow('Quantity', position.quantity.toStringAsFixed(6)),
            _buildDetailRow('Entry Price', '\$${position.entryPrice.toStringAsFixed(2)}'),
            if (position.currentPrice != null)
              _buildDetailRow('Current Price', '\$${position.currentPrice!.toStringAsFixed(2)}'),
            if (position.stopLoss != null)
              _buildDetailRow('Stop Loss', '\$${position.stopLoss!.toStringAsFixed(2)}'),
            if (position.takeProfit != null)
              _buildDetailRow('Take Profit', '\$${position.takeProfit!.toStringAsFixed(2)}'),
            if (position.unrealizedPnl != null)
              _buildDetailRow('Unrealized P&L', '\$${position.unrealizedPnl!.toStringAsFixed(2)}'),
            _buildDetailRow('Opened At', _formatDateTime(position.openTime)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  void _showClosePositionDialog(
    BuildContext context, 
    WidgetRef ref, 
    Position position,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Close Position'),
        content: Text(
          'Are you sure you want to close your ${position.side.name.toUpperCase()} position in ${position.symbol}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Implement close position logic
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Position close request sent')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Close Position'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inMinutes}m ago';
    }
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
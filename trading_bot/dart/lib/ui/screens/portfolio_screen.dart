import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../providers/app_providers.dart';
import '../../data/models.dart';

class PortfolioScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manualPositions = ref.watch(portfolioProvider);
    final riskMetrics = ref.watch(riskMetricsProvider);

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(context),
          Gap(16),
          riskMetrics.when(
            data: (metrics) => _buildSummaryCards(context, metrics, manualPositions),
            loading: () => _buildLoadingSummary(),
            error: (_, __) => _buildErrorSummary(),
          ),
          Gap(16),
          Expanded(
            child: _buildPositionsList(context, manualPositions),
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

  Widget _buildSummaryCards(BuildContext context, RiskMetrics metrics, List<ManualPosition> positions) {
    final totalValue = positions.fold<double>(0, (sum, pos) => sum + (pos.currentPrice * pos.quantity));
    final totalPnL = positions.fold<double>(0, (sum, pos) => sum + pos.unrealizedPnl);
    final totalInvested = positions.fold<double>(0, (sum, pos) => sum + (pos.entryPrice * pos.quantity));
    final totalPnLPercentage = totalInvested > 0 ? (totalPnL / totalInvested) * 100 : 0.0;
    
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            context,
            'Total Value',
            '\$${totalValue.toStringAsFixed(2)}',
            Icons.account_balance,
            Colors.blue,
          ),
        ),
        Gap(16),
        Expanded(
          child: _buildSummaryCard(
            context,
            'Total P&L',
            '${totalPnL >= 0 ? '+' : ''}\$${totalPnL.toStringAsFixed(2)}',
            Icons.trending_up,
            totalPnL >= 0 ? Colors.green : Colors.red,
          ),
        ),
        Gap(16),
        Expanded(
          child: _buildSummaryCard(
            context,
            'P&L %',
            '${totalPnLPercentage >= 0 ? '+' : ''}${totalPnLPercentage.toStringAsFixed(2)}%',
            Icons.percent,
            totalPnLPercentage >= 0 ? Colors.green : Colors.red,
          ),
        ),
        Gap(16),
        Expanded(
          child: _buildSummaryCard(
            context,
            'Open Positions',
            '${positions.where((p) => p.isActive).length}',
            Icons.inventory,
            Colors.orange,
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
    );
  }

  Widget _buildLoadingSummary() {
    return Row(
      children: List.generate(6, (index) => Expanded(
        child: Container(
          margin: EdgeInsets.only(right: index < 5 ? 16 : 0),
          height: 100,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: CircularProgressIndicator()),
        ),
      )),
    );
  }

  Widget _buildErrorSummary() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error, color: Colors.red),
          Gap(12),
          Text('Error loading portfolio metrics'),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              Spacer(),
              Container(
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_upward, size: 12, color: color),
              ),
            ],
          ),
          Gap(12),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          Gap(4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionsList(BuildContext context, List<ManualPosition> positions) {
    if (positions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
            Gap(16),
            Text(
              'No Positions Yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            Gap(8),
            Text(
              'Add positions from the Market Scanner to start tracking your trades',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[500],
              ),
            ),
            Gap(24),
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to market scanner
              },
              icon: Icon(Icons.add_shopping_cart),
              label: Text('Browse Market Scanner'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    final activePositions = positions.where((p) => p.isActive).toList();
    final closedPositions = positions.where((p) => !p.isActive).toList();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: [
              Tab(text: 'Active (${activePositions.length})'),
              Tab(text: 'Closed (${closedPositions.length})'),
            ],
          ),
          Gap(16),
          Expanded(
            child: TabBarView(
              children: [
                _buildPositionsTab(context, activePositions, true),
                _buildPositionsTab(context, closedPositions, false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionsTab(BuildContext context, List<ManualPosition> positions, bool isActive) {
    if (positions.isEmpty) {
      return Center(
        child: Text(
          isActive ? 'No active positions' : 'No closed positions',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return ListView.builder(
      itemCount: positions.length,
      itemBuilder: (context, index) {
        final position = positions[index];
        return _buildPositionCard(context, position, isActive);
      },
    );
  }

  Widget _buildPositionCard(BuildContext context, ManualPosition position, bool isActive) {
    final pnlColor = position.unrealizedPnl >= 0 ? Colors.green : Colors.red;
    final pnlIcon = position.unrealizedPnl >= 0 ? Icons.trending_up : Icons.trending_down;

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: position.side == OrderSide.buy ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    position.side.name.toUpperCase(),
                    style: TextStyle(
                      color: position.side == OrderSide.buy ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                Gap(8),
                Text(
                  position.symbol,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Gap(8),
                Text(
                  '${position.quantity} shares',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                Spacer(),
                if (isActive) ...[
                  PopupMenuButton<String>(
                    onSelected: (value) => _handlePositionAction(context, position, value),
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'edit', child: Text('Edit Position')),
                      PopupMenuItem(value: 'close', child: Text('Close Position')),
                      PopupMenuItem(value: 'details', child: Text('View Details')),
                    ],
                    child: Icon(Icons.more_vert),
                  ),
                ],
              ],
            ),
            Gap(16),
            // Price and P&L info
            Row(
              children: [
                Expanded(
                  child: _buildPriceInfo('Entry', position.entryPrice, Colors.blue),
                ),
                Expanded(
                  child: _buildPriceInfo('Current', position.currentPrice, Colors.grey[700]!),
                ),
                Expanded(
                  child: _buildPriceInfo('Stop Loss', position.stopLoss, Colors.red),
                ),
                Expanded(
                  child: _buildPriceInfo('Take Profit', position.takeProfit, Colors.green),
                ),
              ],
            ),
            Gap(16),
            // P&L and metrics
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: pnlColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: pnlColor.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(pnlIcon, color: pnlColor, size: 16),
                            Gap(4),
                            Text(
                              'Unrealized P&L',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        Gap(4),
                        Text(
                          '${position.unrealizedPnl >= 0 ? '+' : ''}\$${position.unrealizedPnl.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: pnlColor,
                          ),
                        ),
                        Text(
                          '${position.pnlPercentage >= 0 ? '+' : ''}${position.pnlPercentage.toStringAsFixed(2)}%',
                          style: TextStyle(
                            fontSize: 14,
                            color: pnlColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Market Value', '\$${(position.currentPrice * position.quantity).toStringAsFixed(2)}'),
                      _buildInfoRow('Cost Basis', '\$${(position.entryPrice * position.quantity).toStringAsFixed(2)}'),
                      _buildInfoRow('Entry Time', _formatDateTime(position.entryTime)),
                    ],
                  ),
                ),
              ],
            ),
            if (isActive) ...[
              Gap(16),
              // Risk indicators
              Row(
                children: [
                  _buildRiskIndicator(
                    'Stop Loss Risk',
                    '${((position.entryPrice - position.stopLoss) / position.entryPrice * 100).toStringAsFixed(1)}%',
                    Colors.red,
                  ),
                  Gap(12),
                  _buildRiskIndicator(
                    'Take Profit Target',
                    '${((position.takeProfit - position.entryPrice) / position.entryPrice * 100).toStringAsFixed(1)}%',
                    Colors.green,
                  ),
                  Gap(12),
                  _buildRiskIndicator(
                    'Risk/Reward',
                    '1:${((position.takeProfit - position.entryPrice) / (position.entryPrice - position.stopLoss)).toStringAsFixed(1)}',
                    Colors.blue,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPriceInfo(String label, double price, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        Gap(4),
        Text(
          '\$${price.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskIndicator(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            Gap(2),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _handlePositionAction(BuildContext context, ManualPosition position, String action) {
    switch (action) {
      case 'edit':
        _showEditPositionDialog(context, position);
        break;
      case 'close':
        _showClosePositionDialog(context, position);
        break;
      case 'details':
        _showPositionDetails(context, position);
        break;
    }
  }

  void _showEditPositionDialog(BuildContext context, ManualPosition position) {
    final stopLossController = TextEditingController(text: position.stopLoss.toStringAsFixed(2));
    final takeProfitController = TextEditingController(text: position.takeProfit.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, child) => AlertDialog(
          title: Text('Edit ${position.symbol}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: stopLossController,
                decoration: InputDecoration(
                  labelText: 'Stop Loss',
                  prefixText: '\$',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
              Gap(16),
              TextField(
                controller: takeProfitController,
                decoration: InputDecoration(
                  labelText: 'Take Profit',
                  prefixText: '\$',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final stopLoss = double.tryParse(stopLossController.text);
                final takeProfit = double.tryParse(takeProfitController.text);
                
                if (stopLoss != null && takeProfit != null) {
                  ref.read(portfolioProvider.notifier).updatePosition(
                    position.id,
                    stopLoss: stopLoss,
                    takeProfit: takeProfit,
                  );
                  Navigator.of(context).pop();
                }
              },
              child: Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _showClosePositionDialog(BuildContext context, ManualPosition position) {
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, child) => AlertDialog(
          title: Text('Close Position'),
          content: Text('Are you sure you want to close your ${position.symbol} position?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                ref.read(portfolioProvider.notifier).closePosition(position.id);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${position.symbol} position closed'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('Close Position'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPositionDetails(BuildContext context, ManualPosition position) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: EdgeInsets.all(24),
          constraints: BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${position.symbol} Position Details',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Gap(24),
              _buildDetailRow('Symbol', position.symbol),
              _buildDetailRow('Side', position.side.name.toUpperCase()),
              _buildDetailRow('Quantity', '${position.quantity} shares'),
              _buildDetailRow('Entry Price', '\$${position.entryPrice.toStringAsFixed(2)}'),
              _buildDetailRow('Current Price', '\$${position.currentPrice.toStringAsFixed(2)}'),
              _buildDetailRow('Stop Loss', '\$${position.stopLoss.toStringAsFixed(2)}'),
              _buildDetailRow('Take Profit', '\$${position.takeProfit.toStringAsFixed(2)}'),
              _buildDetailRow('Market Value', '\$${(position.currentPrice * position.quantity).toStringAsFixed(2)}'),
              _buildDetailRow('Cost Basis', '\$${(position.entryPrice * position.quantity).toStringAsFixed(2)}'),
              _buildDetailRow('Unrealized P&L', '${position.unrealizedPnl >= 0 ? '+' : ''}\$${position.unrealizedPnl.toStringAsFixed(2)}'),
              _buildDetailRow('P&L Percentage', '${position.pnlPercentage >= 0 ? '+' : ''}${position.pnlPercentage.toStringAsFixed(2)}%'),
              _buildDetailRow('Entry Time', _formatDateTime(position.entryTime)),
              Gap(24),
              Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: value.contains('\$') && value.contains('+') ? Colors.green :
                     value.contains('\$') && value.contains('-') ? Colors.red :
                     Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Color _getHeatColor(double heat, double maxHeat) {
    final ratio = heat / maxHeat;
    if (ratio >= 0.8) return Colors.red;
    if (ratio >= 0.6) return Colors.orange;
    if (ratio >= 0.4) return Colors.yellow;
    return Colors.green;
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
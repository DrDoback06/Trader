import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../providers/app_providers.dart';
import '../../data/models.dart';

class MarketScannerScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signalsAsync = ref.watch(signalsProvider);
    final watchList = ref.watch(watchListProvider);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, ref),
          Gap(16),
          _buildFilters(context, ref),
          Gap(16),
          Expanded(
            child: signalsAsync.when(
              data: (signals) => _buildSignalsTable(context, ref, signals, watchList),
              loading: () => Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error, size: 48, color: Colors.red),
                    Gap(16),
                    Text('Error loading signals: $error'),
                    Gap(16),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(signalsProvider),
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

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Icon(Icons.search, size: 28),
        Gap(12),
        Text(
          'Market Scanner',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Spacer(),
        _buildAddSymbolButton(context, ref),
      ],
    );
  }

  Widget _buildAddSymbolButton(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () => _showAddSymbolDialog(context, ref),
      icon: Icon(Icons.add),
      label: Text('Add Symbol'),
    );
  }

  void _showAddSymbolDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Symbol to Watch List'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Enter symbol (e.g., AAPL)',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final symbol = controller.text.trim().toUpperCase();
              if (symbol.isNotEmpty) {
                ref.read(watchListProvider.notifier).addSymbol(symbol);
                Navigator.pop(context);
              }
            },
            child: Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Text('Filters:', style: Theme.of(context).textTheme.titleSmall),
        Gap(16),
        FilterChip(
          label: Text('Buy Signals'),
          selected: true,
          onSelected: (selected) {},
        ),
        Gap(8),
        FilterChip(
          label: Text('Sell Signals'),
          selected: true,
          onSelected: (selected) {},
        ),
        Gap(8),
        FilterChip(
          label: Text('High Strength'),
          selected: false,
          onSelected: (selected) {},
        ),
        Spacer(),
        Text(
          'Live updates every 300ms',
          style: Theme.of(context).textTheme.caption?.copyWith(
            color: Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildSignalsTable(
    BuildContext context,
    WidgetRef ref,
    List<Signal> signals,
    List<String> watchList,
  ) {
    if (signals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.signals_cellular_alt, size: 48, color: Colors.grey),
            Gap(16),
            Text(
              'No signals detected',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Gap(8),
            Text(
              'Waiting for trading agents to generate signals...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: SingleChildScrollView(
        physics: ClampingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortAscending: false,
          sortColumnIndex: 4, // Sort by timestamp
          columns: [
            DataColumn(
              label: Text('Symbol'),
              onSort: (index, ascending) {},
            ),
            DataColumn(
              label: Text('Side'),
              onSort: (index, ascending) {},
            ),
            DataColumn(
              label: Text('Strength'),
              numeric: true,
              onSort: (index, ascending) {},
            ),
            DataColumn(
              label: Text('Agent'),
              onSort: (index, ascending) {},
            ),
            DataColumn(
              label: Text('Time'),
              onSort: (index, ascending) {},
            ),
            DataColumn(
              label: Text('Reason'),
            ),
            DataColumn(
              label: Text('Watch'),
            ),
          ],
          rows: signals.map((signal) => DataRow(
            cells: [
              DataCell(
                Text(
                  signal.symbol,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                onTap: () {
                  // Set selected symbol for live chart
                  ref.read(selectedSymbolProvider.notifier).state = signal.symbol;
                },
              ),
              DataCell(
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: signal.type == SignalType.buy 
                        ? Colors.green.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    signal.type.name.toUpperCase(),
                    style: TextStyle(
                      color: signal.type == SignalType.buy ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              DataCell(
                _buildStrengthBar(signal.strength),
              ),
              DataCell(
                Chip(
                  label: Text(
                    signal.source,
                    style: TextStyle(fontSize: 10),
                  ),
                  backgroundColor: _getAgentColor(signal.source),
                ),
              ),
              DataCell(
                Text(
                  _formatTime(signal.timestamp),
                  style: TextStyle(fontSize: 12),
                ),
              ),
              DataCell(
                Container(
                  constraints: BoxConstraints(maxWidth: 200),
                  child: Text(
                    signal.metadata['reason']?.toString() ?? 'No reason',
                    style: TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(
                IconButton(
                  icon: Icon(
                    watchList.contains(signal.symbol) 
                        ? Icons.star 
                        : Icons.star_border,
                    color: watchList.contains(signal.symbol) 
                        ? Colors.amber 
                        : null,
                  ),
                  onPressed: () {
                    ref.read(watchListProvider.notifier).toggleSymbol(signal.symbol);
                  },
                  tooltip: watchList.contains(signal.symbol) 
                      ? 'Remove from watch list' 
                      : 'Add to watch list',
                ),
              ),
            ],
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildStrengthBar(double strength) {
    final percentage = (strength * 100).clamp(0, 100);
    Color color;
    
    if (percentage >= 80) {
      color = Colors.red;
    } else if (percentage >= 60) {
      color = Colors.orange;
    } else if (percentage >= 40) {
      color = Colors.yellow;
    } else {
      color = Colors.green;
    }

    return Container(
      width: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${percentage.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Gap(2),
          LinearProgressIndicator(
            value: strength,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ],
      ),
    );
  }

  Color _getAgentColor(String agentName) {
    switch (agentName) {
      case 'technical_agent':
        return Colors.blue.withOpacity(0.2);
      case 'sentiment_agent':
        return Colors.purple.withOpacity(0.2);
      case 'insider_agent':
        return Colors.orange.withOpacity(0.2);
      default:
        return Colors.grey.withOpacity(0.2);
    }
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
}
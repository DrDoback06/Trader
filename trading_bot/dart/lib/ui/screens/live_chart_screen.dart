import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:fl_chart/fl_chart.dart'; // Commented out due to compatibility issues
import 'package:gap/gap.dart';

import '../../providers/app_providers.dart';
import '../../data/models.dart';

class LiveChartScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<LiveChartScreen> createState() => _LiveChartScreenState();
}

class _LiveChartScreenState extends ConsumerState<LiveChartScreen> {
  String selectedTimeframe = '1m';
  
  @override
  Widget build(BuildContext context) {
    final chartData = ref.watch(chartDataProvider);
    final selectedSymbol = ref.watch(selectedSymbolProvider);

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(context),
          Gap(16),
          _buildControls(context),
          Gap(16),
          Expanded(
            child: chartData.when(
              data: (data) => _buildChartContent(context, data),
              loading: () => Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Text('Error loading chart data: $error'),
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
        Icon(Icons.show_chart, size: 28),
        Gap(12),
        Text(
          'Live Chart',
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
        // Refresh chart data
      },
      icon: Icon(Icons.refresh),
      tooltip: 'Refresh chart',
    );
  }

  Widget _buildControls(BuildContext context) {
    final selectedSymbol = ref.watch(selectedSymbolProvider);
    final watchList = ref.watch(watchListProvider);
    
    return Row(
      children: [
        // Symbol selector
        Expanded(
          child: DropdownButtonFormField<String>(
            value: selectedSymbol,
            decoration: InputDecoration(
              labelText: 'Symbol',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: watchList.map((symbol) => DropdownMenuItem(
              value: symbol,
              child: Text(symbol),
            )).toList(),
            onChanged: (value) {
              if (value != null) {
                ref.read(selectedSymbolProvider.notifier).state = value;
              }
            },
          ),
        ),
        Gap(16),
        // Timeframe selector
        Expanded(
          child: DropdownButtonFormField<String>(
            value: selectedTimeframe,
            decoration: InputDecoration(
              labelText: 'Timeframe',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: ['1m', '5m', '15m', '1h', '4h', '1d'].map((timeframe) => 
              DropdownMenuItem(
                value: timeframe,
                child: Text(timeframe),
              ),
            ).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  selectedTimeframe = value;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChartContent(BuildContext context, ChartData data) {
    return Column(
      children: [
        // Main price chart
        Expanded(
          flex: 3,
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Price Chart',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Gap(16),
                                     Expanded(
                     child: _buildPriceChart(data.candlesticks),
                   ),
                ],
              ),
            ),
          ),
        ),
        Gap(16),
        // Technical indicators
        Expanded(
          flex: 2,
          child: Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                                         child: _buildRSIChart(data.rsi),
                  ),
                ),
              ),
              Gap(16),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                                         child: _buildMACDChart(data.macd),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriceChart(List<CandlestickData> candlesticks) {
    if (candlesticks.isEmpty) {
      return Center(child: Text('No price data available'));
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 48, color: Colors.blue),
            Gap(8),
            Text('Price Chart', style: Theme.of(context).textTheme.titleMedium),
            Text('Chart loading...', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildRSIChart(List<RSIData> rsiData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RSI', style: TextStyle(fontWeight: FontWeight.bold)),
        Gap(8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.trending_up, size: 32, color: Colors.purple),
                  Gap(4),
                  Text('RSI Chart'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMACDChart(List<MACDData> macdData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MACD', style: TextStyle(fontWeight: FontWeight.bold)),
        Gap(8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.waves, size: 32, color: Colors.orange),
                  Gap(4),
                  Text('MACD Chart'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
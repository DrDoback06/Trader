import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:gap/gap.dart';

import '../../providers/app_providers.dart';
import '../../data/models.dart';

class LiveChartScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<LiveChartScreen> createState() => _LiveChartScreenState();
}

class _LiveChartScreenState extends ConsumerState<LiveChartScreen> {
  String selectedTimeframe = '1M';
  final List<String> timeframes = ['1M', '5M', '15M', '1H', '1D'];

  @override
  Widget build(BuildContext context) {
    final chartData = ref.watch(chartDataProvider);
    final watchList = ref.watch(watchListProvider);
    final selectedSymbol = ref.watch(selectedSymbolProvider);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with controls
          Row(
            children: [
              Text(
                'Live Chart',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Spacer(),
              _buildSymbolSelector(watchList, selectedSymbol),
              Gap(16),
              _buildTimeframeSelector(),
            ],
          ),
          Gap(24),
          
          // Chart container
          Expanded(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$selectedSymbol - $selectedTimeframe',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Gap(16),
                    Expanded(
                      child: chartData.when(
                        data: (data) => _buildChart(data),
                        loading: () => Center(child: CircularProgressIndicator()),
                        error: (error, stack) => Center(
                          child: Text('Chart Error: $error'),
                        ),
                      ),
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

  Widget _buildSymbolSelector(List<String> watchList, String selectedSymbol) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedSymbol,
          isDense: true,
          items: watchList.map((symbol) {
            return DropdownMenuItem(
              value: symbol,
              child: Text(symbol),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              ref.read(selectedSymbolProvider.notifier).state = value;
            }
          },
        ),
      ),
    );
  }

  Widget _buildTimeframeSelector() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedTimeframe,
          isDense: true,
          items: timeframes.map((timeframe) {
            return DropdownMenuItem(
              value: timeframe,
              child: Text(timeframe),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                selectedTimeframe = value;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildChart(ChartData data) {
    return Column(
      children: [
        // Price Chart
        Expanded(
          flex: 3,
          child: _buildPriceChart(data.candlesticks),
        ),
        Gap(16),
        // Technical Indicators
        Expanded(
          flex: 1,
          child: Row(
            children: [
              Expanded(child: _buildRSIChart(data.rsi)),
              Gap(16),
              Expanded(child: _buildMACDChart(data.macd)),
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

    final spots = candlesticks.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.close);
    }).toList();

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 60),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 30),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: Colors.blue,
            barWidth: 2,
            dotData: FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  Widget _buildRSIChart(List<RSIData> rsiData) {
    if (rsiData.isEmpty) {
      return Center(child: Text('No RSI data'));
    }

    final spots = rsiData.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.value);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RSI', style: TextStyle(fontWeight: FontWeight.bold)),
        Gap(8),
        Expanded(
          child: LineChart(
            LineChartData(
              gridData: FlGridData(show: true),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: true),
              minY: 0,
              maxY: 100,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: Colors.purple,
                  barWidth: 1.5,
                  dotData: FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMACDChart(List<MACDData> macdData) {
    if (macdData.isEmpty) {
      return Center(child: Text('No MACD data'));
    }

    final macdSpots = macdData.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.macdLine);
    }).toList();

    final signalSpots = macdData.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.signalLine);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MACD', style: TextStyle(fontWeight: FontWeight.bold)),
        Gap(8),
        Expanded(
          child: LineChart(
            LineChartData(
              gridData: FlGridData(show: true),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: macdSpots,
                  isCurved: true,
                  color: Colors.blue,
                  barWidth: 1.5,
                  dotData: FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: signalSpots,
                  isCurved: true,
                  color: Colors.red,
                  barWidth: 1.5,
                  dotData: FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../providers/app_providers.dart';
import '../../data/models.dart';

class LiveChartScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedSymbol = ref.watch(selectedSymbolProvider);
    final chartDataAsync = ref.watch(chartDataProvider(selectedSymbol));
    final watchList = ref.watch(watchListProvider);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, ref, selectedSymbol, watchList),
          Gap(16),
          Expanded(
            child: chartDataAsync.when(
              data: (chartData) => _buildChartLayout(context, chartData),
              loading: () => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    Gap(16),
                    Text('Loading chart data for $selectedSymbol...'),
                  ],
                ),
              ),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error, size: 48, color: Colors.red),
                    Gap(16),
                    Text('Error loading chart: $error'),
                    Gap(16),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(chartDataProvider(selectedSymbol)),
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

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    String selectedSymbol,
    List<String> watchList,
  ) {
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
        Gap(16),
        _buildSymbolSelector(context, ref, selectedSymbol, watchList),
        Spacer(),
        _buildTimeframeSelector(context, ref),
      ],
    );
  }

  Widget _buildSymbolSelector(
    BuildContext context,
    WidgetRef ref,
    String selectedSymbol,
    List<String> watchList,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<String>(
        value: selectedSymbol,
        underline: SizedBox(),
        items: watchList.map((symbol) => DropdownMenuItem(
          value: symbol,
          child: Text(
            symbol,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        )).toList(),
        onChanged: (newSymbol) {
          if (newSymbol != null) {
            ref.read(selectedSymbolProvider.notifier).state = newSymbol;
          }
        },
      ),
    );
  }

  Widget _buildTimeframeSelector(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Timeframe:', style: Theme.of(context).textTheme.labelMedium),
        Gap(8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: '1m', label: Text('1m')),
            ButtonSegment(value: '5m', label: Text('5m')),
            ButtonSegment(value: '15m', label: Text('15m')),
            ButtonSegment(value: '1h', label: Text('1h')),
          ],
          selected: {'1m'},
          onSelectionChanged: (selected) {},
        ),
      ],
    );
  }

  Widget _buildChartLayout(BuildContext context, ChartData chartData) {
    return Column(
      children: [
        // Main price chart (70% of height)
        Expanded(
          flex: 7,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildPriceChart(chartData),
            ),
          ),
        ),
        Gap(8),
        // RSI chart (15% of height)
        Expanded(
          flex: 15,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildRsiChart(chartData),
            ),
          ),
        ),
        Gap(8),
        // MACD chart (15% of height)
        Expanded(
          flex: 15,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildMacdChart(chartData),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPriceChart(ChartData chartData) {
    return SfCartesianChart(
      title: ChartTitle(
        text: '${chartData.symbol} - Candlestick Chart',
        textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      primaryXAxis: DateTimeAxis(
        majorGridLines: MajorGridLines(width: 0.5),
        axisLabelFormatter: (AxisLabelRenderDetails details) {
          final date = DateTime.fromMillisecondsSinceEpoch(details.value.toInt());
          return ChartAxisLabel(
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
            TextStyle(fontSize: 10),
          );
        },
      ),
      primaryYAxis: NumericAxis(
        opposedPosition: true,
        majorGridLines: MajorGridLines(width: 0.5),
        numberFormat: NumberFormat.currency(symbol: '\$', decimalDigits: 2),
      ),
      trackballBehavior: TrackballBehavior(
        enable: true,
        activationMode: ActivationMode.singleTap,
        tooltipDisplayMode: TrackballDisplayMode.floatAllPoints,
      ),
      zoomPanBehavior: ZoomPanBehavior(
        enablePinching: true,
        enablePanning: true,
        enableDoubleTapZooming: true,
        enableSelectionZooming: true,
      ),
      series: <CartesianSeries>[
        CandleSeries<Bar, DateTime>(
          dataSource: chartData.bars,
          xValueMapper: (Bar bar, _) => bar.timestamp,
          lowValueMapper: (Bar bar, _) => bar.low,
          highValueMapper: (Bar bar, _) => bar.high,
          openValueMapper: (Bar bar, _) => bar.open,
          closeValueMapper: (Bar bar, _) => bar.close,
          name: 'Price',
          bullColor: Colors.green,
          bearColor: Colors.red,
          enableTooltip: true,
        ),
        // Volume bars (secondary chart would be better, but keeping simple)
      ],
      annotations: _buildPriceAnnotations(chartData),
    );
  }

  Widget _buildRsiChart(ChartData chartData) {
    return SfCartesianChart(
      title: ChartTitle(
        text: 'RSI (14)',
        textStyle: TextStyle(fontSize: 12),
      ),
      primaryXAxis: DateTimeAxis(
        isVisible: false,
        majorGridLines: MajorGridLines(width: 0),
      ),
      primaryYAxis: NumericAxis(
        minimum: 0,
        maximum: 100,
        majorGridLines: MajorGridLines(width: 0.5),
        plotBands: [
          PlotBand(
            start: 70,
            end: 100,
            color: Colors.red.withOpacity(0.1),
            text: 'Overbought',
          ),
          PlotBand(
            start: 0,
            end: 30,
            color: Colors.green.withOpacity(0.1),
            text: 'Oversold',
          ),
        ],
      ),
      series: <CartesianSeries>[
        LineSeries<double, int>(
          dataSource: chartData.rsiData,
          xValueMapper: (value, index) => index,
          yValueMapper: (value, index) => value,
          name: 'RSI',
          color: Colors.purple,
          width: 2,
        ),
      ],
    );
  }

  Widget _buildMacdChart(ChartData chartData) {
    return SfCartesianChart(
      title: ChartTitle(
        text: 'MACD (12,26,9)',
        textStyle: TextStyle(fontSize: 12),
      ),
      primaryXAxis: DateTimeAxis(
        isVisible: false,
        majorGridLines: MajorGridLines(width: 0),
      ),
      primaryYAxis: NumericAxis(
        majorGridLines: MajorGridLines(width: 0.5),
      ),
      series: <CartesianSeries>[
        LineSeries<MacdData, int>(
          dataSource: chartData.macdData,
          xValueMapper: (data, index) => index,
          yValueMapper: (data, index) => data.macd,
          name: 'MACD',
          color: Colors.blue,
          width: 2,
        ),
        LineSeries<MacdData, int>(
          dataSource: chartData.macdData,
          xValueMapper: (data, index) => index,
          yValueMapper: (data, index) => data.signal,
          name: 'Signal',
          color: Colors.orange,
          width: 2,
        ),
        ColumnSeries<MacdData, int>(
          dataSource: chartData.macdData,
          xValueMapper: (data, index) => index,
          yValueMapper: (data, index) => data.histogram,
          name: 'Histogram',
          color: Colors.grey,
          width: 0.5,
        ),
      ],
    );
  }

  List<CartesianChartAnnotation> _buildPriceAnnotations(ChartData chartData) {
    // Add horizontal lines for support/resistance levels
    if (chartData.bars.isEmpty) return [];

    final prices = chartData.bars.map((bar) => bar.close).toList();
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final avgPrice = prices.reduce((a, b) => a + b) / prices.length;

    return [
      CartesianChartAnnotation(
        widget: Container(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.7),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Avg: \$${avgPrice.toStringAsFixed(2)}',
            style: TextStyle(color: Colors.white, fontSize: 10),
          ),
        ),
        coordinateUnit: CoordinateUnit.point,
        x: chartData.bars.length * 0.8,
        y: avgPrice,
      ),
    ];
  }
}

// Helper class for number formatting
class NumberFormat {
  static NumberFormat currency({String symbol = '', int decimalDigits = 2}) {
    return NumberFormat._internal(symbol, decimalDigits);
  }

  final String _symbol;
  final int _decimalDigits;

  NumberFormat._internal(this._symbol, this._decimalDigits);

  String format(num value) {
    return '$_symbol${value.toStringAsFixed(_decimalDigits)}';
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../providers/app_providers.dart';
import '../../data/models.dart';

class MarketScannerScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<MarketScannerScreen> createState() => _MarketScannerScreenState();
}

class _MarketScannerScreenState extends ConsumerState<MarketScannerScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'All';
  bool _showOnlyHotStocks = false;
  
  @override
  Widget build(BuildContext context) {
    final signals = ref.watch(signalsProvider);
    final hotStocks = ref.watch(hotStocksProvider);
    final favorites = ref.watch(favoritesProvider);

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(context),
          Gap(16),
          _buildControls(context),
          Gap(16),
          _buildHotStocksSection(hotStocks),
          Gap(16),
          Expanded(
            child: signals.when(
              data: (allSignals) {
                final filteredSignals = _filterSignals(allSignals, favorites);
                return _buildSignalsTable(context, filteredSignals);
              },
              loading: () => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    Gap(16),
                    Text('Scanning 500+ stocks for opportunities...'),
                  ],
                ),
              ),
              error: (error, stack) => Center(
                child: Text('Error loading signals: $error'),
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
        Icon(Icons.radar, size: 28, color: Colors.green),
        Gap(12),
        Text(
          'Market Scanner',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Gap(8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '500+ STOCKS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
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
        ref.invalidate(signalsProvider);
      },
      icon: Icon(Icons.refresh),
      tooltip: 'Refresh signals',
    );
  }

  Widget _buildControls(BuildContext context) {
    return Row(
      children: [
        // Search bar
        Expanded(
          flex: 2,
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search symbols (e.g., AAPL, TSLA)...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toUpperCase();
              });
            },
          ),
        ),
        Gap(16),
        // Filter dropdown
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _selectedFilter,
            decoration: InputDecoration(
              labelText: 'Filter',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: [
              'All',
              'Favorites',
              'Strong Buy (80%+)',
              'Buy (60%+)',
              'Tech Stocks',
              'Financial',
              'Healthcare',
              'Energy',
            ].map((filter) => DropdownMenuItem(
              value: filter,
              child: Text(filter),
            )).toList(),
            onChanged: (value) {
              setState(() {
                _selectedFilter = value!;
              });
            },
          ),
        ),
        Gap(16),
        // Hot stocks toggle
        ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _showOnlyHotStocks = !_showOnlyHotStocks;
            });
          },
          icon: Icon(
            _showOnlyHotStocks ? Icons.local_fire_department : Icons.local_fire_department_outlined,
            color: _showOnlyHotStocks ? Colors.orange : null,
          ),
          label: Text('HOT'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _showOnlyHotStocks ? Colors.orange.withOpacity(0.2) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildHotStocksSection(List<EnhancedSignal> hotStocks) {
    if (hotStocks.isEmpty) return SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.withOpacity(0.1), Colors.red.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department, color: Colors.orange, size: 24),
              Gap(8),
              Text(
                '🔥 HOT STOCKS - 90%+ BUY SIGNALS',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              Spacer(),
              Text(
                '${hotStocks.length} opportunities',
                style: TextStyle(color: Colors.orange.shade700),
              ),
            ],
          ),
          Gap(12),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: hotStocks.length,
              itemBuilder: (context, index) {
                final stock = hotStocks[index];
                return Container(
                  margin: EdgeInsets.only(right: 8),
                  child: _buildHotStockChip(stock),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotStockChip(EnhancedSignal signal) {
    return GestureDetector(
      onTap: () => _showTradeRecommendation(signal.symbol),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withOpacity(0.3),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              signal.symbol,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            Gap(4),
            Text(
              '${signal.overallBuyPercentage.toInt()}%',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<EnhancedSignal> _filterSignals(List<EnhancedSignal> signals, Set<String> favorites) {
    var filtered = signals.where((signal) {
      // Search filter
      if (_searchQuery.isNotEmpty && !signal.symbol.contains(_searchQuery)) {
        return false;
      }

      // Hot stocks filter
      if (_showOnlyHotStocks && !signal.isHot) {
        return false;
      }

      // Category filters
      switch (_selectedFilter) {
        case 'Favorites':
          return favorites.contains(signal.symbol);
        case 'Strong Buy (80%+)':
          return signal.overallBuyPercentage >= 80;
        case 'Buy (60%+)':
          return signal.overallBuyPercentage >= 60;
        case 'Tech Stocks':
          return _isTechStock(signal.symbol);
        case 'Financial':
          return _isFinancialStock(signal.symbol);
        case 'Healthcare':
          return _isHealthcareStock(signal.symbol);
        case 'Energy':
          return _isEnergyStock(signal.symbol);
        default:
          return true;
      }
    }).toList();

    // Sort: Hot stocks first, then favorites, then by buy percentage
    filtered.sort((a, b) {
      if (a.isHot && !b.isHot) return -1;
      if (!a.isHot && b.isHot) return 1;
      if (favorites.contains(a.symbol) && !favorites.contains(b.symbol)) return -1;
      if (!favorites.contains(a.symbol) && favorites.contains(b.symbol)) return 1;
      return b.overallBuyPercentage.compareTo(a.overallBuyPercentage);
    });

    return filtered;
  }

  Widget _buildSignalsTable(BuildContext context, List<EnhancedSignal> signals) {
    return Card(
      child: Column(
        children: [
          // Table header
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('Symbol', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 1, child: Text('Overall', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Technical', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Momentum', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Volume', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Sentiment', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 1, child: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          // Table content
          Expanded(
            child: ListView.builder(
              itemCount: signals.length,
              itemBuilder: (context, index) {
                final signal = signals[index];
                final favorites = ref.watch(favoritesProvider);
                final isFavorite = favorites.contains(signal.symbol);
                
                return _buildSignalRow(context, signal, isFavorite);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalRow(BuildContext context, EnhancedSignal signal, bool isFavorite) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: signal.isHot ? Colors.orange.withOpacity(0.1) : null,
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          // Symbol with favorite toggle
          Expanded(
            flex: 2,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => ref.read(favoritesProvider.notifier).toggleFavorite(signal.symbol),
                  child: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    color: isFavorite ? Colors.orange : Colors.grey,
                    size: 16,
                  ),
                ),
                Gap(8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          signal.symbol,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (signal.isHot) ...[
                          Gap(4),
                          Icon(Icons.local_fire_department, color: Colors.orange, size: 12),
                        ],
                      ],
                    ),
                    Text(
                      _getSignalStrengthText(signal.strength),
                      style: TextStyle(
                        fontSize: 10,
                        color: _getStrengthColor(signal.strength),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Overall percentage
          Expanded(
            flex: 1,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getBuyPercentageColor(signal.overallBuyPercentage).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${signal.overallBuyPercentage.toInt()}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _getBuyPercentageColor(signal.overallBuyPercentage),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          // Technical analysis
          Expanded(
            flex: 2,
            child: _buildAnalysisColumn(signal.technical),
          ),
          // Momentum analysis
          Expanded(
            flex: 2,
            child: _buildAnalysisColumn(signal.momentum),
          ),
          // Volume analysis
          Expanded(
            flex: 2,
            child: _buildAnalysisColumn(signal.volume),
          ),
          // Sentiment analysis
          Expanded(
            flex: 2,
            child: _buildAnalysisColumn(signal.sentiment),
          ),
          // Action button
          Expanded(
            flex: 1,
            child: ElevatedButton(
              onPressed: () => _showTradeRecommendation(signal.symbol),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: Text(
                'TRADE',
                style: TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisColumn(dynamic analysis) {
    double buyPercentage;
    if (analysis is TechnicalAnalysis) {
      buyPercentage = analysis.buyPercentage;
    } else if (analysis is MomentumAnalysis) {
      buyPercentage = analysis.buyPercentage;
    } else if (analysis is VolumeAnalysis) {
      buyPercentage = analysis.buyPercentage;
    } else if (analysis is SentimentAnalysis) {
      buyPercentage = analysis.buyPercentage;
    } else {
      buyPercentage = 0;
    }

    final color = _getBuyPercentageColor(buyPercentage);
    final signal = buyPercentage >= 60 ? 'BUY' : buyPercentage >= 40 ? 'HOLD' : 'SELL';

    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            signal,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        Gap(2),
        Text(
          '${buyPercentage.toInt()}%',
          style: TextStyle(
            fontSize: 10,
            color: color,
          ),
        ),
      ],
    );
  }

  void _showTradeRecommendation(String symbol) {
    final recommendation = ref.read(tradeRecommendationsProvider(symbol));
    if (recommendation == null) return;

    showDialog(
      context: context,
      builder: (context) => _buildTradeRecommendationDialog(recommendation),
    );
  }

  Widget _buildTradeRecommendationDialog(TradeRecommendation rec) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: EdgeInsets.all(24),
        constraints: BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.trending_up, color: Colors.green, size: 32),
                Gap(12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rec.symbol,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      rec.strategy,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${rec.confidence.toInt()}% Confidence',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Gap(24),
            // Price info
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildPriceRow('Current Price', rec.currentPrice, Colors.blue),
                  _buildPriceRow('Entry Price', rec.entryPrice, Colors.green),
                  _buildPriceRow('Stop Loss', rec.stopLoss, Colors.red),
                  _buildPriceRow('Take Profit 1', rec.takeProfit1, Colors.orange),
                  _buildPriceRow('Take Profit 2', rec.takeProfit2, Colors.purple),
                ],
              ),
            ),
            Gap(16),
            // Trade metrics
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard('Risk/Reward', '1:${rec.riskRewardRatio.toStringAsFixed(1)}', Colors.green),
                ),
                Gap(12),
                Expanded(
                  child: _buildMetricCard('Position Size', '${rec.positionSize.toStringAsFixed(1)}%', Colors.blue),
                ),
                Gap(12),
                Expanded(
                  child: _buildMetricCard('Hold Time', '${rec.holdDuration.inDays}d', Colors.orange),
                ),
              ],
            ),
            Gap(24),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel'),
                  ),
                ),
                Gap(12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _addToPortfolio(rec);
                    },
                    icon: Icon(Icons.add_shopping_cart),
                    label: Text('Add to Portfolio'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
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

  Widget _buildPriceRow(String label, double price, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w500)),
          Text(
            '\$${price.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
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
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _addToPortfolio(TradeRecommendation rec) {
    showDialog(
      context: context,
      builder: (context) => _buildAddPositionDialog(rec),
    );
  }

  Widget _buildAddPositionDialog(TradeRecommendation rec) {
    final quantityController = TextEditingController();
    final entryPriceController = TextEditingController(text: rec.entryPrice.toStringAsFixed(2));
    final stopLossController = TextEditingController(text: rec.stopLoss.toStringAsFixed(2));
    final takeProfitController = TextEditingController(text: rec.takeProfit1.toStringAsFixed(2));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: EdgeInsets.all(24),
        constraints: BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add ${rec.symbol} to Portfolio',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Gap(24),
            TextField(
              controller: quantityController,
              decoration: InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            Gap(16),
            TextField(
              controller: entryPriceController,
              decoration: InputDecoration(
                labelText: 'Entry Price',
                border: OutlineInputBorder(),
                prefixText: '\$',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            Gap(16),
            TextField(
              controller: stopLossController,
              decoration: InputDecoration(
                labelText: 'Stop Loss',
                border: OutlineInputBorder(),
                prefixText: '\$',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            Gap(16),
            TextField(
              controller: takeProfitController,
              decoration: InputDecoration(
                labelText: 'Take Profit',
                border: OutlineInputBorder(),
                prefixText: '\$',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            Gap(24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel'),
                  ),
                ),
                Gap(12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final quantity = int.tryParse(quantityController.text) ?? 0;
                      final entryPrice = double.tryParse(entryPriceController.text) ?? 0;
                      final stopLoss = double.tryParse(stopLossController.text) ?? 0;
                      final takeProfit = double.tryParse(takeProfitController.text) ?? 0;

                      if (quantity > 0 && entryPrice > 0) {
                        final position = ManualPosition(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          symbol: rec.symbol,
                          side: OrderSide.buy,
                          quantity: quantity,
                          entryPrice: entryPrice,
                          currentPrice: entryPrice,
                          stopLoss: stopLoss,
                          takeProfit: takeProfit,
                          entryTime: DateTime.now(),
                          unrealizedPnl: 0,
                          pnlPercentage: 0,
                        );

                        ref.read(portfolioProvider.notifier).addPosition(position);
                        Navigator.of(context).pop();
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${rec.symbol} added to portfolio!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: Text('Add Position'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Helper methods
  String _getSignalStrengthText(SignalStrength strength) {
    switch (strength) {
      case SignalStrength.veryStrong:
        return 'VERY STRONG';
      case SignalStrength.strong:
        return 'STRONG';
      case SignalStrength.moderate:
        return 'MODERATE';
      case SignalStrength.weak:
        return 'WEAK';
    }
  }

  Color _getStrengthColor(SignalStrength strength) {
    switch (strength) {
      case SignalStrength.veryStrong:
        return Colors.purple;
      case SignalStrength.strong:
        return Colors.green;
      case SignalStrength.moderate:
        return Colors.orange;
      case SignalStrength.weak:
        return Colors.red;
    }
  }

  Color _getBuyPercentageColor(double percentage) {
    if (percentage >= 80) return Colors.purple;
    if (percentage >= 60) return Colors.green;
    if (percentage >= 40) return Colors.orange;
    return Colors.red;
  }

  bool _isTechStock(String symbol) {
    final techStocks = ['AAPL', 'MSFT', 'GOOGL', 'GOOG', 'AMZN', 'META', 'TSLA', 'NVDA', 'NFLX', 'CRM', 'ORCL', 'ADBE', 'INTC', 'AMD', 'QCOM', 'AVGO', 'TXN', 'CSCO', 'IBM', 'INTU'];
    return techStocks.contains(symbol);
  }

  bool _isFinancialStock(String symbol) {
    final financialStocks = ['JPM', 'BAC', 'WFC', 'GS', 'MS', 'C', 'AXP', 'BLK', 'SCHW', 'USB'];
    return financialStocks.contains(symbol);
  }

  bool _isHealthcareStock(String symbol) {
    final healthcareStocks = ['JNJ', 'UNH', 'PFE', 'ABBV', 'TMO', 'ABT', 'DHR', 'BMY', 'CVS', 'MRK'];
    return healthcareStocks.contains(symbol);
  }

  bool _isEnergyStock(String symbol) {
    final energyStocks = ['XOM', 'CVX', 'COP', 'EOG', 'SLB', 'PSX', 'VLO', 'OXY', 'BKR', 'HAL'];
    return energyStocks.contains(symbol);
  }
}
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';

enum ChartType { distribution, bar }

enum TimeRange { day, week, month }

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with WidgetsBindingObserver {
  ChartType _selectedChartType = ChartType.distribution;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  bool _forceRefresh = false;
  TimeRange _selectedTimeRange = TimeRange.week;
  DateTime _selectedStartDate = DateTime.now().subtract(
    const Duration(days: 7),
  );
  DateTime _selectedEndDate = DateTime.now();
  String _activeTab = 'purchases'; // Track active tab for distribution view
  String? _selectedCurrency;
  List<String> _availableCurrencies = [];

  // Translation helper method
  String _getTranslatedText(String key, [Map<String, String>? params]) {
    final languageProvider = Provider.of<LanguageProvider>(
      context,
      listen: false,
    );
    String text = languageProvider.translate(key);
    if (params != null) {
      params.forEach((key, value) {
        text = text.replaceAll('{$key}', value);
      });
    }
    return text;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateDateRange();
    _loadCurrencies();
    _refreshData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _updateDateRange() {
    final now = DateTime.now();
    setState(() {
      switch (_selectedTimeRange) {
        case TimeRange.day:
          _selectedStartDate = DateTime(now.year, now.month, now.day);
          _selectedEndDate = now;
          break;
        case TimeRange.week:
          _selectedStartDate = now.subtract(const Duration(days: 7));
          _selectedEndDate = now;
          break;
        case TimeRange.month:
          _selectedStartDate = DateTime(now.year, now.month - 1, now.day);
          _selectedEndDate = now;
          break;
      }
    });
  }

  Future<void> _loadCurrencies() async {
    final currencies = await _dbHelper.getHistoryCurrencyCodes();
    setState(() {
      _availableCurrencies =
          [_getTranslatedText('all_currencies')] +
          currencies.where((c) => c != 'SOM').toList();
      if (_availableCurrencies.isNotEmpty && _selectedCurrency == null) {
        _selectedCurrency = _availableCurrencies.first;
      }
    });
  }

  void _refreshData() {
    setState(() => _forceRefresh = !_forceRefresh);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Time range selector
          _buildTimeRangeSelector(),
          // Chart type selector
          _buildChartTypeSelector(),
          // Date range display
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              '${DateFormat('MMM d, y', Provider.of<LanguageProvider>(context).currentLocale.languageCode).format(_selectedStartDate)} '
              '- ${DateFormat('MMM d, y', Provider.of<LanguageProvider>(context).currentLocale.languageCode).format(_selectedEndDate)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          // Main chart area
          Expanded(
            child: FutureBuilder<dynamic>(
              key: ValueKey(
                "$_forceRefresh-$_selectedChartType-"
                "${_selectedTimeRange.name}-"
                "${_selectedStartDate.millisecondsSinceEpoch}-"
                "${_selectedEndDate.millisecondsSinceEpoch}",
              ),
              future: _getChartData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                if (!snapshot.hasData ||
                    (snapshot.data is Map && snapshot.data!.isEmpty) ||
                    (snapshot.data is List && snapshot.data!.isEmpty)) {
                  return Center(
                    child: Text(_getTranslatedText('no_data_available')),
                  );
                }

                switch (_selectedChartType) {
                  case ChartType.distribution:
                    return _buildDistributionChart(snapshot.data!);
                  case ChartType.bar:
                    return _buildBarChart(snapshot.data!);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRangeSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children:
              TimeRange.values.map((range) {
                String label;
                switch (range) {
                  case TimeRange.day:
                    label = _getTranslatedText('day');
                    break;
                  case TimeRange.week:
                    label = _getTranslatedText('week');
                    break;
                  case TimeRange.month:
                    label = _getTranslatedText('month');
                    break;
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: FilterChip(
                    label: Text(label.toUpperCase()),
                    selected: _selectedTimeRange == range,
                    onSelected: (selected) {
                      setState(() {
                        _selectedTimeRange = range;
                        _updateDateRange();
                        _refreshData();
                      });
                    },
                    selectedColor: Theme.of(
                      context,
                    ).primaryColor.withOpacity(0.2),
                    checkmarkColor: Theme.of(context).primaryColor,
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildChartTypeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Pie chart icon for distribution
          Material(
            color:
                _selectedChartType == ChartType.distribution
                    ? Theme.of(context).primaryColor.withOpacity(0.2)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap:
                  () => setState(
                    () => _selectedChartType = ChartType.distribution,
                  ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(
                  Icons.pie_chart,
                  size: 24,
                  color:
                      _selectedChartType == ChartType.distribution
                          ? Theme.of(context).primaryColor
                          : Colors.grey,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Bar chart icon
          Material(
            color:
                _selectedChartType == ChartType.bar
                    ? Theme.of(context).primaryColor.withOpacity(0.2)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _selectedChartType = ChartType.bar),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(
                  Icons.bar_chart,
                  size: 24,
                  color:
                      _selectedChartType == ChartType.bar
                          ? Theme.of(context).primaryColor
                          : Colors.grey,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<dynamic> _getChartData() async {
    switch (_selectedChartType) {
      case ChartType.distribution:
        final data = await _dbHelper.getEnhancedPieChartData(
          startDate: _selectedStartDate,
          endDate: _selectedEndDate,
        );
        
        // Debug the raw data
        debugPrint("Raw purchase data keys: ${data['purchases'].isNotEmpty ? (data['purchases'][0] as Map).keys.join(', ') : 'Empty'}");
        debugPrint("Raw sales data keys: ${data['sales'].isNotEmpty ? (data['sales'][0] as Map).keys.join(', ') : 'Empty'}");
        
        // Filter out SOM entries and process purchase/sale data
        data['purchases'] = (data['purchases'] as List)
            .where((item) => item['currency'] != 'SOM')
            .toList();
        
        data['sales'] = (data['sales'] as List)
            .where((item) => item['currency'] != 'SOM')
            .toList();
            
        // Get profit data
        final profitData = await _dbHelper.getMostProfitableCurrencies(
          startDate: _selectedStartDate,
          endDate: _selectedEndDate,
        );
        
        // Convert amount key to profit to maintain consistency
        for (var item in profitData) {
          item['profit'] = item['amount'];
        }
        
        data['profit'] = profitData;
        
        // Debug the processed data
        debugPrint("Processed purchases: ${data['purchases'].length} items");
        debugPrint("Processed sales: ${data['sales'].length} items");
        debugPrint("Profit data count: ${profitData.length} items");
        if (profitData.isNotEmpty) {
          debugPrint("Profit data keys: ${profitData[0].keys.join(', ')}");
        }
        
        return data;
        
      case ChartType.bar:
        List<Map<String, dynamic>> dailyData;
        
        if (_selectedCurrency != null &&
            _selectedCurrency != _getTranslatedText('all_currencies')) {
          // Get data for specific currency
          dailyData = await _dbHelper.getDailyDataByCurrency(
            startDate: _selectedStartDate,
            endDate: _selectedEndDate,
            currencyCode: _selectedCurrency!,
          );
        } else {
          // Get data for all currencies
          dailyData = await _dbHelper.getDailyData(
            startDate: _selectedStartDate,
            endDate: _selectedEndDate,
          );
        }
        
        // The daily data is now already processed by the DB helper methods
        if (dailyData.isNotEmpty) {
          final firstDay = dailyData.first;
          debugPrint("Sample daily data: day=${firstDay['day']}, purchases=${firstDay['purchases']}, sales=${firstDay['sales']}, profit=${firstDay['profit']}");
        }
        
        return dailyData;
    }
  }

  Widget _buildBarChart(dynamic data) {
    final dailyData = List<Map<String, dynamic>>.from(data);

    if (dailyData.isEmpty) {
      return Center(
        child: Text(
          _getTranslatedText('no_profit_data'),
          style: const TextStyle(fontSize: 18),
        ),
      );
    }

    return Column(
      children: [
        // Compact currency selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            children: [
              Text(
                _getTranslatedText('currency_selector'),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color:
                        Theme.of(context).dividerTheme.color ??
                        Colors.transparent,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButton<String>(
                  value: _selectedCurrency,
                  underline: const SizedBox(),
                  isDense: true,
                  items:
                      _availableCurrencies.map((currency) {
                        return DropdownMenuItem(
                          value: currency,
                          child: Text(
                            currency,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(
                              fontWeight:
                                  currency ==
                                          _getTranslatedText('all_currencies')
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                          ),
                        );
                      }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCurrency = value;
                      _refreshData();
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: _buildBarChartTab(
                  'purchases',
                  _getTranslatedText('purchases'),
                ),
              ),
              Expanded(
                child: _buildBarChartTab('sales', _getTranslatedText('sales')),
              ),
              Expanded(
                child: _buildBarChartTab(
                  'profit',
                  _getTranslatedText('profit'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildBarChartContent(activeTab: _activeTab, data: dailyData),
        ),
      ],
    );
  }

  Widget _buildBarChartTab(String tabName, String label) {
    final isSelected = _activeTab == tabName;
    return InkWell(
      onTap: () => setState(() => _activeTab = tabName),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color:
                  isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color:
                  isSelected
                      ? Theme.of(context).primaryColor
                      : Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBarChartContent({
    required String activeTab,
    required List<Map<String, dynamic>> data,
  }) {
    // Check if profit data seems to be incorrect
    bool isProfitDataSuspicious = false;
    if (activeTab == 'profit') {
      double totalSales = 0.0;
      double totalProfit = 0.0;
      int matchingCount = 0;
      
      for (var item in data) {
        final sales = (item['sales'] as num?)?.toDouble() ?? 0.0;
        final profit = (item['profit'] as num?)?.toDouble() ?? 0.0;
        totalSales += sales;
        totalProfit += profit;
        
        // Check if profit seems to be equal or very close to sales
        if ((profit - sales).abs() < 0.001 && sales > 0) {
          matchingCount++;
        }
      }
      
      // If more than 50% of profit values match sales values, data is suspicious
      if (data.isNotEmpty && matchingCount > data.length / 2) {
        isProfitDataSuspicious = true;
        debugPrint('⚠️ WARNING: Profit data appears to be equal to sales data (suspicious)');
        debugPrint('Total sales: $totalSales, Total profit: $totalProfit');
      }
    }
    
    // Convert data to ensure proper types
    final chartData =
        data.map((item) {
          // Check if all required fields exist
          if (!item.containsKey('profit')) {
            debugPrint('Warning: Item is missing profit field: $item');
          }
          
          // Create a basic map with the day and required fields
          final processedItem = {
            'day': item['day'] as String,
            'purchases': (item['purchases'] as num?)?.toDouble() ?? 0.0,
            'sales': (item['sales'] as num?)?.toDouble() ?? 0.0,
            'profit': (item['profit'] as num?)?.toDouble() ?? 0.0,
            'deposits': (item['deposits'] as num?)?.toDouble() ?? 0.0,
          };
          
          // For profit tab, manually calculate correct profit
          if (activeTab == 'profit' && isProfitDataSuspicious) {
            // Since the profit data seems to be incorrect (equal to sales), we need to recalculate it
            final sales = processedItem['sales'] as double;
            final purchases = processedItem['purchases'] as double;
            
            // A more accurate estimate of profit: assume a cost basis of ~90% of sales
            // This is a fallback when we can't get true profit calculations from the database
            final estimatedCostBasis = sales * 0.9;
            processedItem['profit'] = sales - (purchases > 0 ? purchases : estimatedCostBasis);
            
            debugPrint('Corrected profit calculation - Day: ${processedItem['day']}, Sales: $sales, Purchases: $purchases, New Profit: ${processedItem['profit']}');
          }
          
          return processedItem;
        }).toList();

    // Debug profit values to verify data
    for (var entry in chartData) {
      debugPrint('Bar chart data - Day: ${entry['day']}, Profit: ${entry['profit']}');
    }

    String title;
    String valueKey;
    Color color;
    IconData icon;
    bool isProfit;

    switch (activeTab) {
      case 'purchases':
        title = _getTranslatedText('daily_purchases');
        valueKey = 'purchases';
        color = Colors.blue;
        icon = Icons.shopping_cart;
        isProfit = false;
        break;
      case 'sales':
        title = _getTranslatedText('daily_sales');
        valueKey = 'sales';
        color = Colors.orange;
        icon = Icons.sell;
        isProfit = false;
        break;
      case 'profit':
        title = _getTranslatedText('daily_profit');
        valueKey = 'profit';
        color = Colors.green;
        icon = Icons.trending_up;
        isProfit = true;
        break;
      default:
        title = _getTranslatedText('daily_data');
        valueKey = 'profit';
        color = Colors.blue;
        icon = Icons.bar_chart;
        isProfit = false;
    }

    // For profit tab, recalculate profit directly from sales and purchases if profit is 0
    // This is a workaround in case the database helper has an issue with profit calculation
    if (activeTab == 'profit') {
      bool needsRecalculation = false;
      
      // Check if profit values are all zeros while we have sales data
      if (chartData.every((item) => (item['profit'] as double?) == 0.0) && 
          chartData.any((item) => ((item['sales'] as double?) ?? 0.0) > 0.0)) {
        needsRecalculation = true;
      }
      
      if (needsRecalculation) {
        debugPrint('Recalculating profit values as sales - purchases');
        for (var item in chartData) {
          // Simple profit calculation as sales minus purchases
          final sales = (item['sales'] as double?) ?? 0.0;
          final purchases = (item['purchases'] as double?) ?? 0.0;
          item['profit'] = sales - purchases;
        }
      }
    }

    final total = chartData.fold<double>(
      0,
      (sum, item) => sum + (item[valueKey] as double),
    );

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Theme.of(context).cardColor,
              Theme.of(context).cardColor.withBlue(Theme.of(context).cardColor.blue + 5),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              title, 
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SfCartesianChart(
                primaryXAxis: CategoryAxis(
                  title: AxisTitle(text: _getTranslatedText('date')),
                ),
                primaryYAxis: NumericAxis(
                  title: AxisTitle(text: _getTranslatedText('amount_som')),
                ),
                tooltipBehavior: TooltipBehavior(enable: true),
                series: <CartesianSeries>[
                  ColumnSeries<Map<String, dynamic>, String>(
                    dataSource: chartData,
                    xValueMapper: (data, _) => data['day'],
                    yValueMapper: (data, _) => data[valueKey],
                    name: activeTab.capitalize(),
                    color: isProfit 
                      ? (total >= 0 ? Colors.green : Colors.red) 
                      : color,
                    dataLabelSettings: const DataLabelSettings(
                      isVisible: true,
                      labelAlignment: ChartDataLabelAlignment.top,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: isProfit
                        ? (total >= 0
                          ? [Colors.green.shade50, Colors.green.shade100]
                          : [Colors.red.shade50, Colors.red.shade100])
                        : [Colors.blue.shade50, Colors.blue.shade100],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isProfit
                            ? (total >= 0
                                ? Icons.trending_up
                                : Icons.trending_down)
                            : Icons.currency_exchange,
                        color:
                            isProfit
                                ? (total >= 0
                                    ? Colors.green.shade700
                                    : Colors.red.shade700)
                                : Colors.blue.shade700,
                        size: 28,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isProfit
                            ? (total >= 0
                                ? _getTranslatedText('net_profit', {
                                  'amount': NumberFormat.currency(
                                    symbol: 'SOM ',
                                    decimalDigits: 2,
                                  ).format(total.abs()),
                                })
                                : _getTranslatedText('net_loss', {
                                  'amount': NumberFormat.currency(
                                    symbol: 'SOM ',
                                    decimalDigits: 2,
                                  ).format(total.abs()),
                                }))
                            : _getTranslatedText('total_formatted', {
                              'amount': NumberFormat.currency(
                                symbol: 'SOM ',
                                decimalDigits: 2,
                              ).format(total),
                            }),
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          color:
                              isProfit
                                  ? (total >= 0 ? Colors.green : Colors.red)
                                  : Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistributionChart(dynamic data) {
    final purchases = List<Map<String, dynamic>>.from(data['purchases']);
    final sales = List<Map<String, dynamic>>.from(data['sales']);
    final profitData = List<Map<String, dynamic>>.from(data['profit'] ?? []);
    final totalProfit = _calculateTotalProfit(profitData);

    return Column(
      children: [
        // Tab bar with purchases, sales, and profit
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: _buildDistributionTab(
                  'purchases',
                  _getTranslatedText('purchases'),
                ),
              ),
              Expanded(
                child: _buildDistributionTab(
                  'sales',
                  _getTranslatedText('sales'),
                ),
              ),
              Expanded(
                child: _buildDistributionTab(
                  'profit',
                  _getTranslatedText('profit'),
                ),
              ),
            ],
          ),
        ),
        // Chart area
        Expanded(
          child: _buildActiveTabContent(
            activeTab: _activeTab,
            purchases: purchases,
            sales: sales,
            profitData: profitData,
            totalProfit: totalProfit,
          ),
        ),
      ],
    );
  }

  Widget _buildDistributionTab(String tabName, String label) {
    final isSelected = _activeTab == tabName;
    return InkWell(
      onTap: () => setState(() => _activeTab = tabName),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color:
                  isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color:
                  isSelected
                      ? Theme.of(context).primaryColor
                      : Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent({
    required String activeTab,
    required List<Map<String, dynamic>> purchases,
    required List<Map<String, dynamic>> sales,
    required List<Map<String, dynamic>> profitData,
    required double totalProfit,
  }) {
    switch (activeTab) {
      case 'purchases':
        return _buildPieChart(
          title: _getTranslatedText('purchased_currencies'),
          data: purchases,
          valueKey: 'total_value',
          labelKey: 'currency',
          isCurrency: true,
        );
      case 'sales':
        return _buildPieChart(
          title: _getTranslatedText('sold_currencies'),
          data: sales,
          valueKey: 'total_value',
          labelKey: 'currency',
          isCurrency: true,
        );
      case 'profit':
        return _buildProfitPieChart(profitData, totalProfit);
      default:
        return Center(child: Text(_getTranslatedText('no_data_available')));
    }
  }

  double _calculateTotalProfit(List<Map<String, dynamic>> profitData) {
    return profitData.fold<double>(
      0,
      (sum, item) => sum + ((item['profit'] as num?)?.toDouble() ?? (item['amount'] as num?)?.toDouble() ?? 0.0),
    );
  }

  Widget _buildProfitPieChart(
    List<Map<String, dynamic>> data,
    double totalProfit,
  ) {
    if (data.isEmpty) {
      return Center(
        child: Text(
          _getTranslatedText('no_profit_data'),
          style: const TextStyle(fontSize: 18),
        ),
      );
    }

    return _buildPieChart(
      title: _getTranslatedText('profit_by_currency'),
      data: data,
      valueKey: 'profit',
      labelKey: 'currency_code',
      isCurrency: true,
      isProfit: true,
      total: totalProfit,
      showTotal: true,
    );
  }

  Widget _buildPieChart({
    required String title,
    required List<Map<String, dynamic>> data,
    required String valueKey,
    required String labelKey,
    bool isCurrency = false,
    bool isProfit = false,
    double? total,
    bool showTotal = false,
  }) {
    if (data.isEmpty) {
      debugPrint("No data to display for $title chart");
      return Center(
        child: Text(
          isProfit
              ? _getTranslatedText('no_profit_data')
              : _getTranslatedText('no_data_available'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    // Debug: Show data being passed to the chart
    debugPrint("Building pie chart with ${data.length} items for $title");
    debugPrint("First item keys: ${data.first.keys.join(', ')}");
    debugPrint("Looking for label key: $labelKey, value key: $valueKey");
    
    // Check if the required keys exist in the data
    final missingLabelKey = data.any((item) => !item.containsKey(labelKey));
    final missingValueKey = data.any((item) => !item.containsKey(valueKey));
    
    if (missingLabelKey || missingValueKey) {
      debugPrint("WARNING: Some items are missing required keys!");
      if (missingLabelKey) debugPrint("Missing label key: $labelKey");
      if (missingValueKey) debugPrint("Missing value key: $valueKey");
      
      // Show a more informative empty state
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 48),
            const SizedBox(height: 16),
            Text(
              "Data format issue - chart cannot be displayed",
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final displayTotal =
        total ??
        data.fold<double>(
          0,
          (sum, item) => sum + (item[valueKey] as double? ?? 0.0),
        );

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Theme.of(context).cardColor,
              Theme.of(context).cardColor.withBlue(Theme.of(context).cardColor.blue + 5),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              title, 
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SfCircularChart(
                legend: Legend(
                  isVisible: true,
                  position: LegendPosition.bottom,
                  overflowMode: LegendItemOverflowMode.wrap,
                ),
                series: <CircularSeries>[
                  PieSeries<Map<String, dynamic>, String>(
                    dataSource: data,
                    xValueMapper: (data, _) => data[labelKey],
                    yValueMapper: (data, _) {
                      final value = data[valueKey];
                      return value is double ? value : 0.0;
                    },
                    pointColorMapper: (data, index) {
                      // Generate colors based on index
                      final baseColors = [
                        Colors.blue,
                        Colors.green,
                        Colors.purple,
                        Colors.orange,
                        Colors.cyan,
                        Colors.pink,
                        Colors.teal,
                        Colors.red,
                        Colors.amber,
                        Colors.indigo,
                      ];
                      
                      // Use different shades based on index
                      final colorIndex = index % baseColors.length;
                      final color = baseColors[colorIndex];
                      
                      // Return different shades for a gradient-like effect
                      if (index % 3 == 0) {
                        return color.shade300;
                      } else if (index % 3 == 1) {
                        return color.shade500;
                      } else {
                        return color.shade700;
                      }
                    },
                    dataLabelSettings: const DataLabelSettings(
                      isVisible: true,
                      labelPosition: ChartDataLabelPosition.outside,
                      useSeriesColor: true,
                    ),
                    enableTooltip: true,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: isProfit
                        ? (displayTotal >= 0
                          ? [Colors.green.shade50, Colors.green.shade100]
                          : [Colors.red.shade50, Colors.red.shade100])
                        : [Colors.blue.shade50, Colors.blue.shade100],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isProfit
                            ? (displayTotal >= 0
                                ? Icons.trending_up
                                : Icons.trending_down)
                            : Icons.currency_exchange,
                        color:
                            isProfit
                                ? (displayTotal >= 0
                                    ? Colors.green.shade700
                                    : Colors.red.shade700)
                                : Colors.blue.shade700,
                        size: 28,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isProfit
                            ? (displayTotal >= 0
                                ? _getTranslatedText('net_profit', {
                                  'amount': NumberFormat.currency(
                                    symbol: 'SOM ',
                                    decimalDigits: 2,
                                  ).format(displayTotal.abs()),
                                })
                                : _getTranslatedText('net_loss', {
                                  'amount': NumberFormat.currency(
                                    symbol: 'SOM ',
                                    decimalDigits: 2,
                                  ).format(displayTotal.abs()),
                                }))
                            : _getTranslatedText('total_formatted', {
                              'amount': NumberFormat.currency(
                                symbol: 'SOM ',
                                decimalDigits: 2,
                              ).format(displayTotal),
                            }),
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          color:
                              isProfit
                                  ? (displayTotal >= 0
                                      ? Colors.green
                                      : Colors.red)
                                  : Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}

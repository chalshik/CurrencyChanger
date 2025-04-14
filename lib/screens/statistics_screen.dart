import 'package:flutter/material.dart';
import '../db_helper.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> with SingleTickerProviderStateMixin {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _currencyStats = [];
  double _totalProfit = 0.0;
  double _somBalance = 0.0;
  double _kassaValue = 0.0;
  bool _isLoading = false;
  late TabController _tabController;
  DateTime _startDate = DateTime.now().subtract(Duration(days: 7));
  DateTime _endDate = DateTime.now();

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
    _loadCurrencyStats();
    _tabController = TabController(length: 4, vsync: this);
  }

  Future<void> _loadCurrencyStats() async {
    if (!mounted || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      final analytics = await _dbHelper.calculateAnalytics(
        startDate: null,
        endDate: null,
      );

      if (!mounted) return;

      double somBalance = 0.0;
      double kassaValue = 0.0;

      if (analytics.containsKey('currency_stats')) {
        final stats = analytics['currency_stats'] as List<dynamic>;

        final currencyStats =
            stats
                .where(
                  (item) =>
                      item is Map<String, dynamic> &&
                      item.containsKey('currency'),
                )
                .map((item) => item as Map<String, dynamic>)
                .toList();

        for (var stat in currencyStats) {
          if (stat['currency'] == 'SOM') {
            somBalance = stat['current_quantity'] as double? ?? 0.0;
          } else {
            final avgPurchaseRate = stat['avg_purchase_rate'] as double? ?? 0.0;
            final totalPurchased = stat['total_purchased'] as double? ?? 0.0;
            kassaValue += avgPurchaseRate * totalPurchased;
          }
        }

        setState(() {
          _currencyStats = currencyStats;
          _totalProfit = analytics['total_profit'] as double? ?? 0.0;
          _somBalance = somBalance;
          _kassaValue = kassaValue;
          _isLoading = false;
        });
      } else {
        setState(() {
          _currencyStats = [];
          _isLoading = false;
        });
      }
      
      // Debug print to check data
      debugPrint('Loaded ${_currencyStats.length} currency stats');
      if (_currencyStats.isNotEmpty) {
        debugPrint('First currency: ${_currencyStats.first['currency']}');
      }
    } catch (e) {
      debugPrint('Error loading statistics: $e');
      if (!mounted) return;

      setState(() {
        _currencyStats = [];
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading statistics: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildSummaryCards(bool isTablet) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isDarkMode ? Colors.blue.shade900.withOpacity(0.7) : Colors.blue.shade50.withOpacity(0.8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _getTranslatedText('som_balance'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700.withOpacity(0.9),
                  ),
                ),
                Text(
                  '${_somBalance.toStringAsFixed(2)} SOM',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ),
        InkWell(
          onTap: () => _showForeignCurrencyValueDetails(),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDarkMode ? Colors.green.shade900.withOpacity(0.7) : Colors.green.shade50.withOpacity(0.8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _getTranslatedText('foreign_currency_value'),
                    style: TextStyle(
                      fontSize: 16,
                          fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.green.shade300 : Colors.green.shade700.withOpacity(0.9),
                    ),
                  ),
                  Text(
                    '${_kassaValue.toStringAsFixed(2)} SOM',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.green.shade300 : Colors.green.shade700.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isDarkMode ? Colors.indigo.shade900.withOpacity(0.8) : Colors.indigo.shade50.withOpacity(0.8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _getTranslatedText('total_profit'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.indigo.shade300 : Colors.indigo.shade700.withOpacity(0.9),
                  ),
                ),
                Text(
                  '${formatProfit(_totalProfit)} SOM',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _totalProfit >= 0 
                        ? (isDarkMode ? Colors.cyan.shade300 : Colors.cyan.shade700)
                        : (isDarkMode ? Colors.pink.shade300 : Colors.pink.shade700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, {Color? valueColor}) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor ?? (isDarkMode ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  String formatProfit(double value) {
    if (value > -0.005 && value < 0.005) return "0.00";
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width >= 600;
    final isLandscape = screenSize.width > screenSize.height;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadCurrencyStats,
        child:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24, top: 16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      isLandscape
                          ? _buildLandscapeSummaryCards() // Horizontal cards for landscape mode
                          : _buildSummaryCards(
                            isTablet,
                          ), // Vertical cards for portrait mode
                      // Always use table view with horizontal scrolling for small screens
                      _buildScrollableTable(isTablet),

                      // Profit Pie Chart Section
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                        child: Text(
                          _getTranslatedText('profit_distribution'),
                          style: TextStyle(
                            fontSize: isTablet ? 20 : 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700.withOpacity(0.9),
                          ),
                        ),
                      ),
                      _buildProfitPieChart(),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _buildScrollableTable(bool isTablet) {
    // Get currencies excluding SOM
    final currenciesToDisplay = _currencyStats.where((stat) => stat['currency'] != 'SOM').toList();
    
    // Return a message if no data is available
    if (currenciesToDisplay.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            _getTranslatedText('no_data'),
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          // Set width based on device, but always ensure there's space for the table
          width: isTablet ? MediaQuery.of(context).size.width - 32 : 800,
          child: _buildCurrencyTable(currenciesToDisplay),
        ),
      ),
    );
  }

  Widget _buildCurrencyTable(List<Map<String, dynamic>> currenciesToDisplay) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (currenciesToDisplay.isEmpty) {
      return Center(
          child: Text(
            _getTranslatedText('no_data'),
            style: TextStyle(color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600),
        ),
      );
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table Header
          Container(
            decoration: BoxDecoration(
              color: isDarkMode 
                ? Colors.blue.shade900.withOpacity(1.0)
                : Colors.blue.shade800.withOpacity(1.0),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              children: [
                _buildTableHeaderCell(
                  _getTranslatedText('currency_code_header'),
                  flex: 1,
                ),
                _buildTableHeaderCell(
                  _getTranslatedText('current_balance'),
                  flex: 2,
                ),
                _buildTableHeaderCell(
                  _getTranslatedText('avg_purchase_rate'),
                  flex: 2,
                ),
                _buildTableHeaderCell(
                  _getTranslatedText('total_purchased'),
                  flex: 2,
                ),
                _buildTableHeaderCell(
                  _getTranslatedText('avg_sale_rate'),
                  flex: 2,
                ),
                _buildTableHeaderCell(
                  _getTranslatedText('total_sold'),
                  flex: 2,
                ),
                _buildTableHeaderCell(_getTranslatedText('profit'), flex: 1),
              ],
            ),
          ),
          // Table Body
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
              color: isDarkMode ? Colors.grey.shade900 : Colors.white,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: currenciesToDisplay.length,
              separatorBuilder:
                  (context, index) =>
                      Divider(height: 1, color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300),
              itemBuilder: (context, index) {
                final stat = currenciesToDisplay[index];
                final avgPurchaseRate =
                    stat['avg_purchase_rate'] as double? ?? 0.0;
                final avgSaleRate = stat['avg_sale_rate'] as double? ?? 0.0;
                final totalPurchased =
                    stat['total_purchased'] as double? ?? 0.0;
                final totalSold = stat['total_sold'] as double? ?? 0.0;
                final currentQuantity =
                    stat['current_quantity'] as double? ?? 0.0;
                final profit = stat['profit'] as double? ?? 0.0;

                return InkWell(
                  onTap: () {
                    // Show detailed stats for this currency on tap
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder:
                          (context) => DraggableScrollableSheet(
                            initialChildSize: 0.6,
                            maxChildSize: 0.9,
                            minChildSize: 0.4,
                            builder:
                                (_, controller) => Container(
                                  decoration: BoxDecoration(
                                    color: isDarkMode ? Colors.grey.shade900 : Colors.white,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(20),
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  child: ListView(
                                    controller: controller,
                                    children: [
                                      Text(
                                        '${stat['currency']} ${_getTranslatedText('statistics')}',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: isDarkMode ? Colors.white : Colors.black,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _getTranslatedText('current_balance'),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _buildStatRow(
                                        _getTranslatedText('amount_label'),
                                        '${currentQuantity.toStringAsFixed(2)} ${stat['currency']}',
                                      ),
                                      Divider(height: 24, color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300),
                                      Text(
                                        _getTranslatedText('purchase_info'),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _buildStatRow(
                                        _getTranslatedText('total_purchased'),
                                        '${totalPurchased.toStringAsFixed(2)} ${stat['currency']}',
                                      ),
                                      _buildStatRow(
                                        _getTranslatedText('avg_purchase_rate'),
                                        avgPurchaseRate.toStringAsFixed(4),
                                      ),
                                      _buildStatRow(
                                        _getTranslatedText('total_spent'),
                                        '${(avgPurchaseRate * totalPurchased).toStringAsFixed(2)} SOM',
                                      ),
                                      Divider(height: 24, color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300),
                                      Text(
                                        _getTranslatedText('sale_info'),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _buildStatRow(
                                        _getTranslatedText('total_sold'),
                                        '${totalSold.toStringAsFixed(2)} ${stat['currency']}',
                                      ),
                                      _buildStatRow(
                                        _getTranslatedText('avg_sale_rate'),
                                        avgSaleRate.toStringAsFixed(4),
                                      ),
                                      _buildStatRow(
                                        _getTranslatedText('total_earned'),
                                        '${(avgSaleRate * totalSold).toStringAsFixed(2)} SOM',
                                      ),
                                      Divider(height: 24, color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300),
                                      Text(
                                        _getTranslatedText('profit'),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              profit >= 0
                                                  ? (isDarkMode ? Colors.green.shade300 : Colors.green.shade700)
                                                  : (isDarkMode ? Colors.red.shade300 : Colors.red.shade700),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _buildStatRow(
                                        _getTranslatedText('amount_label'),
                                        formatProfit(profit),
                                        valueColor:
                                            profit >= 0
                                                ? (isDarkMode ? Colors.green.shade300 : Colors.green.shade700)
                                                : (isDarkMode ? Colors.red.shade300 : Colors.red.shade700),
                                      ),
                                    ],
                                  ),
                                ),
                          ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                    color: isDarkMode 
                        ? (index % 2 == 0 ? Colors.grey.shade800 : Colors.grey.shade900)
                        : (index % 2 == 0 ? Colors.grey.shade50 : Colors.white),
                    child: Row(
                      children: [
                        _buildTableCell(
                          stat['currency'].toString(),
                          bold: true,
                          color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700,
                          flex: 1,
                        ),
                        _buildTableCell(
                          '${currentQuantity.toStringAsFixed(2)}',
                          flex: 2,
                          textColor: isDarkMode ? Colors.white : null,
                        ),
                        _buildTableCell(
                          avgPurchaseRate.toStringAsFixed(4),
                          flex: 2,
                          textColor: isDarkMode ? Colors.white : null,
                        ),
                        _buildTableCell(
                          '${totalPurchased.toStringAsFixed(2)}',
                          flex: 2,
                          textColor: isDarkMode ? Colors.white : null,
                        ),
                        _buildTableCell(
                          avgSaleRate.toStringAsFixed(4),
                          flex: 2,
                          textColor: isDarkMode ? Colors.white : null,
                        ),
                        _buildTableCell(
                          '${totalSold.toStringAsFixed(2)}',
                          flex: 2,
                          textColor: isDarkMode ? Colors.white : null,
                        ),
                        _buildTableCell(
                          formatProfit(profit),
                          bold: true,
                          color:
                              profit >= 0
                                  ? (isDarkMode ? Colors.green.shade300 : Colors.green.shade700)
                                  : (isDarkMode ? Colors.red.shade300 : Colors.red.shade700),
                          flex: 1,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Table Footer with totals
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.blue.shade900.withOpacity(0.3) : Colors.blue.shade50,
              border: Border(
                left: BorderSide(color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300),
                right: BorderSide(color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300),
                bottom: BorderSide(color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300),
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                _buildTableCell(
                  _getTranslatedText('total'),
                  bold: true,
                  flex: 1,
                  textColor: isDarkMode ? Colors.white : null,
                ),
                _buildTableCell(
                _calculateTotal(currenciesToDisplay, 'current_quantity').toStringAsFixed(2),
                  bold: true,
                  flex: 2,
                  textColor: isDarkMode ? Colors.white : null,
                ),
                _buildTableCell(
                  "-", // Avg purchase rate doesn't have a meaningful total
                  bold: true,
                  flex: 2,
                  textColor: isDarkMode ? Colors.white : null,
                ),
                _buildTableCell(
                _calculateTotal(currenciesToDisplay, 'total_purchased').toStringAsFixed(2),
                  bold: true,
                  flex: 2,
                  textColor: isDarkMode ? Colors.white : null,
                ),
                _buildTableCell(
                  "-", // Avg sale rate doesn't have a meaningful total
                  bold: true,
                  flex: 2,
                  textColor: isDarkMode ? Colors.white : null,
                ),
                _buildTableCell(
                _calculateTotal(currenciesToDisplay, 'total_sold').toStringAsFixed(2),
                  bold: true,
                  flex: 2,
                  textColor: isDarkMode ? Colors.white : null,
                ),
                _buildTableCell(
                formatProfit(_calculateTotal(currenciesToDisplay, 'profit')),
                  bold: true,
                  color:
                    _calculateTotal(currenciesToDisplay, 'profit') >= 0
                          ? (isDarkMode ? Colors.green.shade300 : Colors.green.shade700)
                          : (isDarkMode ? Colors.red.shade300 : Colors.red.shade700),
                  flex: 1,
                ),
              ],
            ),
          ),
        ],
    );
  }

  Widget _buildTableHeaderCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTableCell(
    String text, {
    bool bold = false,
    Color? color,
    Color? textColor,
    int flex = 1,
  }) {
    if (text == "-0.00") text = "0.00";
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: color ?? textColor,
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  double _calculateTotal(List<Map<String, dynamic>> stats, String field) {
    return stats.fold(0.0, (sum, stat) => sum + (stat[field] as double? ?? 0.0));
  }

  Widget _buildLandscapeSummaryCards() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Row(
      children: [
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(8),
            color: isDarkMode ? Colors.blue.shade900.withOpacity(0.7) : Colors.blue.shade50.withOpacity(0.8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _getTranslatedText('som_balance'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700.withOpacity(0.9),
                    ),
                  ),
                  Text(
                    '${_somBalance.toStringAsFixed(2)} SOM',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: () => _showForeignCurrencyValueDetails(),
            child: Card(
              margin: const EdgeInsets.all(8),
              color: isDarkMode ? Colors.green.shade900.withOpacity(0.7) : Colors.green.shade50.withOpacity(0.8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          _getTranslatedText('foreign_currency_value'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.green.shade300 : Colors.green.shade700.withOpacity(0.9),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.info_outline,
                          color: isDarkMode ? Colors.green.shade300 : Colors.green.shade700.withOpacity(0.9),
                          size: 20,
                        ),
                      ],
                    ),
                    Text(
                      '${_kassaValue.toStringAsFixed(2)} SOM',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.green.shade300 : Colors.green.shade700.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(8),
            color: isDarkMode ? Colors.indigo.shade900.withOpacity(0.8) : Colors.indigo.shade50.withOpacity(0.8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _getTranslatedText('total_profit'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.indigo.shade300 : Colors.indigo.shade700.withOpacity(0.9),
                    ),
                  ),
                  Text(
                    '${formatProfit(_totalProfit)} SOM',
                    style: TextStyle(
                      fontSize: 16, 
                      fontWeight: FontWeight.bold,
                      color: _totalProfit >= 0 
                          ? (isDarkMode ? Colors.cyan.shade300 : Colors.cyan.shade700)
                          : (isDarkMode ? Colors.pink.shade300 : Colors.pink.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showForeignCurrencyValueDetails() {
    // Get currencies excluding SOM, with non-zero purchased amount
    final currencies = _currencyStats.where((stat) => 
      stat['currency'] != 'SOM' && 
      (stat['total_purchased'] as double? ?? 0.0) > 0
    ).toList();
    
    if (currencies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_getTranslatedText('no_data')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _getTranslatedText('foreign_currency_value_breakdown'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Table headers
              Container(
                decoration: BoxDecoration(
                  color: Colors.green.shade700.withOpacity(0.9),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Row(
                  children: [
                    _buildTableHeaderCell(
                      _getTranslatedText('currency_code_header'),
                      flex: 1,
                    ),
                    _buildTableHeaderCell(
                      _getTranslatedText('total_purchased'),
                      flex: 2,
                    ),
                    _buildTableHeaderCell(
                      _getTranslatedText('avg_purchase_rate'),
                      flex: 2,
                    ),
                    _buildTableHeaderCell(
                      _getTranslatedText('total_value'),
                      flex: 2,
                    ),
                  ],
                ),
              ),
              // Table body
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ListView.separated(
                    controller: controller,
                    shrinkWrap: true,
                    itemCount: currencies.length,
                    separatorBuilder: (context, index) => 
                      Divider(height: 1, color: Colors.grey.shade300),
                    itemBuilder: (context, index) {
                      final currency = currencies[index];
                      final code = currency['currency'] as String;
                      final totalPurchased = currency['total_purchased'] as double? ?? 0.0;
                      final avgPurchaseRate = currency['avg_purchase_rate'] as double? ?? 0.0;
                      final totalValue = totalPurchased * avgPurchaseRate;
                      
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12, 
                          horizontal: 8,
                        ),
                        color: index % 2 == 0 ? Colors.grey.shade50 : Colors.white,
                        child: Row(
                          children: [
                            _buildTableCell(
                              code,
                              bold: true,
                              color: Colors.green.shade700,
                              flex: 1,
                            ),
                            _buildTableCell(
                              totalPurchased.toStringAsFixed(2),
                              flex: 2,
                            ),
                            _buildTableCell(
                              avgPurchaseRate.toStringAsFixed(4),
                              flex: 2,
                            ),
                            _buildTableCell(
                              totalValue.toStringAsFixed(2),
                              bold: true,
                              flex: 2,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Table footer with total
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border(
                    left: BorderSide(color: Colors.grey.shade300),
                    right: BorderSide(color: Colors.grey.shade300),
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Row(
                  children: [
                    _buildTableCell(
                      _getTranslatedText('total'),
                      bold: true,
                      flex: 1,
                    ),
                    _buildTableCell(
                      _calculateTotal(currencies, 'total_purchased').toStringAsFixed(2),
                      bold: true,
                      flex: 2,
                    ),
                    _buildTableCell(
                      "-", // Average doesn't have a meaningful total
                      bold: true,
                      flex: 2,
                    ),
                    _buildTableCell(
                      _kassaValue.toStringAsFixed(2),
                      bold: true,
                      color: Colors.green.shade700,
                      flex: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfitPieChart() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Get currencies excluding SOM, with non-zero profit
    final currenciesWithProfit = _currencyStats
        .where((stat) => 
            stat['currency'] != 'SOM' && 
            ((stat['profit'] as double? ?? 0.0).abs() > 0.01)) // Only include if profit is not near-zero
        .toList();
    
    if (currenciesWithProfit.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            _getTranslatedText('no_profit_data'),
            style: TextStyle(color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600),
          ),
        ),
      );
    }

    // Sort by profit value (absolute) for better visualization
    currenciesWithProfit.sort((a, b) => 
        (b['profit'] as double).abs().compareTo((a['profit'] as double).abs()));
    
    // Calculate total profit (positive and negative)
    final totalPositiveProfit = currenciesWithProfit
        .where((c) => (c['profit'] as double) > 0)
        .fold<double>(0, (sum, c) => sum + (c['profit'] as double));
        
    final totalNegativeProfit = currenciesWithProfit
        .where((c) => (c['profit'] as double) < 0)
        .fold<double>(0, (sum, c) => sum + (c['profit'] as double));
    
    final totalProfitText = totalPositiveProfit + totalNegativeProfit;
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SizedBox(
            height: 350, // Increased height for better visualization
            child: SfCircularChart(
              margin: const EdgeInsets.all(10),
              legend: Legend(
                isVisible: true,
                position: LegendPosition.bottom,
                overflowMode: LegendItemOverflowMode.wrap,
                textStyle: TextStyle(
                  fontSize: 12,
                  color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700,
                ),
              ),
              annotations: <CircularChartAnnotation>[
                CircularChartAnnotation(
                  widget: Container(
                    child: Text(
                      '${totalProfitText.toStringAsFixed(2)}\nSOM',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: totalProfitText >= 0 
                          ? (isDarkMode ? Colors.cyan.shade300 : Colors.green.shade800)
                          : (isDarkMode ? Colors.pink.shade300 : Colors.red.shade800),
                        fontWeight: FontWeight.bold,
                        fontSize: 16, // Increased font size
                      ),
                    ),
                  ),
                ),
              ],
              series: <CircularSeries>[
                DoughnutSeries<Map<String, dynamic>, String>(
                  dataSource: currenciesWithProfit,
                  xValueMapper: (data, _) => data['currency'] as String,
                  yValueMapper: (data, _) => (data['profit'] as double).abs(),
                  pointColorMapper: (data, index) {
                    final profit = data['profit'] as double;
                    final hue = 120 + (index * 50) % 240;
                    return profit >= 0 
                      ? (isDarkMode
                          ? HSLColor.fromAHSL(1.0, hue.toDouble(), 0.8, 0.3).toColor()
                          : HSLColor.fromAHSL(1.0, hue.toDouble(), 0.7, 0.5).toColor())
                      : (isDarkMode
                          ? HSLColor.fromAHSL(1.0, 0.0, 0.8, 0.3).toColor()
                          : HSLColor.fromAHSL(1.0, 0.0, 0.7, 0.5).toColor());
                  },
                  dataLabelSettings: DataLabelSettings(
                    isVisible: true,
                    labelPosition: ChartDataLabelPosition.outside,
                    connectorLineSettings: const ConnectorLineSettings(
                      type: ConnectorType.line,
                      length: '15%', // Longer connector lines
                    ),
                    labelIntersectAction: LabelIntersectAction.shift,
                    textStyle: TextStyle(
                      fontSize: 13, // Increased font size
                      fontWeight: FontWeight.w500,
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                    useSeriesColor: true,
                    builder: (data, point, series, pointIndex, seriesIndex) {
                      // Custom builder to show value along with currency code
                      final currencyData = data as Map<String, dynamic>;
                      final currencyCode = currencyData['currency'] as String;
                      final profit = currencyData['profit'] as double;
                      return Container(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          '$currencyCode: ${profit.abs().toStringAsFixed(2)}',
                          style: TextStyle(
                            color: isDarkMode ? Colors.white : Colors.black,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                  enableTooltip: true,
                  innerRadius: '60%',
                  radius: '85%', // Slightly smaller to leave more room for labels
                ),
              ],
              tooltipBehavior: TooltipBehavior(
                enable: true,
                format: 'point.x: point.y SOM',
                color: isDarkMode ? Colors.grey.shade800 : Colors.white,
                textStyle: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
            ),
          ),
          
          // Add extra spacing between pie chart and legend
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Soften TabBar colors
  Widget _buildTabBar() {
    return Container(
      color: Colors.blue.shade50.withOpacity(0.8),
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.blue.shade700.withOpacity(0.9),
        unselectedLabelColor: Colors.grey.shade600,
        indicatorColor: Colors.blue.shade400.withOpacity(0.9),
        tabs: [
          Tab(text: _getTranslatedText('summary')),
          Tab(text: _getTranslatedText('transactions')),
          Tab(text: _getTranslatedText('currencies')),
          Tab(text: _getTranslatedText('profit_details')),
        ],
      ),
    );
  }

  // Soften date picker button
  Widget _buildDatePicker() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () => _showDateRangePicker(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade100.withOpacity(0.8),
              foregroundColor: Colors.blue.shade700.withOpacity(0.9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '${DateFormat('dd/MM/yyyy').format(_startDate)} - ${DateFormat('dd/MM/yyyy').format(_endDate)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700.withOpacity(0.9),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Add this method to handle date range picking
  void _showDateRangePicker() {
    // Implement date range picker logic
    showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    ).then((dateRange) {
      if (dateRange != null) {
        setState(() {
          _startDate = dateRange.start;
          _endDate = dateRange.end;
          // Refresh data with new date range
          _loadCurrencyStats();
        });
      }
    });
  }
}

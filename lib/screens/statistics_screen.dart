import 'package:flutter/material.dart';
import '../db_helper.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _currencyStats = [];
  double _totalProfit = 0.0;
  double _somBalance = 0.0;
  double _kassaValue = 0.0;
  bool _isLoading = false;

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
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getTranslatedText('som_balance'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                _buildStatRow(
                  _getTranslatedText('amount_label'),
                  '${_somBalance.toStringAsFixed(2)} SOM',
                  valueColor: Colors.blue,
                ),
              ],
            ),
          ),
        ),
        InkWell(
          onTap: () => _showForeignCurrencyValueDetails(),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _getTranslatedText('foreign_currency_value'),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      Icon(
                        Icons.info_outline,
                        color: Colors.green.shade700,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildStatRow(
                    _getTranslatedText('total_value'),
                    '${_kassaValue.toStringAsFixed(2)} SOM',
                    valueColor: Colors.green,
                  ),
                ],
              ),
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getTranslatedText('total_profit'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                const SizedBox(height: 8),
                _buildStatRow(
                  _getTranslatedText('amount_label'),
                  '${formatProfit(_totalProfit)} SOM',
                  valueColor: _totalProfit >= 0 ? Colors.green : Colors.red,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor,
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
    if (currenciesToDisplay.isEmpty) {
      return Center(
        child: Text(
          _getTranslatedText('no_data'),
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Table Header
        Container(
          decoration: BoxDecoration(
            color: Colors.blue.shade700,
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
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: currenciesToDisplay.length,
            separatorBuilder:
                (context, index) =>
                    Divider(height: 1, color: Colors.grey.shade300),
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
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(20),
                                  ),
                                ),
                                padding: const EdgeInsets.all(16),
                                child: ListView(
                                  controller: controller,
                                  children: [
                                    Text(
                                      '${stat['currency']} ${_getTranslatedText('statistics')}',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _getTranslatedText('current_balance'),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildStatRow(
                                      _getTranslatedText('amount_label'),
                                      '${currentQuantity.toStringAsFixed(2)} ${stat['currency']}',
                                    ),
                                    const Divider(height: 24),
                                    Text(
                                      _getTranslatedText('purchase_info'),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade700,
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
                                    const Divider(height: 24),
                                    Text(
                                      _getTranslatedText('sale_info'),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade700,
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
                                    const Divider(height: 24),
                                    Text(
                                      _getTranslatedText('profit'),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            profit >= 0
                                                ? Colors.green.shade700
                                                : Colors.red.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildStatRow(
                                      _getTranslatedText('amount_label'),
                                      formatProfit(profit),
                                      valueColor:
                                          profit >= 0
                                              ? Colors.green.shade700
                                              : Colors.red.shade700,
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
                  color: index % 2 == 0 ? Colors.grey.shade50 : Colors.white,
                  child: Row(
                    children: [
                      _buildTableCell(
                        stat['currency'].toString(),
                        bold: true,
                        color: Colors.blue.shade700,
                        flex: 1,
                      ),
                      _buildTableCell(
                        '${currentQuantity.toStringAsFixed(2)}',
                        flex: 2,
                      ),
                      _buildTableCell(
                        avgPurchaseRate.toStringAsFixed(4),
                        flex: 2,
                      ),
                      _buildTableCell(
                        '${totalPurchased.toStringAsFixed(2)}',
                        flex: 2,
                      ),
                      _buildTableCell(
                        avgSaleRate.toStringAsFixed(4),
                        flex: 2,
                      ),
                      _buildTableCell(
                        '${totalSold.toStringAsFixed(2)}',
                        flex: 2,
                      ),
                      _buildTableCell(
                        formatProfit(profit),
                        bold: true,
                        color:
                            profit >= 0
                                ? Colors.green.shade700
                                : Colors.red.shade700,
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
            color: Colors.blue.shade50,
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
                _calculateTotal(currenciesToDisplay, 'current_quantity').toStringAsFixed(2),
                bold: true,
                flex: 2,
              ),
              _buildTableCell(
                "-", // Avg purchase rate doesn't have a meaningful total
                bold: true,
                flex: 2,
              ),
              _buildTableCell(
                _calculateTotal(currenciesToDisplay, 'total_purchased').toStringAsFixed(2),
                bold: true,
                flex: 2,
              ),
              _buildTableCell(
                "-", // Avg sale rate doesn't have a meaningful total
                bold: true,
                flex: 2,
              ),
              _buildTableCell(
                _calculateTotal(currenciesToDisplay, 'total_sold').toStringAsFixed(2),
                bold: true,
                flex: 2,
              ),
              _buildTableCell(
                formatProfit(_calculateTotal(currenciesToDisplay, 'profit')),
                bold: true,
                color:
                    _calculateTotal(currenciesToDisplay, 'profit') >= 0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
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
    int flex = 1,
  }) {
    if (text == "-0.00") text = "0.00";
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: color,
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
    return Row(
      children: [
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(8),
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getTranslatedText('som_balance'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildStatRow(
                    _getTranslatedText('amount_label'),
                    '${_somBalance.toStringAsFixed(2)} SOM',
                    valueColor: Colors.blue,
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
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _getTranslatedText('foreign_currency_value'),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        Icon(
                          Icons.info_outline,
                          color: Colors.green.shade700,
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildStatRow(
                      _getTranslatedText('total_value'),
                      '${_kassaValue.toStringAsFixed(2)} SOM',
                      valueColor: Colors.green,
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
            color: Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getTranslatedText('total_profit'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildStatRow(
                    _getTranslatedText('amount_label'),
                    '${formatProfit(_totalProfit)} SOM',
                    valueColor: _totalProfit >= 0 ? Colors.green : Colors.red,
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
                  color: Colors.green.shade700,
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
}

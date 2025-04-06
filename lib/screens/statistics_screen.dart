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

  // Date range filter variables
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();

  // Currency filter variables
  Set<String> _selectedCurrencies = {}; // Track selected currency codes

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
    // Set default date to today
    final today = DateTime.now();
    _startDate = DateTime(today.year, today.month, today.day);
    _endDate = DateTime(today.year, today.month, today.day, 23, 59, 59);
    _startDateController.text = _formatDate(_startDate!);
    _endDateController.text = _formatDate(_endDate!);
    _loadCurrencyStats();
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          isStartDate
              ? _startDate ?? DateTime.now()
              : _endDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = DateTime(picked.year, picked.month, picked.day);
          _startDateController.text = _formatDate(picked);
        } else {
          _endDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            23,
            59,
            59,
          );
          _endDateController.text = _formatDate(picked);
        }
      });
      _loadCurrencyStats();
    }
  }

  void _clearDateFilters() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _startDateController.clear();
      _endDateController.clear();
    });
    _loadCurrencyStats();
  }

  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year.toString().substring(2, 4)}";
  }

  Future<void> _loadCurrencyStats() async {
    if (!mounted || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      final analytics = await _dbHelper.calculateAnalytics(
        startDate: _startDate,
        endDate: _endDate,
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

  Widget _buildDateFilterRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _startDateController,
              decoration: InputDecoration(
                labelText: _getTranslatedText('from'),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today, size: 20),
                  onPressed: () => _selectDate(context, true),
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              readOnly: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _endDateController,
              decoration: InputDecoration(
                labelText: _getTranslatedText('to'),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today, size: 20),
                  onPressed: () => _selectDate(context, false),
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              readOnly: true,
            ),
          ),
          if (_startDate != null || _endDate != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearDateFilters,
              tooltip: _getTranslatedText('reset_filters'),
            ),
        ],
      ),
    );
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _getTranslatedText('statistics_and_balance'),
                              style: TextStyle(
                                fontSize: isTablet ? 24 : 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: _loadCurrencyStats,
                              tooltip: _getTranslatedText('refresh_statistics'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDateFilterRow(),
                      isLandscape
                          ? _buildLandscapeSummaryCards() // Horizontal cards for landscape mode
                          : _buildSummaryCards(
                            isTablet,
                          ), // Vertical cards for portrait mode
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          _getTranslatedText('currency_statistics'),
                          style: TextStyle(
                            fontSize: isTablet ? 20 : 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                      _buildCurrencyFilterButtons(), // Now visible in all modes
                      isTablet
                          ? _buildCurrencyTable()
                          : _buildCurrencyCardsList(),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _buildCurrencyFilterButtons() {
    // Get unique currency codes (excluding SOM)
    final currencyCodes =
        _currencyStats
            .where((stat) => stat['currency'] != 'SOM')
            .map((stat) => stat['currency'].toString())
            .toSet()
            .toList();

    if (currencyCodes.isEmpty) {
      return const SizedBox.shrink(); // No currencies to filter
    }

    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 400;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Show headers
          Text(
            _getTranslatedText('filter_history'),
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade700,
            ),
          ),
          const SizedBox(height: 8),
          // Scrollable row of currency filter chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // All filter option
              FilterChip(
                label: Text(_getTranslatedText('all_filters')),
                selected: _selectedCurrencies.isEmpty,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedCurrencies.clear();
                    });
                  }
                },
                backgroundColor: Colors.grey.shade100,
                selectedColor: Colors.blue.shade100,
                checkmarkColor: Colors.blue.shade800,
              ),
              // Filter chips for each currency
              ...currencyCodes.map((code) {
                return FilterChip(
                  label: Text(code),
                  selected: _selectedCurrencies.contains(code),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedCurrencies.add(code);
                      } else {
                        _selectedCurrencies.remove(code);
                      }
                    });
                  },
                  backgroundColor: Colors.grey.shade100,
                  selectedColor: Colors.blue.shade100,
                  checkmarkColor: Colors.blue.shade800,
                );
              }).toList(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurrencyTable() {
    // Apply currency filter if any currencies are selected
    final currenciesToDisplay =
        _currencyStats
            .where(
              (stat) =>
                  stat['currency'] != 'SOM' &&
                  (_selectedCurrencies.isEmpty ||
                      _selectedCurrencies.contains(stat['currency'])),
            )
            .toList();

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
      child: Column(
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
                
                // Ensure we have profit data
                var profit = stat['profit'] as double? ?? 0.0;
                
                // Debug the profit value
                debugPrint('Currency: ${stat['currency']}, Profit: $profit');

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
                  _calculateTotal('current_quantity').toStringAsFixed(2),
                  bold: true,
                  flex: 2,
                ),
                _buildTableCell(
                  "-", // Avg purchase rate doesn't have a meaningful total
                  bold: true,
                  flex: 2,
                ),
                _buildTableCell(
                  _calculateTotal('total_purchased').toStringAsFixed(2),
                  bold: true,
                  flex: 2,
                ),
                _buildTableCell(
                  "-", // Avg sale rate doesn't have a meaningful total
                  bold: true,
                  flex: 2,
                ),
                _buildTableCell(
                  _calculateTotal('total_sold').toStringAsFixed(2),
                  bold: true,
                  flex: 2,
                ),
                _buildTableCell(
                  formatProfit(_calculateTotal('profit')),
                  bold: true,
                  color:
                      _calculateTotal('profit') >= 0
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                  flex: 1,
                ),
              ],
            ),
          ),
        ],
      ),
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

  double _calculateTotal(String field) {
    return _currencyStats
        .where((stat) => stat['currency'] != 'SOM')
        .fold(0.0, (sum, stat) => sum + (stat[field] as double? ?? 0.0));
  }

  Widget _buildCurrencyCard(Map<String, dynamic> stat) {
    final avgPurchaseRate = stat['avg_purchase_rate'] as double? ?? 0.0;
    final avgSaleRate = stat['avg_sale_rate'] as double? ?? 0.0;
    final totalPurchased = stat['total_purchased'] as double? ?? 0.0;
    final totalSold = stat['total_sold'] as double? ?? 0.0;
    final currentQuantity = stat['current_quantity'] as double? ?? 0.0;
    final profit = stat['profit'] as double? ?? 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  stat['currency'].toString(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        profit >= 0
                            ? Colors.green.shade100
                            : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    formatProfit(profit),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color:
                          profit >= 0
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatRow(
              _getTranslatedText('current_balance'),
              '${currentQuantity.toStringAsFixed(2)} ${stat['currency']}',
            ),
            const Divider(height: 16),
            Text(
              _getTranslatedText('purchase_info'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
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
            const SizedBox(height: 8),
            Text(
              _getTranslatedText('sale_info'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
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
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencyCardsList() {
    // Apply currency filter if any currencies are selected, just like in the table view
    final currenciesToDisplay =
        _currencyStats
            .where(
              (stat) =>
                  stat['currency'] != 'SOM' &&
                  (_selectedCurrencies.isEmpty ||
                      _selectedCurrencies.contains(stat['currency'])),
            )
            .toList();

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: currenciesToDisplay.length,
      itemBuilder: (context, index) {
        return _buildCurrencyCard(currenciesToDisplay[index]);
      },
    );
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
                      _calculateTotal('total_purchased').toStringAsFixed(2),
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

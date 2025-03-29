import 'package:flutter/material.dart';
import '../db_helper.dart';

// This file is now renamed to statistics_screen.dart
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen>
    with WidgetsBindingObserver {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _currencyStats = [];
  double _totalProfit = 0.0;
  double _somBalance = 0.0;
  double _kassaValue = 0.0;
  bool _isLoading = false;
  DateTime? _lastLoadTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCurrencyStats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh data when app resumes from background
    if (state == AppLifecycleState.resumed) {
      _loadCurrencyStats();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Always force refresh when the screen becomes visible
    _lastLoadTime = null; // Reset last load time
    _loadCurrencyStats();
  }

  Future<void> _loadCurrencyStats() async {
    if (!mounted || _isLoading) return;

    setState(() => _isLoading = true);
    _lastLoadTime = DateTime.now();

    try {
      final analytics = await _dbHelper.calculateAnalytics();

      if (!mounted) return;

      // Calculate SOM balance and kassa value
      double somBalance = 0.0;
      double kassaValue = 0.0;

      if (analytics.containsKey('currency_stats')) {
        final stats = analytics['currency_stats'] as List<dynamic>;

        // Convert to proper format and filter out invalid entries
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
            final currentQuantity = stat['current_quantity'] as double? ?? 0.0;
            final avgSaleRate = stat['avg_sale_rate'] as double? ?? 0.0;
            kassaValue += currentQuantity * avgSaleRate;
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

  Widget _buildSummaryCards() {
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.blue.shade50, // Light blue background for SOM
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Main Currency (SOM)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                _buildStatRow(
                  'Balance',
                  _somBalance.toStringAsFixed(2),
                  valueColor: Colors.blue,
                ),
              ],
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Foreign Currency Value',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildStatRow(
                  'Total Kassa Value',
                  _kassaValue.toStringAsFixed(2),
                  valueColor: Colors.green,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrencyCard(Map<String, dynamic> stat) {
    final isSom = stat['currency'] == 'SOM';

    // Handle possible null values with defaults
    final avgPurchaseRate = stat['avg_purchase_rate'] as double? ?? 0.0;
    final avgSaleRate = stat['avg_sale_rate'] as double? ?? 0.0;
    final totalPurchased = stat['total_purchased'] as double? ?? 0.0;
    final totalSold = stat['total_sold'] as double? ?? 0.0;
    final currentQuantity = stat['current_quantity'] as double? ?? 0.0;
    final profit = stat['profit'] as double? ?? 0.0;
    if (isSom) return const SizedBox();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: isSom ? Colors.blue.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  stat['currency'].toString(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isSom ? Colors.blue : null,
                  ),
                ),
                if (isSom)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text(
                      '(Main Currency)',
                      style: TextStyle(
                        color: Colors.blue,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildStatRow('Avg Buy Rate', avgPurchaseRate.toStringAsFixed(4)),
            _buildStatRow('Avg Sell Rate', avgSaleRate.toStringAsFixed(4)),
            _buildStatRow('Purchased', totalPurchased.toStringAsFixed(2)),
            _buildStatRow('Sold', totalSold.toStringAsFixed(2)),
            _buildStatRow('Remaining', currentQuantity.toStringAsFixed(2)),
            _buildProfitRow(profit),
            const Divider(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitRow(double profit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Profit', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(
            formatProfit(profit),
            style: TextStyle(
              color: profit >= 0 ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalProfitCard() {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.shade100, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Total Profit:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              formatProfit(_totalProfit),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _totalProfit >= 0 ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if we're on a tablet
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width >= 600;
    final isLandscape = screenSize.width > screenSize.height;
    final isWideTablet = isTablet && isLandscape;
    
    // Determine column count based on screen width
    final columnCount = isWideTablet ? 3 : (isTablet ? 2 : 1);
    
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadCurrencyStats,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24, top: 16),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title with refresh button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Statistics & Balance',
                            style: TextStyle(
                              fontSize: isTablet ? 24 : 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _loadCurrencyStats,
                            tooltip: 'Refresh Statistics',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Total profit card
                    isWideTablet
                        ? _buildWideTabletSummary()
                        : _buildSummaryCards(),
                    
                    // Currency statistics section
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'Currency Statistics',
                        style: TextStyle(
                          fontSize: isTablet ? 20 : 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                    
                    // Currency display: table for tablets, list for mobile
                    isTablet
                        ? _buildCurrencyTable()
                        : _buildCurrencyCardsList(),
                  ],
                ),
              ),
      ),
    );
  }
  
  // Wide tablet layout with all summary cards in one row
  Widget _buildWideTabletSummary() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // SOM Balance
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SOM Balance',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${_somBalance.toStringAsFixed(2)} SOM',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Foreign Currency Value
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Foreign Currency Value',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${_kassaValue.toStringAsFixed(2)} SOM',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Total Profit
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Profit',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${formatProfit(_totalProfit)} SOM',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _totalProfit >= 0 
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Grid layout for currency cards on tablets
  Widget _buildCurrencyCardsGrid(int columnCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columnCount,
          childAspectRatio: 1.2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _currencyStats.length,
        itemBuilder: (context, index) {
          return _buildCurrencyCardForGrid(_currencyStats[index]);
        },
      ),
    );
  }
  
  // Table layout for tablet view
  Widget _buildCurrencyTable() {
    // Filter out SOM from the display list for table
    final currenciesToDisplay = _currencyStats.where((stat) => stat['currency'] != 'SOM').toList();
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Table header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  _buildTableHeaderCell('Currency', flex: 2),
                  _buildTableHeaderCell('Balance', flex: 2),
                  _buildTableHeaderCell('Purchased', flex: 2),
                  _buildTableHeaderCell('Sold', flex: 2),
                  _buildTableHeaderCell('Avg Buy', flex: 2),
                  _buildTableHeaderCell('Avg Sell', flex: 2),
                  _buildTableHeaderCell('Profit', flex: 2),
                ],
              ),
            ),
            
            // Table body
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
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: Colors.grey.shade300,
                ),
                itemBuilder: (context, index) {
                  final stat = currenciesToDisplay[index];
                  final avgPurchaseRate = stat['avg_purchase_rate'] as double? ?? 0.0;
                  final avgSaleRate = stat['avg_sale_rate'] as double? ?? 0.0;
                  final totalPurchased = stat['total_purchased'] as double? ?? 0.0;
                  final totalSold = stat['total_sold'] as double? ?? 0.0;
                  final currentQuantity = stat['current_quantity'] as double? ?? 0.0;
                  final profit = stat['profit'] as double? ?? 0.0;
                  
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    color: index % 2 == 0 ? Colors.grey.shade50 : Colors.white,
                    child: Row(
                      children: [
                        // Currency
                        _buildTableCell(
                          stat['currency'].toString(),
                          bold: true,
                          color: Colors.blue.shade800,
                          flex: 2,
                        ),
                        
                        // Balance
                        _buildTableCell(
                          currentQuantity.toStringAsFixed(2),
                          bold: true,
                          flex: 2,
                        ),
                        
                        // Purchased
                        _buildTableCell(
                          totalPurchased.toStringAsFixed(2),
                          flex: 2,
                        ),
                        
                        // Sold
                        _buildTableCell(
                          totalSold.toStringAsFixed(2),
                          flex: 2,
                        ),
                        
                        // Avg Buy Rate
                        _buildTableCell(
                          avgPurchaseRate.toStringAsFixed(4),
                          color: Colors.red.shade700,
                          flex: 2,
                        ),
                        
                        // Avg Sell Rate
                        _buildTableCell(
                          avgSaleRate.toStringAsFixed(4),
                          color: Colors.green.shade700,
                          flex: 2,
                        ),
                        
                        // Profit
                        _buildTableCell(
                          formatProfit(profit),
                          bold: true,
                          color: profit >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                          flex: 2,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            
            // Table footer with totals
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  _buildTableCell('TOTAL', bold: true, flex: 2),
                  
                  // Total Balance
                  _buildTableCell(
                    _calculateTotal('current_quantity').toStringAsFixed(2),
                    bold: true,
                    flex: 2,
                  ),
                  
                  // Total Purchased
                  _buildTableCell(
                    _calculateTotal('total_purchased').toStringAsFixed(2),
                    bold: true,
                    flex: 2,
                  ),
                  
                  // Total Sold
                  _buildTableCell(
                    _calculateTotal('total_sold').toStringAsFixed(2),
                    bold: true,
                    flex: 2,
                  ),
                  
                  // Empty cells for avg rates
                  _buildTableCell('', flex: 2),
                  _buildTableCell('', flex: 2),
                  
                  // Total Profit
                  _buildTableCell(
                    formatProfit(_totalProfit),
                    bold: true,
                    color: _totalProfit >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                    flex: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Helper for building table header cells
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
  
  // Helper for building table cells
  Widget _buildTableCell(
    String text, {
    bool bold = false,
    Color? color,
    int flex = 1,
  }) {
    // Fix for -0.00 display
    if (text == "-0.00") {
      text = "0.00";
    }
    
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
  
  // Helper to calculate totals for the specified field
  double _calculateTotal(String field) {
    return _currencyStats
        .where((stat) => stat['currency'] != 'SOM')
        .fold(0.0, (sum, stat) => sum + (stat[field] as double? ?? 0.0));
  }
  
  // Helper to format profit values, handling the -0.00 case
  String formatProfit(double value) {
    // Check if the value is very close to zero (to handle floating point precision issues)
    if (value > -0.005 && value < 0.005) {
      return "0.00";
    }
    return value.toStringAsFixed(2);
  }
  
  // Modified currency card for grid layout with more compact stats
  Widget _buildCurrencyCardForGrid(Map<String, dynamic> stat) {
    final isSom = stat['currency'] == 'SOM';
    
    // Handle possible null values with defaults
    final avgPurchaseRate = stat['avg_purchase_rate'] as double? ?? 0.0;
    final avgSaleRate = stat['avg_sale_rate'] as double? ?? 0.0;
    final currentQuantity = stat['current_quantity'] as double? ?? 0.0;
    final profit = stat['profit'] as double? ?? 0.0;
    
    return Card(
      elevation: 3,
      color: isSom ? Colors.blue.shade50 : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Currency name with icon
            Row(
              children: [
                Text(
                  stat['currency'].toString(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isSom ? Colors.blue.shade700 : Colors.blue.shade800,
                  ),
                ),
                if (isSom)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.star,
                      size: 16,
                      color: Colors.amber.shade700,
                    ),
                  ),
                const Spacer(),
                // Circular indicator for positive/negative profit
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: profit >= 0 ? Colors.green.shade100 : Colors.red.shade100,
                  ),
                  child: Center(
                    child: Icon(
                      profit >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 16,
                      color: profit >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            
            // Balance information
            Text(
              'Current Balance',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              currentQuantity.toStringAsFixed(2),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            
            // Rates
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Avg Buy', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      avgPurchaseRate.toStringAsFixed(2),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Avg Sell', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      avgSaleRate.toStringAsFixed(2),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Profit
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Profit: ',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                Text(
                  formatProfit(profit),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: profit >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  // Original list layout for currency cards on mobile
  Widget _buildCurrencyCardsList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _currencyStats.length,
      itemBuilder: (context, index) {
        return _buildCurrencyCard(_currencyStats[index]);
      },
    );
  }
}

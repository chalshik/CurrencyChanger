import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart'; // Add SystemChrome
import '../db_helper.dart';
import '../models/currency.dart';
import '../models/history.dart';
import 'history_screen.dart';
import 'settings.dart';
import 'analytics_screen.dart';
import 'statistics_screen.dart';
import 'login_screen.dart';
import 'package:flutter/rendering.dart';

// Responsive Currency Converter
class ResponsiveCurrencyConverter extends StatelessWidget {
  const ResponsiveCurrencyConverter({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 599) {
          return const TabletCurrencyConverterLayout();
        } else {
          return const MobileCurrencyConverterLayout();
        }
      },
    );
  }
}

// Core Converter Logic
class CurrencyConverterCore extends StatefulWidget {
  final bool isWideLayout;

  const CurrencyConverterCore({super.key, this.isWideLayout = false});

  @override
  State<CurrencyConverterCore> createState() => _CurrencyConverterCoreState();
}

class _CurrencyConverterCoreState extends State<CurrencyConverterCore> {
  final _databaseHelper = DatabaseHelper.instance;
  List<CurrencyModel> _currencies = [];
  List<HistoryModel> _recentHistory = [];
  final TextEditingController _currencyController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  String _selectedCurrency = '';
  String _operationType = 'Purchase';
  double _totalSum = 0.0;
  bool _isLoading = true;

  // Add focus nodes to track which field is active
  final FocusNode _currencyFocusNode = FocusNode();
  final FocusNode _quantityFocusNode = FocusNode();

  // Track which field is currently active for the numpad
  bool _isRateFieldActive = true;

  // Track numpad visibility for tablet portrait mode
  bool _isNumpadVisible = true;

  @override
  void initState() {
    super.initState();
    _initializeData();

    // Set default values to start with
    _currencyController.text = '';
    _quantityController.text = '';

    // Set up listeners for focus changes
    _currencyFocusNode.addListener(_handleFocusChange);
    _quantityFocusNode.addListener(_handleFocusChange);
    
    // Add listeners to the text controllers to update total when text changes
    _currencyController.addListener(_calculateTotal);
    _quantityController.addListener(_calculateTotal);

    // Ensure rate field is active initially
    _isRateFieldActive = true;

    // Schedule focus request for after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isWideLayout) {
        // Request focus on rate field
        _currencyFocusNode.requestFocus();
      }
    });
  }

  void _handleFocusChange() {
    setState(() {
      _isRateFieldActive = _currencyFocusNode.hasFocus;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when screen becomes visible
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _loadCurrencies();
    await _loadOperationHistory();
  }

  Future<void> _loadCurrencies() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      final currencies = await _databaseHelper.getAllCurrencies();

      if (!mounted) return;
      setState(() {
        _currencies = currencies;
        _isLoading = false;

        // Update selected currency if needed
        if (_selectedCurrency.isEmpty && currencies.isNotEmpty) {
          for (var currency in currencies) {
            if (currency.code != 'SOM') {
              _selectedCurrency = currency.code!;
              // Set the default exchange rate based on operation type
              _currencyController.text = _operationType == 'Purchase' 
                  ? currency.defaultBuyRate.toString()
                  : currency.defaultSellRate.toString();
              _calculateTotal();
              break;
            }
          }
        }
      });
    } catch (e) {
      debugPrint('Error loading currencies: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadOperationHistory() async {
    try {
      final historyEntries = await _databaseHelper.getHistoryEntries(limit: 10);
      setState(() {
        _recentHistory = historyEntries;
      });
    } catch (e) {
      _showBriefNotification('Error loading history', Colors.red);
    }
  }

  void _calculateTotal() {
    // Convert empty fields to 0
    double currencyValue = _currencyController.text.isEmpty 
        ? 0.0 
        : double.tryParse(_currencyController.text) ?? 0.0;
    
    double quantity = _quantityController.text.isEmpty 
        ? 0.0 
        : double.tryParse(_quantityController.text) ?? 0.0;
    
    setState(() {
      _totalSum = currencyValue * quantity;
    });
  }

  // Show brief notification (snackbar)
  void _showBriefNotification(String message, Color backgroundColor) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildCurrencyInputSection() {
    final screenSize = MediaQuery.of(context).size;
    final isPortrait = screenSize.height > screenSize.width;
    final isTablet = MediaQuery.of(context).size.width > 600;
    final isSmallScreen = screenSize.width < 360;
    final fontSize = isSmallScreen ? 13.0 : 14.0;
    final iconSize = isSmallScreen ? 18.0 : 24.0;
    
    // For portrait mode, put the fields in a row
    if (isPortrait) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Exchange Rate Field
          Expanded(
            child: TextField(
              controller: _currencyController,
              focusNode: _currencyFocusNode,
              decoration: InputDecoration(
                labelText: 'Exchange Rate',
                hintText: _operationType == 'Purchase'
                    ? 'Enter buy rate'
                    : 'Enter sell rate',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                prefixIcon: Icon(
                  Icons.attach_money,
                  color: Colors.blue,
                  size: iconSize,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              // Show tablet keyboard when numpad is hidden and we're on a tablet
              readOnly: isTablet && _isNumpadVisible,
              showCursor: true,
              // Always calculate total when text changes
              onChanged: (_) => _calculateTotal(),
              style: TextStyle(fontSize: fontSize),
              onTap: () {
                setState(() {
                  _isRateFieldActive = true;
                });
              },
            ),
          ),
          const SizedBox(width: 16),
          // Quantity Field
          Expanded(
            child: TextField(
              controller: _quantityController,
              focusNode: _quantityFocusNode,
              decoration: InputDecoration(
                labelText: 'Quantity',
                hintText: 'Enter amount in $_selectedCurrency',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                prefixIcon: Icon(
                  Icons.numbers,
                  color: Colors.blue,
                  size: iconSize,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              // Show tablet keyboard when numpad is hidden and we're on a tablet
              readOnly: isTablet && _isNumpadVisible,
              showCursor: true,
              // Always calculate total when text changes
              onChanged: (_) => _calculateTotal(),
              style: TextStyle(fontSize: fontSize),
              onTap: () {
                setState(() {
                  _isRateFieldActive = false;
                });
              },
            ),
          ),
        ],
      );
    }
    
    // For landscape mode, stack the fields vertically
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Exchange Rate field
        TextField(
          controller: _currencyController,
          focusNode: _currencyFocusNode,
          decoration: InputDecoration(
            labelText: 'Exchange Rate',
            hintText: _operationType == 'Purchase'
                ? 'Enter buy rate'
                : 'Enter sell rate',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            prefixIcon: Icon(
              Icons.attach_money,
              color: Colors.blue,
              size: iconSize,
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 12,
            ),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          readOnly: isTablet,
          showCursor: true,
          // Always calculate total when text changes
          onChanged: (_) => _calculateTotal(),
          style: TextStyle(fontSize: fontSize),
          onTap: () {
            setState(() {
              _isRateFieldActive = true;
            });
          },
        ),
        const SizedBox(height: 16),
        // Quantity field
        TextField(
          controller: _quantityController,
          focusNode: _quantityFocusNode,
          decoration: InputDecoration(
            labelText: 'Quantity',
            hintText: 'Enter amount in $_selectedCurrency',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            prefixIcon: Icon(
              Icons.numbers,
              color: Colors.blue,
              size: iconSize,
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 12,
            ),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          readOnly: isTablet,
          showCursor: true,
          // Always calculate total when text changes
          onChanged: (_) => _calculateTotal(),
          style: TextStyle(fontSize: fontSize),
          onTap: () {
            setState(() {
              _isRateFieldActive = false;
            });
          },
        ),
      ],
    );
  }

  Widget _buildTotalSumCard() {
    // Get screen width to adjust sizing
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;
    final titleSize = isSmallScreen ? 14.0 : 16.0;
    final valueSize = isSmallScreen ? 24.0 : 28.0;
    final subtitleSize = isSmallScreen ? 12.0 : 14.0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
        child: Column(
          children: [
            Text(
              _operationType == 'Purchase'
                  ? 'Total SOM to pay'
                  : 'Total SOM to receive',
              style: TextStyle(
                fontSize: titleSize,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_totalSum.toStringAsFixed(2)} SOM',
              style: TextStyle(
                fontSize: valueSize,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'for ${_quantityController.text.isEmpty ? '0' : _quantityController.text} $_selectedCurrency',
              style: TextStyle(
                fontSize: subtitleSize,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencySelector() {
    // Check screen size to adjust layout accordingly
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;

    // Filter out SOM currency for selection
    final availableCurrencies =
        _currencies.where((c) => c.code != 'SOM').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Currency:',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.blue.shade700,
            fontWeight: FontWeight.bold,
            fontSize: isSmallScreen ? 14 : 16,
          ),
        ),
        const SizedBox(height: 4),
        _isLoading
            ? const Center(child: CircularProgressIndicator())
            : availableCurrencies.isEmpty
            ? Center(
              child: Column(
                children: [
                  Text(
                    'No currencies available',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add currencies in Settings',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            )
            : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:
                    availableCurrencies.map((currency) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            currency.code ?? '',
                            style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                          ),
                          selected: _selectedCurrency == currency.code,
                          onSelected: (selected) {
                            if (currency.code != null) {
                              setState(() {
                                _selectedCurrency = currency.code!;
                                // Set the default exchange rate based on operation type
                                _currencyController.text = _operationType == 'Purchase' 
                                    ? currency.defaultBuyRate.toString()
                                    : currency.defaultSellRate.toString();
                                _calculateTotal();
                              });
                            }
                          },
                          backgroundColor: Colors.blue.shade50,
                          selectedColor: Colors.blue.shade700,
                          labelStyle: TextStyle(
                            color:
                                _selectedCurrency == currency.code
                                    ? Colors.white
                                    : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
              ),
            ),
      ],
    );
  }

  Widget _buildOperationTypeButtons() {
    // Get screen width to adjust button size
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;
    final buttonPadding =
        isSmallScreen
            ? const EdgeInsets.symmetric(vertical: 12)
            : const EdgeInsets.symmetric(vertical: 16);
    final buttonTextSize = isSmallScreen ? 14.0 : 16.0;

    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                _operationType = 'Purchase';
                // Update exchange rate based on selected currency
                if (_selectedCurrency.isNotEmpty) {
                  final selectedCurrency = _currencies.firstWhere(
                    (c) => c.code == _selectedCurrency,
                    orElse: () => CurrencyModel(code: ''),
                  );
                  _currencyController.text = selectedCurrency.defaultBuyRate.toString();
                  _calculateTotal();
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _operationType == 'Purchase'
                  ? Colors.blue.shade700
                  : Colors.blue.shade50,
              foregroundColor: _operationType == 'Purchase'
                  ? Colors.white
                  : Colors.blue.shade700,
              padding: buttonPadding,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Purchase',
              style: TextStyle(
                fontSize: buttonTextSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                _operationType = 'Sale';
                // Update exchange rate based on selected currency
                if (_selectedCurrency.isNotEmpty) {
                  final selectedCurrency = _currencies.firstWhere(
                    (c) => c.code == _selectedCurrency,
                    orElse: () => CurrencyModel(code: ''),
                  );
                  _currencyController.text = selectedCurrency.defaultSellRate.toString();
                  _calculateTotal();
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _operationType == 'Sale'
                  ? Colors.blue.shade700
                  : Colors.blue.shade50,
              foregroundColor: _operationType == 'Sale'
                  ? Colors.white
                  : Colors.blue.shade700,
              padding: buttonPadding,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Sale',
              style: TextStyle(
                fontSize: buttonTextSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFinishButton() {
    // Get screen width to adjust sizing
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;
    final isLandscape = screenSize.width > screenSize.height;

    // Larger sizes for landscape mode
    final fontSize = isLandscape ? 18.0 : (isSmallScreen ? 13.0 : 15.0);
    final verticalPadding = isLandscape ? 18.0 : (isSmallScreen ? 14.0 : 16.0);
    final buttonHeight = isLandscape ? 60.0 : (isSmallScreen ? 50.0 : 56.0);

    return Container(
      height: buttonHeight,
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      child: ElevatedButton(
        onPressed: _finishOperation,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: Colors.blue.shade200,
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          'Finish Operation',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Future<void> _finishOperation() async {
    if (_currencyController.text.isEmpty || _quantityController.text.isEmpty) {
      _showBriefNotification('Please enter rate and amount', Colors.orange);
      return;
    }
    if (_currencies.isEmpty) {
      _showBriefNotification(
        'No currencies available for exchange',
        Colors.orange,
      );
      return;
    }

    try {
      final rate = double.parse(_currencyController.text);
      final quantity = double.parse(_quantityController.text);
      final totalSom = rate * quantity;

      if (_operationType == 'Purchase') {
        // Check if we have enough SOM to buy the currency
        final hasEnough = await _databaseHelper.hasEnoughSomForPurchase(
          totalSom,
        );
        if (!hasEnough) {
          _showBriefNotification(
            'Not enough SOM for this purchase',
            Colors.red,
          );
          return;
        }
      } else {
        // Check if we have enough of the currency to sell
        final hasEnough = await _databaseHelper.hasEnoughCurrencyToSell(
          _selectedCurrency,
          quantity,
        );
        if (!hasEnough) {
          _showBriefNotification(
            'Not enough $_selectedCurrency to sell',
            Colors.red,
          );
          return;
        }
      }

      // Proceed with the operation
      await _databaseHelper.performCurrencyExchange(
        currencyCode: _selectedCurrency,
        operationType: _operationType,
        rate: rate,
        quantity: quantity,
      );

      setState(() {
        _currencyController.clear();
        _quantityController.clear();
        _totalSum = 0.0;
      });

      _showBriefNotification(
        '$_operationType operation completed',
        _operationType == 'Purchase' ? Colors.green : Colors.red,
      );

      // Refresh history and available currencies
      await _loadOperationHistory();
      await _loadCurrencies();
    } catch (e) {
      _showBriefNotification('Operation failed: ${e.toString()}', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check screen size to adjust layout accordingly
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;
    final isTablet = screenSize.width >= 600;
    final spacing = isSmallScreen ? 8.0 : 12.0;

    final cardRadius = widget.isWideLayout ? 20.0 : 16.0;
    final cardPadding =
        widget.isWideLayout ? 20.0 : (isSmallScreen ? 8.0 : 12.0);
    final headerFontSize =
        widget.isWideLayout ? 22.0 : (isSmallScreen ? 16.0 : 18.0);
    final standardFontSize =
        widget.isWideLayout ? 16.0 : (isSmallScreen ? 13.0 : 15.0);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(cardPadding),
          child:
              widget.isWideLayout
                  ? _buildTabletLayout(
                    context,
                    spacing,
                    headerFontSize,
                    standardFontSize,
                    isTablet,
                  )
                  : _buildMobileLayout(
                    context,
                    spacing,
                    headerFontSize,
                    standardFontSize,
                  ),
        ),
      ),
    );
  }

  // Two-column layout optimized for tablets
  Widget _buildTabletLayout(
    BuildContext context,
    double spacing,
    double headerFontSize,
    double standardFontSize,
    bool isTablet,
  ) {
    final screenSize = MediaQuery.of(context).size;
    final isPortrait = screenSize.height > screenSize.width;

    // For tablet in portrait orientation:
    if (isPortrait) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Currency Exchange',
                  style: TextStyle(
                    fontSize: headerFontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ),
              // Toggle numpad button for tablet portrait mode
              _buildNumpadToggleButton(),
            ],
          ),
          SizedBox(height: spacing),
          
          // Exchange rate and quantity in one row for portrait mode
          _buildCurrencyInputSection(),
          
          // Total sum display
          _buildTotalSumCard(),
          SizedBox(height: spacing),
          
          // Currency selector now below total amount
          _buildCurrencySelector(),
          SizedBox(height: spacing),
          
          // Position numpad after currency selector
          if (isTablet && _isNumpadVisible) _buildPortraitNumpad(),
          SizedBox(height: spacing),
          
          // Operation type and finish button
          Text(
            'Operation Type:',
            style: TextStyle(
              fontSize: standardFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade800,
            ),
          ),
          SizedBox(height: 4),
          _buildOperationTypeButtons(),
          SizedBox(height: spacing),
          _buildFinishButton(),
        ],
      );
    }

    // Landscape tablet layout with positioned finish button
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _operationType == 'Purchase'
                ? 'Buy Foreign Currency'
                : 'Sell Foreign Currency',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.blue.shade800,
              fontWeight: FontWeight.bold,
              fontSize: headerFontSize,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: spacing),
          // Main content area
          LayoutBuilder(
            builder: (context, constraints) {
              final isLandscape =
                  MediaQuery.of(context).size.width >
                  MediaQuery.of(context).size.height;

              // Use row in landscape, column in portrait for tablets
              if (isLandscape) {
                return Stack(
                  children: [
                    // Main row with content
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left column - main controls
                        Expanded(
                          flex: 5,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildCurrencyInputSection(),
                                SizedBox(height: spacing),
                                _buildTotalSumCard(),
                                SizedBox(height: spacing),
                                _buildCurrencySelector(),
                                SizedBox(height: spacing),
                                Text(
                                  'Operation Type:',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium?.copyWith(
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold,
                                    fontSize: standardFontSize,
                                  ),
                                ),
                                SizedBox(height: 4),
                                _buildOperationTypeButtons(),
                                SizedBox(
                                  height: spacing * 3,
                                ), // Extra space for button at bottom
                              ],
                            ),
                          ),
                        ),
                        // Right column for numpad
                        if (isTablet) ...[
                          SizedBox(width: spacing),
                          Expanded(flex: 3, child: _buildNumpad()),
                        ],
                      ],
                    ),

                    // Positioned finish button at bottom right
                    Positioned(
                      right: 0,
                      bottom: 50, // Position it even higher (50px from bottom)
                      child: Container(
                        width: 250, // Maintain width
                        padding: const EdgeInsets.symmetric(
                          vertical: 2,
                        ), // Add padding to fix overlap
                        child: _buildFinishButton(),
                      ),
                    ),
                  ],
                );
              } else {
                // Portrait tablet layout - make it more compact
                return Column(
                  children: [
                    // Currency input
                    _buildCurrencyInputSection(),
                    SizedBox(height: spacing),

                    // Total sum card 
                    _buildTotalSumCard(),
                    SizedBox(height: spacing),
                    
                    // Currency selector below total
                    _buildCurrencySelector(),
                    SizedBox(height: spacing),

                    // Position numpad after currency selector
                    if (isTablet && _isNumpadVisible) _buildPortraitNumpad(),
                    SizedBox(height: spacing),

                    // Operation type and finish button
                    Text(
                      'Operation Type:',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: standardFontSize,
                      ),
                    ),
                    SizedBox(height: 4),
                    _buildOperationTypeButtons(),
                    SizedBox(height: spacing),
                    _buildFinishButton(),
                    SizedBox(height: spacing * 2),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // Column layout for mobile devices
  Widget _buildMobileLayout(
    BuildContext context,
    double spacing,
    double headerFontSize,
    double standardFontSize,
  ) {
    final isPortrait = MediaQuery.of(context).size.height > MediaQuery.of(context).size.width;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Currency Exchange',
          style: TextStyle(
            fontSize: headerFontSize,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade800,
          ),
        ),
        SizedBox(height: spacing),
        
        // Input fields
        _buildCurrencyInputSection(),
        
        // Total amount card
        _buildTotalSumCard(),
        SizedBox(height: spacing),
        
        // Currency selector (moved below total card)
        _buildCurrencySelector(),
        SizedBox(height: spacing),
        
        // Operation type buttons (Buy/Sell)
        Text(
          'Operation Type:',
          style: TextStyle(
            fontSize: standardFontSize,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade800,
          ),
        ),
        SizedBox(height: 4),
        _buildOperationTypeButtons(),
        SizedBox(height: spacing),
        
        // Submit button
        _buildFinishButton(),
      ],
    );
  }

  // Add method to create toggle numpad button
  Widget _buildNumpadToggleButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ElevatedButton.icon(
        onPressed: () {
          setState(() {
            _isNumpadVisible = !_isNumpadVisible;
          });
        },
        icon: Icon(
          _isNumpadVisible ? Icons.keyboard_hide : Icons.keyboard,
          size: 20,
        ),
        label: Text(_isNumpadVisible ? 'Hide Numpad' : 'Show Numpad'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey.shade200,
          foregroundColor: Colors.grey.shade800,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  // Special numpad layout for portrait mode with buttons on the side
  Widget _buildPortraitNumpad() {
    // If numpad is hidden, return empty container
    if (!_isNumpadVisible) {
      return const SizedBox.shrink();
    }
    
    final activeColor =
        _isRateFieldActive ? Colors.blue.shade100 : Colors.green.shade100;
    final activeBorder =
        _isRateFieldActive ? Colors.blue.shade700 : Colors.green.shade700;

    // Calculate optimal button size - make buttons smaller
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonSize = (screenWidth - 250) / 8; // Smaller buttons

    return Container(
      key: const ValueKey('portrait_numpad'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8), // More padding
      margin: const EdgeInsets.symmetric(vertical: 8), // More margin
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Numpad grid with side buttons - more spacing between buttons
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main number pad (3x4 grid)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // First row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPortraitNumpadButton('7', size: buttonSize),
                      const SizedBox(width: 12), // More spacing
                      _buildPortraitNumpadButton('8', size: buttonSize),
                      const SizedBox(width: 12), // More spacing
                      _buildPortraitNumpadButton('9', size: buttonSize),
                    ],
                  ),
                  const SizedBox(height: 12), // More spacing
                  // Second row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPortraitNumpadButton('4', size: buttonSize),
                      const SizedBox(width: 12), // More spacing
                      _buildPortraitNumpadButton('5', size: buttonSize),
                      const SizedBox(width: 12), // More spacing
                      _buildPortraitNumpadButton('6', size: buttonSize),
                    ],
                  ),
                  const SizedBox(height: 12), // More spacing
                  // Third row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPortraitNumpadButton('1', size: buttonSize),
                      const SizedBox(width: 12), // More spacing
                      _buildPortraitNumpadButton('2', size: buttonSize),
                      const SizedBox(width: 12), // More spacing
                      _buildPortraitNumpadButton('3', size: buttonSize),
                    ],
                  ),
                  const SizedBox(height: 12), // More spacing
                  // Fourth row (replaced backspace with 00)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPortraitNumpadButton('.', size: buttonSize),
                      const SizedBox(width: 12), // More spacing
                      _buildPortraitNumpadButton('0', size: buttonSize),
                      const SizedBox(width: 12), // More spacing
                      _buildPortraitNumpadButton('00', size: buttonSize),
                    ],
                  ),
                ],
              ),

              // Side buttons (same size as other buttons, no text)
              const SizedBox(width: 12), // More spacing
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Toggle button
                  SizedBox(
                    width: buttonSize,
                    height: buttonSize,
                    child: ElevatedButton(
                      onPressed: _toggleActiveField,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: activeBorder,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero, // No padding
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Icon(Icons.swap_horiz, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12), // More spacing
                  // Backspace button (was previously clear button - swapped positions)
                  SizedBox(
                    width: buttonSize,
                    height: buttonSize,
                    child: ElevatedButton(
                      onPressed: () => _handleNumpadInput('⌫'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade100,
                        foregroundColor: Colors.orange.shade900,
                        padding: EdgeInsets.zero, // No padding
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: BorderSide(color: Colors.grey.shade300, width: 1),
                        ),
                      ),
                      child: const Icon(Icons.backspace, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12), // More spacing
                  // Clear button (was previously backspace - swapped positions)
                  SizedBox(
                    width: buttonSize,
                    height: buttonSize,
                    child: ElevatedButton(
                      onPressed: _clearActiveField,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero, // No padding
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Text(
                        'C',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Special button for portrait mode with smaller size but larger font
  Widget _buildPortraitNumpadButton(
    String value, {
    required double size,
    bool isSpecial = false,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: () => _handleNumpadInput(value),
        style: ElevatedButton.styleFrom(
          backgroundColor: isSpecial ? Colors.orange.shade100 : Colors.white,
          foregroundColor: isSpecial ? Colors.orange.shade900 : Colors.black,
          elevation: 2,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: Colors.grey.shade300, width: 1),
          ),
        ),
        child: Center(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 18, // Larger font relative to button size
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // Numpad widget for tablets
  Widget _buildNumpad() {
    final activeColor =
        _isRateFieldActive ? Colors.blue.shade100 : Colors.green.shade100;
    final activeBorder =
        _isRateFieldActive ? Colors.blue.shade700 : Colors.green.shade700;

    // Calculate optimal button size based on available width
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscape =
        MediaQuery.of(context).size.width > MediaQuery.of(context).size.height;
    final buttonSize =
        isLandscape
            ? 50.0
            : (screenWidth > 600 ? 60.0 : 50.0); // Restore original sizes

    return Container(
      key: const ValueKey('numpad'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header showing active field
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: BoxDecoration(
              color: activeColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: activeBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _isRateFieldActive ? 'Exchange Rate' : 'Quantity',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: activeBorder,
                      fontSize: 14, // Restored
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: _toggleActiveField,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activeBorder,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: const Size(10, 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _isRateFieldActive ? 'To Quantity' : 'To Rate',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Number display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.shade50,
            ),
            child: Text(
              _isRateFieldActive
                  ? (_currencyController.text.isEmpty
                      ? '0'
                      : _currencyController.text)
                  : (_quantityController.text.isEmpty
                      ? '0'
                      : _quantityController.text),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18, // Restored
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(height: 6),

          // Layout with numpad and side buttons for landscape mode
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Numpad grid using Row and Column for more direct control
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // First row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildFixedSizeNumpadButton('7', size: buttonSize),
                        _buildFixedSizeNumpadButton('8', size: buttonSize),
                        _buildFixedSizeNumpadButton('9', size: buttonSize),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Second row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildFixedSizeNumpadButton('4', size: buttonSize),
                        _buildFixedSizeNumpadButton('5', size: buttonSize),
                        _buildFixedSizeNumpadButton('6', size: buttonSize),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Third row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildFixedSizeNumpadButton('1', size: buttonSize),
                        _buildFixedSizeNumpadButton('2', size: buttonSize),
                        _buildFixedSizeNumpadButton('3', size: buttonSize),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Fourth row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildFixedSizeNumpadButton('.', size: buttonSize),
                        _buildFixedSizeNumpadButton('0', size: buttonSize),
                        _buildFixedSizeNumpadButton(
                          '⌫',
                          size: buttonSize,
                          isSpecial: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Side buttons for landscape mode
              if (isLandscape) ...[
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Toggle button
                    SizedBox(
                      width: 60,
                      height: buttonSize * 2,
                      child: ElevatedButton(
                        onPressed: _toggleActiveField,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: activeBorder,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.swap_vert, size: 16),
                      
                            
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Clear button
                    SizedBox(
                      width: 60,
                      height: buttonSize * 2,
                      child: ElevatedButton(
                        onPressed: _clearActiveField,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'C',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),

          // Clear button at bottom (only for portrait mode or if not using side buttons)
          if (!isLandscape) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 36,
              child: ElevatedButton(
                onPressed: _clearActiveField,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('C', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Fixed size numpad button with smaller styling
  Widget _buildFixedSizeNumpadButton(
    String value, {
    required double size,
    bool isSpecial = false,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: () => _handleNumpadInput(value),
        style: ElevatedButton.styleFrom(
          backgroundColor: isSpecial ? Colors.orange.shade100 : Colors.white,
          foregroundColor: isSpecial ? Colors.orange.shade900 : Colors.black,
          elevation: 1,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        child: Center(
          child: Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  // Handle numpad button presses
  void _handleNumpadInput(String value) {
    final controller =
        _isRateFieldActive ? _currencyController : _quantityController;
    final currentText = controller.text;

    // Ensure controller has a valid selection
    if (controller.selection.baseOffset < 0) {
      controller.selection = TextSelection.collapsed(
        offset: currentText.length,
      );
    }

    final currentSelection = controller.selection;
    final selectionStart =
        currentSelection.start < 0 ? 0 : currentSelection.start;
    final selectionEnd = currentSelection.end < 0 ? 0 : currentSelection.end;

    if (value == '⌫') {
      // Handle backspace
      if (currentText.isEmpty) return;

      if (selectionStart == selectionEnd && selectionStart == 0) return;

      String newText;
      if (selectionStart == selectionEnd) {
        // Delete character before cursor
        final deletePos = selectionStart - 1;
        newText =
            currentText.substring(0, deletePos) +
            currentText.substring(selectionEnd);
        controller.text = newText;
        controller.selection = TextSelection.collapsed(offset: deletePos);
      } else {
        // Delete selected text
        newText =
            currentText.substring(0, selectionStart) +
            currentText.substring(selectionEnd);
        controller.text = newText;
        controller.selection = TextSelection.collapsed(offset: selectionStart);
      }
    } else if (value == '.') {
      // Only add decimal point if there isn't one already
      if (!currentText.contains('.')) {
        String newText;
        if (selectionStart != selectionEnd) {
          // Replace selected text
          newText =
              currentText.substring(0, selectionStart) +
              (currentText.isEmpty ? '0.' : '.') +
              currentText.substring(selectionEnd);
        } else {
          // Insert at cursor
          newText =
              currentText.isEmpty
                  ? '0.'
                  : currentText.substring(0, selectionStart) +
                      '.' +
                      currentText.substring(selectionEnd);
        }
        controller.text = newText;

        // Calculate new cursor position
        final newPosition = selectionStart + (currentText.isEmpty ? 2 : 1);
        controller.selection = TextSelection.collapsed(offset: newPosition);
      }
    } else if (value == '00') {
      // Handle double zero input - only add if there's already a non-zero number
      if (currentText.isNotEmpty && currentText != '0') {
        String newText;
        if (selectionStart != selectionEnd) {
          // Replace selected text
          newText = currentText.substring(0, selectionStart) + '00' + currentText.substring(selectionEnd);
        } else {
          // Insert at cursor
          newText = currentText.substring(0, selectionStart) + '00' + currentText.substring(selectionEnd);
        }
        
        controller.text = newText;
        controller.selection = TextSelection.collapsed(offset: selectionStart + 2);
      } else if (currentText.isEmpty) {
        // Just insert a single 0 if the field is empty
        controller.text = '0';
        controller.selection = TextSelection.collapsed(offset: 1);
      }
    } else {
      // Handle number input
      String newText;
      if (selectionStart != selectionEnd) {
        // Replace selected text
        newText =
            currentText.substring(0, selectionStart) +
            value +
            currentText.substring(selectionEnd);
      } else {
        // Insert at cursor
        newText =
            currentText.substring(0, selectionStart) +
            value +
            currentText.substring(selectionEnd);
      }

      controller.text = newText;
      controller.selection = TextSelection.collapsed(
        offset: selectionStart + 1,
      );
    }

    // Recalculate total
    _calculateTotal();
  }

  // Toggle between rate and quantity fields
  void _toggleActiveField() {
    setState(() {
      _isRateFieldActive = !_isRateFieldActive;
      if (_isRateFieldActive) {
        _currencyFocusNode.requestFocus();
      } else {
        _quantityFocusNode.requestFocus();
      }
    });
  }

  // Clear the active input field
  void _clearActiveField() {
    if (_isRateFieldActive) {
      _currencyController.clear();
    } else {
      _quantityController.clear();
    }
    // Ensure total is calculated immediately after clearing
    _calculateTotal();
  }

  @override
  void dispose() {
    _currencyController.dispose();
    _quantityController.dispose();
    _currencyFocusNode.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  // Custom tablet numpad for landscape mode
  Widget _buildTabletNumpad() {
    final activeColor = _isRateFieldActive ? Colors.blue.shade100 : Colors.green.shade100;
    final activeBorder = _isRateFieldActive ? Colors.blue.shade700 : Colors.green.shade700;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with field selection
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: activeColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: activeBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _isRateFieldActive ? 'Exchange Rate' : 'Quantity',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: activeBorder,
                      fontSize: 16,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _toggleActiveField,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activeBorder,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _isRateFieldActive ? 'To Quantity' : 'To Rate',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          // Current value display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.shade50,
            ),
            child: Text(
              _isRateFieldActive
                  ? (_currencyController.text.isEmpty ? '0' : _currencyController.text)
                  : (_quantityController.text.isEmpty ? '0' : _quantityController.text),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(height: 12),
          
          // Numpad grid
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Numpad columns
              Expanded(
                child: GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  childAspectRatio: 1.5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildNumpadButton('7'),
                    _buildNumpadButton('8'),
                    _buildNumpadButton('9'),
                    _buildNumpadButton('4'),
                    _buildNumpadButton('5'),
                    _buildNumpadButton('6'),
                    _buildNumpadButton('1'),
                    _buildNumpadButton('2'),
                    _buildNumpadButton('3'),
                    _buildNumpadButton('.'),
                    _buildNumpadButton('0'),
                    _buildNumpadButton('⌫', isSpecial: true),
                  ],
                ),
              ),
              
              // Side buttons
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // Switch fields button
                  SizedBox(
                    width: 60,
                    height: 100,
                    child: ElevatedButton(
                      onPressed: _toggleActiveField,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: activeBorder,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.swap_horiz),
                          SizedBox(height: 8),
                          Text(
                            'Switch\nFields',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Clear button
                  SizedBox(
                    width: 60,
                    height: 100,
                    child: ElevatedButton(
                      onPressed: _clearActiveField,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text(
                            'C',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          
                          
                          
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Numpad button for tablet landscape view
  Widget _buildNumpadButton(String value, {bool isSpecial = false}) {
    return ElevatedButton(
      onPressed: () => _handleNumpadInput(value),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSpecial ? Colors.orange.shade100 : Colors.white,
        foregroundColor: isSpecial ? Colors.orange.shade900 : Colors.black,
        elevation: 2,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Center(
        child: Text(
          value,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // Format the date for display
  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year.toString().substring(2)}';
  }

  // Build the current page directly rather than using IndexedStack
  Widget _buildCurrentPage() {
    // No implementation needed in the core state as this is handled by the layout classes
    return Container(); // This should never be called in the core state
  }

  // Recent transaction history list (defined but not used in the main view)
  Widget _buildHistoryList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _recentHistory.length,
      itemBuilder: (context, index) {
        final history = _recentHistory[index];
        final isPositive = history.operationType == 'Sale';
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 1,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: isPositive 
                  ? Colors.green.shade100
                  : Colors.red.shade100,
              child: Icon(
                isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
            title: Text(
              '${history.operationType} - ${history.currencyCode}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Rate: ${history.rate} SOM | Amount: ${history.quantity}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${history.rate * history.quantity} SOM',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
                Text(
                  _formatDate(history.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Mobile Layout
class MobileCurrencyConverterLayout extends StatefulWidget {
  const MobileCurrencyConverterLayout({super.key});

  @override
  State<MobileCurrencyConverterLayout> createState() =>
      _MobileCurrencyConverterLayoutState();
}

class _MobileCurrencyConverterLayoutState
    extends State<MobileCurrencyConverterLayout> {
  int _selectedIndex = 0;
  final _currencyConverterCoreKey = GlobalKey<_CurrencyConverterCoreState>();
  Key _historyScreenKey = GlobalKey();
  // Keys for statistics and analytics screens to force refresh
  Key _statisticsKey = UniqueKey();
  Key _analyticsKey = UniqueKey();

  late List<Widget> _pages;
  late List<BottomNavigationBarItem> _navigationItems;

  @override
  void initState() {
    super.initState();
    _initPages();
    _initNavigationItems();
  }

  void _initPages() {
    // Check if user is admin to determine what pages are available
    final bool isAdmin = currentUser?.role == 'admin';

    // Always include Converter and History screens
    _pages = [
      CurrencyConverterCore(key: _currencyConverterCoreKey),
      HistoryScreen(key: _historyScreenKey),
    ];

    // Add Statistics and Analytics screens only for admin users
    if (isAdmin) {
      _pages.add(StatisticsScreen(key: _statisticsKey));
      _pages.add(AnalyticsScreen(key: _analyticsKey));
    }

    // Add Settings screen for all users
    _pages.add(const SettingsScreen());
  }

  void _initNavigationItems() {
    // Check if user is admin
    final bool isAdmin = currentUser?.role == 'admin';

    // Basic navigation items available to all users
    _navigationItems = [
      const BottomNavigationBarItem(
        icon: Icon(Icons.currency_exchange),
        label: 'Converter',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.history),
        label: 'History',
      ),
    ];

    // Only add Analytics and Charts options for admin users
    if (isAdmin) {
      _navigationItems.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.analytics),
          label: 'Statistics',
        ),
      );

      _navigationItems.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.pie_chart),
          label: 'Analytics',
        ),
      );
    }

    // Settings available for all users
    _navigationItems.add(
      const BottomNavigationBarItem(
        icon: Icon(Icons.settings),
        label: 'Settings',
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;

      // Handle the history screen refresh
      if (index == 1) {
        _historyScreenKey = UniqueKey();
      }

      // For Statistics and Analytics screens, always recreate them with a new key
      // to force a full refresh when they're selected
      if (index == 2 && currentUser?.role == 'admin') {
        // Statistics screen
        _statisticsKey = UniqueKey();
      } else if (index == 3 && currentUser?.role == 'admin') {
        // Analytics screen
        _analyticsKey = UniqueKey();
      }

      // Refresh currency data when going to converter screen
      if (index == 0) {
        _loadCurrencyData();
      }
    });
  }

  // Method to refresh currency data in the converter screen
  void _loadCurrencyData() {
    _currencyConverterCoreKey.currentState?._loadCurrencies();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.blue.shade50,
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        title: const Text(
          'Currency Converter',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          // Use a direct widget instead of IndexedStack to ensure screens rebuild
          child: _buildCurrentPage(),
        ),
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.shade100,
              spreadRadius: 1,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BottomNavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: Colors.blue.shade700,
            unselectedItemColor: Colors.grey,
            type: BottomNavigationBarType.fixed,
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            items: _navigationItems,
          ),
        ),
      ),
    );
  }

  // Build the current page directly rather than using IndexedStack
  Widget _buildCurrentPage() {
    // This ensures every page switch fully rebuilds the widget
    return _pages[_selectedIndex];
  }
}

// Tablet Layout
class TabletCurrencyConverterLayout extends StatefulWidget {
  const TabletCurrencyConverterLayout({super.key});

  @override
  State<TabletCurrencyConverterLayout> createState() =>
      _TabletCurrencyConverterLayoutState();
}

class _TabletCurrencyConverterLayoutState
    extends State<TabletCurrencyConverterLayout> {
  int _selectedIndex = 0;
  final _currencyConverterCoreKey = GlobalKey<_CurrencyConverterCoreState>();
  Key _historyScreenKey = GlobalKey();
  // Keys for statistics and analytics screens to force refresh
  Key _statisticsKey = UniqueKey();
  Key _analyticsKey = UniqueKey();

  late List<Widget> _pages;
  // Use proper types for navigation items
  late List<NavigationDestination> _navigationBarDestinations;
  late List<NavigationRailDestination> _navigationRailDestinations;

  @override
  void initState() {
    super.initState();
    _initPages();
    _initNavigationDestinations();
  }

  void _initPages() {
    // Check if user is admin to determine what pages are available
    final bool isAdmin = currentUser?.role == 'admin';

    // Always include Converter and History screens
    _pages = [
      CurrencyConverterCore(isWideLayout: true, key: _currencyConverterCoreKey),
      HistoryScreen(key: _historyScreenKey),
    ];

    // Add Statistics and Analytics screens only for admin users
    if (isAdmin) {
      _pages.add(StatisticsScreen(key: _statisticsKey));
      _pages.add(AnalyticsScreen(key: _analyticsKey));
    }

    // Add Settings screen for all users
    _pages.add(const SettingsScreen());
  }

  void _initNavigationDestinations() {
    // Check if user is admin
    final bool isAdmin = currentUser?.role == 'admin';

    // Basic navigation items available to all users - for NavigationBar
    _navigationBarDestinations = [
      const NavigationDestination(
        icon: Icon(Icons.currency_exchange, size: 24),
        label: 'Converter',
      ),
      const NavigationDestination(
        icon: Icon(Icons.history, size: 24),
        label: 'History',
      ),
    ];

    // Basic navigation items for NavigationRail
    _navigationRailDestinations = [
      const NavigationRailDestination(
        icon: Icon(Icons.currency_exchange, size: 24),
        label: Text('Converter'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.history, size: 24),
        label: Text('History'),
      ),
    ];

    // Only add Analytics and Charts options for admin users
    if (isAdmin) {
      _navigationBarDestinations.add(
        const NavigationDestination(
          icon: Icon(Icons.analytics, size: 24),
          label: 'Statistics',
        ),
      );

      _navigationBarDestinations.add(
        const NavigationDestination(
          icon: Icon(Icons.pie_chart, size: 24),
          label: 'Analytics',
        ),
      );

      _navigationRailDestinations.add(
        const NavigationRailDestination(
          icon: Icon(Icons.analytics, size: 24),
          label: Text('Statistics'),
        ),
      );

      _navigationRailDestinations.add(
        const NavigationRailDestination(
          icon: Icon(Icons.pie_chart, size: 24),
          label: Text('Analytics'),
        ),
      );
    }

    // Settings available for all users
    _navigationBarDestinations.add(
      const NavigationDestination(
        icon: Icon(Icons.settings, size: 24),
        label: 'Settings',
      ),
    );

    _navigationRailDestinations.add(
      const NavigationRailDestination(
        icon: Icon(Icons.settings, size: 24),
        label: Text('Settings'),
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;

      // Handle the history screen refresh
      if (index == 1) {
        _historyScreenKey = UniqueKey();
      }

      // For Statistics and Analytics screens, always recreate them with a new key
      // to force a full refresh when they're selected
      if (index == 2 && currentUser?.role == 'admin') {
        // Statistics screen
        _statisticsKey = UniqueKey();
      } else if (index == 3 && currentUser?.role == 'admin') {
        // Analytics screen
        _analyticsKey = UniqueKey();
      }

      // Refresh currency data when going to converter screen
      if (index == 0) {
        _loadCurrencyData();
      }
    });
  }

  // Method to refresh currency data in the converter screen
  void _loadCurrencyData() {
    _currencyConverterCoreKey.currentState?._loadCurrencies();
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions to adjust layout accordingly
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    final isWideTablet = screenSize.width > 840;
    final horizontalPadding = isWideTablet ? 24.0 : 16.0;

    // Use side-by-side layout in landscape, bottom navigation in portrait
    if (isLandscape) {
      return Scaffold(
        backgroundColor: Colors.blue.shade50,
        appBar: AppBar(
          backgroundColor: Colors.blue.shade700,
          title: const Text(
            'Currency Converter',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
              letterSpacing: 0.5,
            ),
          ),
          centerTitle: true,
          elevation: 0,
        ),
        body: SafeArea(
          child: Row(
            children: [
              // Navigation rail on the left side in landscape mode
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _onItemTapped,
                labelType: NavigationRailLabelType.all,
                backgroundColor: Colors.white,
                useIndicator: true,
                indicatorColor: Colors.blue.shade100,
                selectedIconTheme: IconThemeData(color: Colors.blue.shade700),
                unselectedIconTheme: const IconThemeData(color: Colors.grey),
                destinations: _navigationRailDestinations,
                elevation: 4,
              ),
              // Vertical divider
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Colors.grey.shade300,
              ),
              // Main content
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(horizontalPadding),
                  child: _buildCurrentPage(),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Portrait mode - use bottom navigation similar to previous implementation
      return Scaffold(
        backgroundColor: Colors.blue.shade50,
        appBar: AppBar(
          backgroundColor: Colors.blue.shade700,
          title: const Text(
            'Currency Converter',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
              letterSpacing: 0.5,
            ),
          ),
          centerTitle: true,
          elevation: 0,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 16,
                  ),
                  child: _buildCurrentPage(),
                ),
              ),
            ],
          ),
        ),
        // Use NavigationBar for Material 3 design
        bottomNavigationBar: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.shade100,
                spreadRadius: 1,
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: NavigationBar(
            height: 70,
            backgroundColor: Colors.white,
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onItemTapped,
            destinations: _navigationBarDestinations,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            elevation: 0,
          ),
        ),
      );
    }
  }

  // Build the current page directly rather than using IndexedStack
  Widget _buildCurrentPage() {
    // This ensures every page switch fully rebuilds the widget
    return _pages[_selectedIndex];
  }
}

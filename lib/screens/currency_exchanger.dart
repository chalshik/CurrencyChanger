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
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';

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

    // Set empty values to start with
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

        // Update selected currency if needed, but don't auto-fill rate
        if (_selectedCurrency.isEmpty && currencies.isNotEmpty) {
          for (var currency in currencies) {
            if (currency.code != 'SOM') {
              _selectedCurrency = currency.code!;
              // Don't auto-fill rate values
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
    // Check if SOM is selected (rate is always 1.0 for SOM)
    if (_selectedCurrency == 'SOM') {
      double quantity =
          _quantityController.text.isEmpty
              ? 0.0
              : double.tryParse(_quantityController.text) ?? 0.0;

      setState(() {
        _totalSum = quantity; // For SOM, total equals quantity (rate is 1.0)
      });
      return;
    }

    // For other currencies, calculate normally
    double currencyValue =
        _currencyController.text.isEmpty
            ? 0.0
            : double.tryParse(_currencyController.text) ?? 0.0;

    double quantity =
        _quantityController.text.isEmpty
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

  // Add this method for translations
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

  Widget _buildCurrencyInputSection() {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = MediaQuery.of(context).size.width > 600;
    final isSmallScreen = screenSize.width < 360;
    final fontSize = isSmallScreen ? 16.0 : 18.0; // Increased font size
    final iconSize = isSmallScreen ? 24.0 : 28.0; // Increased icon size

    // Always use portrait layout
    return Row(
      children: [
        // Exchange Rate Field
        Expanded(
          child: TextField(
            controller: _currencyController,
            focusNode: _currencyFocusNode,
            decoration: InputDecoration(
              labelText: _getTranslatedText('exchange_rate'),
              labelStyle: TextStyle(
                fontSize: fontSize - 2,
                color: Colors.blue.shade700,
              ), // Adjusted label with blue color
              hintText:
                  _operationType == 'Purchase'
                      ? _getTranslatedText('enter_buy_rate')
                      : _getTranslatedText('enter_sell_rate'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  12,
                ), // Increased border radius
                borderSide: BorderSide(
                  color: Colors.blue.shade500,
                  width: 2.0,
                ), // Blue border
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.blue.shade300,
                  width: 2.0,
                ), // Light blue when not focused
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.blue.shade700,
                  width: 2.5,
                ), // Darker blue when focused
              ),
              filled: true,
              fillColor: Theme.of(context).inputDecorationTheme.fillColor,
              prefixIcon: Icon(
                Icons.attach_money,
                color: Colors.blue.shade700, // Blue icon color
                size: iconSize,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 16, // Increased vertical padding
                horizontal: 16, // Increased horizontal padding
              ),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            readOnly:
                isTablet && _isNumpadVisible ||
                _selectedCurrency == 'SOM', // Simplified condition
            enabled: _selectedCurrency != 'SOM', // Keep this as is
            showCursor: true, // Always show cursor
            cursorColor: Colors.blue.shade700, // Add visible cursor color
            cursorWidth: 2.0, // Make cursor more visible
            cursorRadius: const Radius.circular(1.0), // Rounded cursor
            onChanged: (_) => _calculateTotal(),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: fontSize),
            onTap: () {
              setState(() {
                _isRateFieldActive = true;
              });
            },
          ),
        ),
        const SizedBox(width: 20), // Increased spacing
        // Quantity Field
        Expanded(
          child: TextField(
            controller: _quantityController,
            focusNode: _quantityFocusNode,
            decoration: InputDecoration(
              labelText: _getTranslatedText('quantity'),
              labelStyle: TextStyle(
                fontSize: fontSize - 2,
                color: Colors.blue.shade700,
              ), // Adjusted label with blue color
              hintText: _getTranslatedText('amount_in_currency', {
                'code': _selectedCurrency,
              }),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  12,
                ), // Increased border radius
                borderSide: BorderSide(
                  color: Colors.blue.shade500,
                  width: 2.0,
                ), // Blue border
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.blue.shade300,
                  width: 2.0,
                ), // Light blue when not focused
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.blue.shade700,
                  width: 2.5,
                ), // Darker blue when focused
              ),
              filled: true,
              fillColor: Theme.of(context).inputDecorationTheme.fillColor,
              prefixIcon: Icon(
                Icons.numbers,
                color: Colors.blue.shade700, // Blue icon color
                size: iconSize,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 16, // Increased vertical padding
                horizontal: 16, // Increased horizontal padding
              ),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            readOnly: isTablet && _isNumpadVisible, // Keep only this condition
            showCursor: true, // Always show cursor
            cursorColor: Colors.blue.shade700, // Add visible cursor color
            cursorWidth: 2.0, // Make cursor more visible
            cursorRadius: const Radius.circular(1.0), // Rounded cursor
            onChanged: (_) => _calculateTotal(),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: fontSize),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Get current date
    final currentDate = DateFormat('dd-MM-yyyy').format(DateTime.now());
    // Check if device is tablet based on screen width
    final isTablet = MediaQuery.of(context).size.width > 600;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date display at the top with numpad toggle on the right (only for tablet)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                // Left spacer that expands to push the date to the center
                Expanded(child: Container()),

                // Centered date
                Container(
                  alignment: Alignment.center,
                  child: Text(
                    currentDate,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Right side with either the button or an expanded spacer
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [if (isTablet) _buildNumpadToggleButton()],
                  ),
                ),
              ],
            ),
          ),

          // Currency selection always at the top
          _buildCurrencySelection(),
          const SizedBox(height: 16),

          // Operation type buttons (Purchase/Sale)
          _buildOperationButtons(),
          const SizedBox(height: 16),

          // Amount input
          _buildAmountInput(isTablet),
          const SizedBox(height: 16),

          // Exchange rate input
          _buildExchangeRateInput(isTablet),
          const SizedBox(height: 16),

          // Total sum display
          _buildTotalDisplay(),
          const SizedBox(height: 20),

          // Finish button
          _buildFinishButton(),

          // Numpad (only for tablet)
          if (isTablet && _isNumpadVisible) ...[
            const SizedBox(height: 16),
            _buildNumpad(),
          ],

          const SizedBox(height: 24),

          // Recent transaction history
          _buildTransactionHistorySection(),
        ],
      ),
    );
  }

  Widget _buildTotalDisplay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _getTranslatedText('total'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.shade200.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            gradient: LinearGradient(
              colors: [Colors.blue.shade50, Colors.blue.shade100],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Text(
            '${_totalSum.toStringAsFixed(2)} SOM',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade700,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildFinishButton() {
    return Container(
      height: 54,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade400, Colors.green.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.green.shade300.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _validateAndSubmit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          _getTranslatedText('finish'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencySelection() {
    // Include all currencies including SOM in the dropdown
    final allCurrencies =
        _currencies
            .map((c) => c.code)
            .where((code) => code != null)
            .cast<String>()
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _getTranslatedText('currency'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: DropdownButton<String>(
            value: _selectedCurrency.isNotEmpty ? _selectedCurrency : null,
            hint: Text(_getTranslatedText('select_currency')),
            isExpanded: true,
            underline: Container(),
            icon: Icon(Icons.arrow_drop_down, color: Colors.blue.shade700),
            items:
                allCurrencies.map((String currency) {
                  return DropdownMenuItem<String>(
                    value: currency,
                    child: Text(currency, style: const TextStyle(fontSize: 16)),
                  );
                }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedCurrency = newValue;
                  _calculateTotal();
                });
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOperationButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _getTranslatedText('operation_type'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient:
                      _operationType == 'Purchase'
                          ? LinearGradient(
                            colors: [
                              Colors.blue.shade400,
                              Colors.blue.shade600,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                          : null,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow:
                      _operationType == 'Purchase'
                          ? [
                            BoxShadow(
                              color: Colors.blue.shade200.withOpacity(0.5),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                          : null,
                ),
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _operationType = 'Purchase';
                      _calculateTotal();
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _operationType == 'Purchase'
                            ? Colors.transparent
                            : Colors.grey.shade200,
                    foregroundColor:
                        _operationType == 'Purchase'
                            ? Colors.white
                            : Colors.black87,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _getTranslatedText('purchase'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient:
                      _operationType == 'Sale'
                          ? LinearGradient(
                            colors: [
                              Colors.blue.shade400,
                              Colors.blue.shade600,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                          : null,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow:
                      _operationType == 'Sale'
                          ? [
                            BoxShadow(
                              color: Colors.blue.shade200.withOpacity(0.5),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                          : null,
                ),
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _operationType = 'Sale';
                      _calculateTotal();
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _operationType == 'Sale'
                            ? Colors.transparent
                            : Colors.grey.shade200,
                    foregroundColor:
                        _operationType == 'Sale'
                            ? Colors.white
                            : Colors.black87,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _getTranslatedText('sale'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAmountInput(bool isTablet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _getTranslatedText('amount_label'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _quantityController,
          focusNode: _quantityFocusNode,
          decoration: InputDecoration(
            filled: true,
            fillColor:
                _isRateFieldActive
                    ? Colors.white
                    : Colors.blue.shade50, // Highlight when active
            hintText: '0.00',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color:
                    _isRateFieldActive
                        ? Colors.grey.shade300
                        : Colors.blue.shade400,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.blue.shade500, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            prefixIcon: Icon(
              Icons.numbers,
              color:
                  _isRateFieldActive
                      ? Colors.blue.shade400
                      : Colors.blue.shade700,
            ),
          ),
          style: const TextStyle(fontSize: 16),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          readOnly: isTablet && _isNumpadVisible,
          showCursor: true,
          cursorColor: Colors.blue.shade700,
          cursorWidth: 2.0,
          cursorRadius: const Radius.circular(1.0),
          onTap: () {
            setState(() {
              _isRateFieldActive = false;
              _quantityFocusNode.requestFocus();

              // Force rebuild after a slight delay
              Future.delayed(const Duration(milliseconds: 50), () {
                if (mounted) setState(() {});
              });
            });
          },
          onChanged: (value) {
            setState(() {
              _calculateTotal();
            });
          },
        ),
      ],
    );
  }

  Widget _buildExchangeRateInput(bool isTablet) {
    // Check if SOM is selected to hide the rate input
    final isSomSelected = _selectedCurrency == 'SOM';

    if (isSomSelected) {
      // When SOM is selected, we don't need the exchange rate field
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _getTranslatedText('exchange_rate'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _currencyController,
          focusNode: _currencyFocusNode,
          decoration: InputDecoration(
            filled: true,
            fillColor:
                _isRateFieldActive
                    ? Colors.blue.shade50
                    : Colors.white, // Highlight when active
            hintText: '0.00',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color:
                    _isRateFieldActive
                        ? Colors.blue.shade400
                        : Colors.grey.shade300,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.blue.shade500, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            prefixIcon: Icon(
              Icons.attach_money,
              color:
                  _isRateFieldActive
                      ? Colors.blue.shade700
                      : Colors.blue.shade400,
            ),
          ),
          style: const TextStyle(fontSize: 16),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          readOnly: isTablet && _isNumpadVisible,
          showCursor: true,
          cursorColor: Colors.blue.shade700,
          cursorWidth: 2.0,
          cursorRadius: const Radius.circular(1.0),
          onTap: () {
            setState(() {
              _isRateFieldActive = true;
              _currencyFocusNode.requestFocus();

              // Force rebuild after a slight delay
              Future.delayed(const Duration(milliseconds: 50), () {
                if (mounted) setState(() {});
              });
            });
          },
          onChanged: (value) {
            setState(() {
              _calculateTotal();
            });
          },
        ),
      ],
    );
  }

  Widget _buildNumpadToggleButton() {
    return ElevatedButton.icon(
      onPressed: () {
        setState(() {
          _isNumpadVisible = !_isNumpadVisible;
        });
      },
      icon: Icon(
        _isNumpadVisible ? Icons.keyboard_hide : Icons.keyboard,
        size: 20,
      ),
      label: Text(
        _isNumpadVisible
            ? _getTranslatedText('hide_numpad')
            : _getTranslatedText('show_numpad'),
        style: const TextStyle(fontSize: 14),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.shade50,
        foregroundColor: Colors.blue.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.blue.shade200),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(color: Colors.grey.shade300),
            gradient: LinearGradient(
              colors: [Colors.white, Colors.grey.shade50],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Numpad grid
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildNumpadButton('7'),
                  const SizedBox(width: 8),
                  _buildNumpadButton('8'),
                  const SizedBox(width: 8),
                  _buildNumpadButton('9'),
                  const SizedBox(width: 8),
                  _buildNumpadButton(
                    '⌫',
                    isFunction: true,
                    color: Colors.blue.shade400,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildNumpadButton('4'),
                  const SizedBox(width: 8),
                  _buildNumpadButton('5'),
                  const SizedBox(width: 8),
                  _buildNumpadButton('6'),
                  const SizedBox(width: 8),
                  _buildNumpadButton(
                    'C',
                    isFunction: true,
                    color: Colors.orange.shade400,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildNumpadButton('1'),
                  const SizedBox(width: 8),
                  _buildNumpadButton('2'),
                  const SizedBox(width: 8),
                  _buildNumpadButton('3'),
                  const SizedBox(width: 8),
                  _buildNumpadButton(
                    '⇄',
                    isFunction: true,
                    color: Colors.red.shade400,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildNumpadButton('.'),
                  const SizedBox(width: 8),
                  _buildNumpadButton('0'),
                  const SizedBox(width: 8),
                  _buildNumpadButton('00'),
                  const SizedBox(width: 8),
                  _buildNumpadButton(
                    '↵',
                    isFunction: true,
                    color: Colors.green.shade400,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Numpad button widget
  Widget _buildNumpadButton(
    String value, {
    bool isFunction = false,
    Color? color,
  }) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: isFunction ? color : Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300.withOpacity(0.5),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(
          color: isFunction ? Colors.transparent : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: GestureDetector(
        onTap: () => _handleNumpadInput(value),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isFunction ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionHistorySection() {
    if (_recentHistory.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey.shade100,
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Center(
          child: Text(
            _getTranslatedText('no_recent_transactions'),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            _getTranslatedText('recent_transactions'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recentHistory.length > 10 ? 10 : _recentHistory.length,
            separatorBuilder:
                (context, index) =>
                    Divider(color: Colors.grey.shade300, height: 1),
            itemBuilder: (context, index) {
              final transaction = _recentHistory[index];
              final formattedTime = DateFormat(
                'HH:mm',
              ).format(transaction.createdAt);

              final isPurchase = transaction.operationType == 'Purchase';

              return Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors:
                        isPurchase
                            ? [Colors.green.shade50, Colors.white]
                            : [Colors.orange.shade50, Colors.white],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Time centered at the top but offset slightly to match rate position
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 50,
                      ), // Align with rate position
                      child: Center(
                        child: Text(
                          formattedTime,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Currency amount, rate, and total with icon on the left
                    Row(
                      children: [
                        // Arrow icon on the left
                        Container(
                          padding: const EdgeInsets.all(4),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color:
                                isPurchase
                                    ? Colors.green.withOpacity(0.1)
                                    : Colors.orange.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPurchase
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: isPurchase ? Colors.green : Colors.orange,
                            size: 14,
                          ),
                        ),

                        // Amount and currency
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${transaction.quantity.toStringAsFixed(2)} ${transaction.currencyCode}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        // Rate centered
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: Column(
                              children: [
                                Text(
                                  _getTranslatedText('rate'),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  transaction.rate.toStringAsFixed(1),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Total
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${transaction.total.toStringAsFixed(2)} SOM',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _currencyController.dispose();
    _quantityController.dispose();
    _currencyFocusNode.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  // Validate inputs and submit transaction
  void _validateAndSubmit() async {
    // Validate currency selection
    if (_selectedCurrency.isEmpty) {
      _showBriefNotification(
        _getTranslatedText('select_currency_first'),
        Colors.red,
      );
      return;
    }

    // Validate quantity input
    final quantity =
        _quantityController.text.isEmpty
            ? 0.0
            : double.tryParse(_quantityController.text);

    if (quantity == null || quantity <= 0) {
      _showBriefNotification(
        _getTranslatedText('invalid_quantity'),
        Colors.red,
      );
      return;
    }

    // Special validation for SOM
    if (_selectedCurrency == 'SOM') {
      // For 'Sale' operation, check if we have enough SOM
      if (_operationType == 'Sale') {
        final somBalance = await _databaseHelper.getCurrencyQuantity('SOM');
        if (quantity > somBalance) {
          _showBriefNotification(
            _getTranslatedText('insufficient_balance', {'code': 'SOM'}),
            Colors.red,
          );
          return;
        }
      }

      try {
        // Create history entry for SOM with rate=1.0
        final historyEntry = HistoryModel(
          currencyCode: 'SOM',
          quantity: quantity,
          rate: 1.0, // Fixed rate for SOM
          total: quantity, // Total equals quantity for SOM
          operationType: _operationType,
          username: currentUser?.username ?? 'unknown',
        );

        // Add to database
        await _databaseHelper.addHistoryEntry(historyEntry);

        // Update SOM quantity
        if (_operationType == 'Purchase') {
          // For purchase, we add to SOM balance
          await _databaseHelper.adjustCurrencyQuantity(
            'SOM',
            quantity,
            true, // Increment
          );
        } else {
          // For sale, we deduct from SOM balance
          await _databaseHelper.adjustCurrencyQuantity(
            'SOM',
            quantity,
            false, // Decrement
          );
        }

        // Show success message
        _showBriefNotification(
          _getTranslatedText('transaction_complete'),
          Colors.green,
        );

        // Reset form
        setState(() {
          _quantityController.text = '';
          _totalSum = 0.0;
        });

        // Reload data
        await _initializeData();

        return; // Exit early, we're done with SOM transaction
      } catch (e) {
        debugPrint('Error processing SOM transaction: $e');
        _showBriefNotification(
          _getTranslatedText('transaction_failed'),
          Colors.red,
        );
        return;
      }
    }

    // Validate rate input for non-SOM currencies
    final rate =
        _currencyController.text.isEmpty
            ? 0.0
            : double.tryParse(_currencyController.text);

    if (rate == null || rate <= 0) {
      _showBriefNotification(_getTranslatedText('invalid_rate'), Colors.red);
      return;
    }

    // Calculate total SOM needed for purchase
    final totalSomNeeded = rate * quantity;

    // Check if we have enough SOM balance for a purchase operation
    if (_operationType == 'Purchase') {
      // Get current SOM balance
      final somBalance = await _databaseHelper.getCurrencyQuantity('SOM');

      if (totalSomNeeded > somBalance) {
        _showBriefNotification(
          _getTranslatedText('insufficient_balance', {'code': 'SOM'}) +
              ' (${somBalance.toStringAsFixed(2)} SOM)',
          Colors.red,
        );
        return;
      }
    }

    // Check if we have enough balance for a sale operation
    if (_operationType == 'Sale') {
      final currencyBalance = await _databaseHelper.getCurrencyQuantity(
        _selectedCurrency,
      );
      if (quantity > currencyBalance) {
        _showBriefNotification(
          _getTranslatedText('insufficient_balance', {
            'code': _selectedCurrency,
          }),
          Colors.red,
        );
        return;
      }
    }

    // All validations passed, proceed with transaction for non-SOM currencies
    try {
      // Create history entry
      final historyEntry = HistoryModel(
        currencyCode: _selectedCurrency,
        quantity: quantity,
        rate: rate!,
        total: _totalSum,
        operationType: _operationType,
        username: currentUser?.username ?? 'unknown',
      );

      // Add to database
      await _databaseHelper.addHistoryEntry(historyEntry);

      // Update currency quantities
      if (_operationType == 'Purchase') {
        // For purchase, we add to the currency and deduct from SOM
        await _databaseHelper.adjustCurrencyQuantity(
          _selectedCurrency,
          quantity,
          true,
        );

        // Deduct from SOM
        await _databaseHelper.adjustCurrencyQuantity('SOM', _totalSum, false);
      } else {
        // For sale, we deduct from the currency and add to SOM
        await _databaseHelper.adjustCurrencyQuantity(
          _selectedCurrency,
          quantity,
          false,
        );

        // Add to SOM
        await _databaseHelper.adjustCurrencyQuantity('SOM', _totalSum, true);
      }

      // Show success message
      _showBriefNotification(
        _getTranslatedText('transaction_successful'),
        Colors.green,
      );

      // Reset form
      setState(() {
        _currencyController.text = '';
        _quantityController.text = '';
        _totalSum = 0.0;
      });

      // Reload data
      await _initializeData();
    } catch (e) {
      debugPrint('Error processing transaction: $e');
      _showBriefNotification(
        _getTranslatedText('transaction_failed'),
        Colors.red,
      );
    }
  }

  // Handle numpad input
  void _handleNumpadInput(String value) {
    final controller =
        _isRateFieldActive ? _currencyController : _quantityController;
    final focusNode =
        _isRateFieldActive ? _currencyFocusNode : _quantityFocusNode;

    // Request focus on the current field
    focusNode.requestFocus();

    // Set cursor position to the end if it's not already set
    if (controller.selection.baseOffset < 0 ||
        controller.selection.baseOffset > controller.text.length) {
      controller.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length),
      );
    }

    final currentText = controller.text;
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
    } else if (value == 'C') {
      // Handle clear button
      controller.text = '';
      controller.selection = TextSelection.collapsed(offset: 0);
    } else if (value == '⇄') {
      // Handle swap button - switch between rate and amount fields
      setState(() {
        _isRateFieldActive = !_isRateFieldActive;

        // Immediately request focus on the new active field
        if (_isRateFieldActive) {
          _currencyFocusNode.requestFocus();
        } else {
          _quantityFocusNode.requestFocus();
        }
      });

      // Add a slight delay to ensure UI updates properly
      Future.delayed(const Duration(milliseconds: 50), () {
        setState(() {}); // Force rebuild
      });

      return; // Early return to avoid calling _calculateTotal
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
          newText =
              currentText.substring(0, selectionStart) +
              '00' +
              currentText.substring(selectionEnd);
        } else {
          // Insert at cursor
          newText =
              currentText.substring(0, selectionStart) +
              '00' +
              currentText.substring(selectionEnd);
        }

        controller.text = newText;
        controller.selection = TextSelection.collapsed(
          offset: selectionStart + 2,
        );
      } else if (currentText.isEmpty) {
        // Just insert a single 0 if the field is empty
        controller.text = '0';
        controller.selection = TextSelection.collapsed(offset: 1);
      }
    } else if (value == '↵') {
      // Handle enter button - submit the transaction
      _validateAndSubmit();
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
  Key _historyScreenKey = UniqueKey();

  late List<Widget> _pages;
  late List<BottomNavigationBarItem> _navigationItems;

  @override
  void initState() {
    super.initState();
    _initPages();
    _initNavigationItems();
  }

  void _initPages() {
    final bool isAdmin = currentUser?.role == 'admin';

    _pages = [CurrencyConverterCore(key: _currencyConverterCoreKey)];

    if (isAdmin) {
      _pages.add(HistoryScreen(key: _historyScreenKey));
      _pages.add(StatisticsScreen(key: UniqueKey()));
      _pages.add(AnalyticsScreen(key: UniqueKey()));
    }

    _pages.add(const SettingsScreen());
  }

  void _initNavigationItems() {
    final bool isAdmin = currentUser?.role == 'admin';

    _navigationItems = [
      BottomNavigationBarItem(
        icon: Icon(Icons.currency_exchange, size: 28),
        label: '',
        activeIcon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade100, Colors.blue.shade200],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.currency_exchange, size: 28),
        ),
      ),
    ];

    if (isAdmin) {
      _navigationItems.add(
        BottomNavigationBarItem(
          icon: Icon(Icons.history, size: 28),
          label: '',
          activeIcon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade100, Colors.blue.shade200],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.history, size: 28),
          ),
        ),
      );

      _navigationItems.add(
        BottomNavigationBarItem(
          icon: Icon(Icons.analytics, size: 28),
          label: '',
          activeIcon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade100, Colors.blue.shade200],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.analytics, size: 28),
          ),
        ),
      );

      _navigationItems.add(
        BottomNavigationBarItem(
          icon: Icon(Icons.pie_chart, size: 28),
          label: '',
          activeIcon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade100, Colors.blue.shade200],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.pie_chart, size: 28),
          ),
        ),
      );
    }

    _navigationItems.add(
      BottomNavigationBarItem(
        icon: Icon(Icons.settings, size: 28),
        label: '',
        activeIcon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade100, Colors.blue.shade200],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.settings, size: 28),
        ),
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;

      if (index == 1) {
        _historyScreenKey = UniqueKey();
      }

      if (index == 0) {
        _loadCurrencyData();
      }
    });
  }

  void _loadCurrencyData() {
    _currencyConverterCoreKey.currentState?._loadCurrencies();
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const LoginScreen();
    }

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.blue.shade50,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: _buildCurrentPage(),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, Colors.blue.shade50],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.shade100,
                spreadRadius: 2,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BottomNavigationBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: Colors.blue.shade700,
              unselectedItemColor: Colors.grey.shade400,
              showSelectedLabels: false,
              showUnselectedLabels: false,
              type: BottomNavigationBarType.fixed,
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              iconSize: 32,
              items: _navigationItems,
              mouseCursor: SystemMouseCursors.click,
              unselectedFontSize: 0,
              selectedFontSize: 0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentPage() {
    return _pages[_selectedIndex];
  }

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
}

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
  Key _historyScreenKey = UniqueKey();

  late List<Widget> _pages;
  late List<NavigationRailDestination> _navigationDestinations;

  @override
  void initState() {
    super.initState();
    _initPages();
    _initNavigationDestinations();
  }

  void _initPages() {
    final bool isAdmin = currentUser?.role == 'admin';

    _pages = [
      CurrencyConverterCore(key: _currencyConverterCoreKey, isWideLayout: true),
    ];

    if (isAdmin) {
      _pages.add(HistoryScreen(key: _historyScreenKey));
      _pages.add(StatisticsScreen(key: UniqueKey()));
      _pages.add(AnalyticsScreen(key: UniqueKey()));
    }

    _pages.add(const SettingsScreen());
  }

  void _initNavigationDestinations() {
    final bool isAdmin = currentUser?.role == 'admin';

    _navigationDestinations = [
      const NavigationRailDestination(
        icon: Icon(Icons.currency_exchange, size: 28),
        label: Text(''),
      ),
    ];

    if (isAdmin) {
      _navigationDestinations.add(
        const NavigationRailDestination(
          icon: Icon(Icons.history, size: 28),
          label: Text(''),
        ),
      );

      _navigationDestinations.addAll([
        const NavigationRailDestination(
          icon: Icon(Icons.analytics, size: 28),
          label: Text(''),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.pie_chart, size: 28),
          label: Text(''),
        ),
      ]);
    }

    _navigationDestinations.add(
      const NavigationRailDestination(
        icon: Icon(Icons.settings, size: 28),
        label: Text(''),
      ),
    );
  }

  void _onDestinationSelected(int index) {
    setState(() {
      _selectedIndex = index;

      if (index == 1) {
        _historyScreenKey = UniqueKey();
      }

      if (index == 0) {
        _loadCurrencyData();
      }
    });
  }

  void _loadCurrencyData() {
    _currencyConverterCoreKey.currentState?._loadCurrencies();
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const LoginScreen();
    }

    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      body: SafeArea(child: _buildPortraitLayout()),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.blue.shade50],
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.shade100.withOpacity(0.5),
                blurRadius: 12,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BottomNavigationBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: Colors.blue.shade700,
              unselectedItemColor: Colors.grey.shade400,
              showSelectedLabels: false,
              showUnselectedLabels: false,
              type: BottomNavigationBarType.fixed,
              currentIndex: _selectedIndex,
              onTap: _onDestinationSelected,
              iconSize: 36,
              items:
                  _navigationDestinations.map((destination) {
                    return BottomNavigationBarItem(
                      icon: destination.icon,
                      label: '',
                      activeIcon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.shade100,
                              Colors.blue.shade200,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: destination.icon,
                      ),
                    );
                  }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitLayout() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
      child: _pages[_selectedIndex],
    );
  }

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
}

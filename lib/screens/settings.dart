import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';
import '../db_helper.dart';
import '../models/currency.dart';
import '../models/user.dart';
import '../screens/login_screen.dart';
import '../widgets/language_selector.dart';
import '../providers/language_provider.dart';
import 'package:excel/excel.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:media_scanner/media_scanner.dart';
import '../services/export_service.dart';
import '../providers/theme_provider.dart';
import 'package:flutter/services.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ExportService _exportService = ExportService();
  List<CurrencyModel> _currencies = [];
  List<UserModel> _users = [];
  final TextEditingController _newCurrencyCodeController =
      TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _roleController = TextEditingController();
  bool _showCurrencyManagement = false;
  bool _showUserManagement = false;
  bool _showExportSection = false;
  Timer? _autoRefreshTimer;
  bool _isAdmin = false;
  final _currencyController = TextEditingController();
  final TextEditingController _somController = TextEditingController();
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  final TextEditingController _defaultBuyRateController =
      TextEditingController();
  final TextEditingController _defaultSellRateController =
      TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;

  // Add new property for export
  String _selectedFormat = 'excel';
  String _exportType = 'history'; // Add export type variable

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    // Restore orientation settings when widget is disposed
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _newCurrencyCodeController.dispose();
    _quantityController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _roleController.dispose();
    _currencyController.dispose();
    _somController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _defaultBuyRateController.dispose();
    _defaultSellRateController.dispose();
    super.dispose();
  }

  Future<void> _initScreen() async {
    setState(() { _isLoading = true; });
    try {
      // Use batched loading to get both currencies and users in one request
      final batchData = await _dbHelper.batchLoad();
      
      if (mounted) {
        setState(() {
          // Process currencies
          _currencies = (batchData['currencies'] as List<CurrencyModel>).map((currency) {
            return CurrencyModel(
              id: currency.id,
              code: currency.code,
              quantity: 
                currency.quantity is double
                  ? currency.quantity
                  : double.tryParse(currency.quantity.toString()) ?? 0.0,
              updatedAt: currency.updatedAt,
              defaultBuyRate: currency.defaultBuyRate,
              defaultSellRate: currency.defaultSellRate,
            );
          }).toList();
          
          // Process users
          _users = batchData['users'] as List<UserModel>;
          
          // Check admin status
          _isAdmin = currentUser?.role == 'admin';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error in _initScreen: $e');
      // Fall back to individual loading if batch loading fails
      _loadCurrencies();
      _loadUsers();
      _checkIsAdmin();
    }
  }

  void _checkIsAdmin() {
    setState(() {
      _isAdmin = currentUser?.role == 'admin';
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when the screen becomes visible, but avoid redundant loading
    if (_showCurrencyManagement) {
      // Only start auto-refresh if not already running
      if (_autoRefreshTimer == null || !_autoRefreshTimer!.isActive) {
        _loadCurrenciesWithIndicator();
        _startAutoRefresh();
      }
    } else if (_showUserManagement) {
      if (_autoRefreshTimer == null || !_autoRefreshTimer!.isActive) {
        _loadUsersWithIndicator();
        _startAutoRefresh();
      }
    } else {
      // Load both currencies and users when first navigating to settings
      _loadCurrenciesWithIndicator();
      _loadUsersWithIndicator();
    }
  }

  void _startAutoRefresh() {
    // Cancel any existing timer
    _autoRefreshTimer?.cancel();

    // Set up a timer to refresh currencies less frequently - every 10 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      if (_showCurrencyManagement) {
        _loadCurrenciesWithIndicator();
      } else if (_showUserManagement) {
        _loadUsersWithIndicator();
      } else {
        timer.cancel();
      }
    });
  }

  // New method with loading indicator
  Future<void> _loadCurrenciesWithIndicator() async {
    try {
      setState(() { _isLoading = true; });
      final currencies = await _dbHelper.getAllCurrencies();
      if (!mounted) return;
      setState(() {
        // Ensure proper quantity parsing for all currencies
        _currencies = currencies.map((currency) {
          // Ensure quantity is properly parsed as double
          return CurrencyModel(
            id: currency.id,
            code: currency.code,
            quantity:
                currency.quantity is double
                    ? currency.quantity
                    : double.tryParse(currency.quantity.toString()) ?? 0.0,
            updatedAt: currency.updatedAt,
            defaultBuyRate: currency.defaultBuyRate,
            defaultSellRate: currency.defaultSellRate,
          );
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading currencies: $e');
      if (mounted) setState(() { _isLoading = false; });
    }
  }
  
  // New method with loading indicator
  Future<void> _loadUsersWithIndicator() async {
    try {
      setState(() { _isLoading = true; });
      final users = await _dbHelper.getAllUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading users: $e');
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _loadCurrencies() async {
    if (mounted) {
      await _loadCurrenciesWithIndicator();
    }
  }
  
  Future<void> _loadUsers() async {
    if (mounted) {
      await _loadUsersWithIndicator();
    }
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

  Future<void> _resetAllData() async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(_getTranslatedText('reset_all_data')),
            content: Text(
              _getTranslatedText('reset_warning'),
              style: const TextStyle(color: Colors.red),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(_getTranslatedText('cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: Text(
                  _getTranslatedText('reset_everything'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => const Center(child: CircularProgressIndicator()),
        );

        // Perform the reset
        await _dbHelper.resetAllData();

        // Close loading indicator
        if (!mounted) return;
        Navigator.of(context).pop();

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getTranslatedText('reset_success')),
            backgroundColor: Colors.green,
          ),
        );

        // Refresh the data
        await _loadCurrencies();
        await _loadUsers();

        // Return to main settings page
        setState(() {
          _showCurrencyManagement = false;
          _showUserManagement = false;
        });
      } catch (e) {
        if (!mounted) return;
        Navigator.of(context).pop();

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_getTranslatedText('error')}: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showAddCurrencyDialog(BuildContext context) async {
    _newCurrencyCodeController.clear();
    _quantityController.text = "0"; // Set default value to 0
    _defaultBuyRateController.text = "0.0";
    _defaultSellRateController.text = "0.0";

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            _getTranslatedText('add_new_currency'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _newCurrencyCodeController,
                decoration: InputDecoration(
                  labelText: _getTranslatedText('currency_code'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                maxLength: 3,
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _quantityController,
                decoration: InputDecoration(
                  labelText: _getTranslatedText('initial_quantity'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _defaultBuyRateController,
                decoration: InputDecoration(
                  labelText: _getTranslatedText('default_buy_rate'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _defaultSellRateController,
                decoration: InputDecoration(
                  labelText: _getTranslatedText('default_sell_rate'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                _getTranslatedText('cancel'),
                style: const TextStyle(fontSize: 16),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_newCurrencyCodeController.text.isNotEmpty &&
                    _quantityController.text.isNotEmpty &&
                    _defaultBuyRateController.text.isNotEmpty &&
                    _defaultSellRateController.text.isNotEmpty) {
                  try {
                    final newCurrency = CurrencyModel(
                      code: _newCurrencyCodeController.text.toUpperCase(),
                      quantity: double.parse(_quantityController.text),
                      defaultBuyRate: double.parse(
                        _defaultBuyRateController.text,
                      ),
                      defaultSellRate: double.parse(
                        _defaultSellRateController.text,
                      ),
                    );

                    await _dbHelper.insertCurrency(newCurrency);
                    await _loadCurrencies();
                    Navigator.pop(context);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${_getTranslatedText('error')}: ${e.toString()}',
                        ),
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _getTranslatedText('add'),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddSomDialog() async {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              _getTranslatedText('add_som'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _getTranslatedText('som_amount'),
                  prefixIcon: const Icon(Icons.attach_money, size: 24),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return _getTranslatedText('enter_amount');
                  }
                  if (double.tryParse(value) == null) {
                    return _getTranslatedText('enter_valid_number');
                  }
                  return null;
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  _getTranslatedText('cancel'),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    final amount = double.parse(amountController.text);
                    try {
                      await _dbHelper.addToSomBalance(amount);
                      Navigator.pop(context);
                      _showSuccessNotification(
                        _getTranslatedText('som_added_success', {
                          'amount': amount.toString(),
                        }),
                      );
                      // Refresh currencies to show updated SOM balance
                      _loadCurrencies();
                    } catch (e) {
                      Navigator.pop(context);
                      _showErrorNotification(
                        _getTranslatedText('som_add_error', {
                          'error': e.toString(),
                        }),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _getTranslatedText('add'),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
    );
  }

  void _showSuccessNotification(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorNotification(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showAddUserDialog(BuildContext context) async {
    _usernameController.clear();
    _passwordController.clear();
    _roleController.text = 'user'; // Default role

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            _getTranslatedText('add_new_user'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: _getTranslatedText('username'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: _getTranslatedText('password'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: 'user',
                decoration: InputDecoration(
                  labelText: _getTranslatedText('role'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'user',
                    child: Text(
                      _getTranslatedText('user'),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text(
                      _getTranslatedText('admin'),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _roleController.text = value;
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                _getTranslatedText('cancel'),
                style: const TextStyle(fontSize: 16),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_usernameController.text.isNotEmpty &&
                    _passwordController.text.isNotEmpty) {
                  try {
                    // Check if username already exists
                    final exists = await _dbHelper.usernameExists(
                      _usernameController.text,
                    );
                    if (exists) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_getTranslatedText('username_exists')),
                        ),
                      );
                      return;
                    }

                    final newUser = UserModel(
                      username: _usernameController.text,
                      password: _passwordController.text,
                      role: _roleController.text,
                    );

                    await _dbHelper.createUser(newUser);
                    await _loadUsers();
                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _getTranslatedText('user_created'),
                        ),
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${_getTranslatedText('error')}: ${e.toString()}',
                        ),
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _getTranslatedText('add'),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteCurrency(int? id, String code) async {
    if (id == null || code == 'SOM') return;

    // Show confirmation dialog
    bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Confirm Delete'),
            content: Text('Are you sure you want to delete currency $code?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        await _dbHelper.deleteCurrency(id);
        await _loadCurrencies();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Currency $code deleted')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting currency: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _deleteUser(int? id, String username) async {
    if (id == null) return;

    // Show confirmation dialog
    bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Confirm Delete'),
            content: Text('Are you sure you want to delete user $username?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        await _dbHelper.deleteUser(id);
        await _loadUsers();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('User $username deleted')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting user: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Primary content based on what's selected
              if (_showCurrencyManagement)
                _buildCurrencyManagement()
              else if (_showUserManagement)
                _buildUserManagement()
              else if (_showExportSection)
                _buildExportSection()
              else
                _buildSettings(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettings() {
    // Check if user is admin
    final bool isAdmin = currentUser?.role == 'admin';
    final themeProvider = Provider.of<ThemeProvider>(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 12.0),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.grey.shade300, width: 1.5),
            ),
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 8.0,
                  ),
                  title: Text(
                    _getTranslatedText('language'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  leading: Icon(
                    Icons.language,
                    color: Theme.of(context).primaryColor,
                    size: 28,
                  ),
                  trailing: const LanguageSelector(),
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 8.0,
                  ),
                  title: Text(
                    _getTranslatedText('theme'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  leading: Icon(
                    themeProvider.isDarkMode
                        ? Icons.dark_mode
                        : Icons.light_mode,
                    color: Theme.of(context).primaryColor,
                    size: 28,
                  ),
                  trailing: Switch(
                    value: themeProvider.isDarkMode,
                    onChanged: (value) {
                      themeProvider.toggleTheme();
                    },
                    activeColor: Theme.of(context).primaryColor,
                  ),
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 8.0,
                  ),
                  title: Text(
                    _getTranslatedText('currency_settings'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  leading: Icon(
                    Icons.currency_exchange,
                    color: Theme.of(context).primaryColor,
                    size: 28,
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 20),
                  onTap: _navigateToCurrencyManagement,
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 8.0,
                  ),
                  title: Text(
                    _getTranslatedText('export_data'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  leading: Icon(
                    Icons.file_download,
                    color: Theme.of(context).primaryColor,
                    size: 28,
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 20),
                  onTap: () {
                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);
                    setState(() {
                      _startDate = today;
                      _endDate = now;
                      _startDateController.text = DateFormat(
                        'dd-MM-yyyy',
                      ).format(today);
                      _endDateController.text = DateFormat(
                        'dd-MM-yyyy',
                      ).format(now);
                      _showExportSection = true;
                      _showCurrencyManagement = false;
                      _showUserManagement = false;
                    });
                  },
                ),
                if (isAdmin) ...[
                  Divider(height: 1, color: Colors.grey.shade200),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 8.0,
                    ),
                    title: Text(
                      _getTranslatedText('user_settings'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    leading: Icon(
                      Icons.people,
                      color: Theme.of(context).primaryColor,
                      size: 28,
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 20),
                    onTap: () {
                      setState(() {
                        _showUserManagement = true;
                        _showCurrencyManagement = false;
                        _showExportSection = false;
                      });
                    },
                  ),
                ],
                if (isAdmin) ...[
                  Divider(height: 1, color: Colors.grey.shade200),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 8.0,
                    ),
                    title: Text(
                      _getTranslatedText('reset_all_data'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    leading: const Icon(
                      Icons.delete_forever,
                      color: Colors.red,
                      size: 28,
                    ),
                    onTap: _resetAllData,
                  ),
                ],
                Divider(height: 1, color: Colors.grey.shade200),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 8.0,
                  ),
                  title: Text(
                    _getTranslatedText('logout'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  leading: const Icon(
                    Icons.logout,
                    color: Colors.red,
                    size: 28,
                  ),
                  onTap: _logout,
                ),
              ],
            ),
          ),

          // Watermark / Made by section
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: Column(
              children: [
                Divider(color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.copyright,
                      size: 16,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Made by Boz Zat",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "v1.0.0 online",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Logout function
  Future<void> _logout() async {
    // Show confirmation dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(_getTranslatedText('logout')),
            content: Text(_getTranslatedText('logout_confirmation')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(_getTranslatedText('cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  _getTranslatedText('logout'),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (shouldLogout == true) {
      try {
        // Clear remember me if enabled
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('remember_me', false);

        // Clear the current user
        currentUser = null;

        if (!mounted) return;

        // Navigate back to login screen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false, // Remove all previous routes
        );
      } catch (e) {
        debugPrint('Error during logout: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_getTranslatedText('logout_error'))),
        );
      }
    }
  }

  Future<void> _navigateToCurrencyManagement() async {
    setState(() {
      _showCurrencyManagement = true;
      _showUserManagement = false;
      _showExportSection = false;
      _startAutoRefresh();
    });
  }

  Widget _buildCurrencyManagement() {
    return OrientationBuilder(
      builder: (context, orientation) {
        // Force portrait orientation
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);

        return SizedBox(
          height: MediaQuery.of(context).size.height - 200,
          child: Column(
            children: [
              // Header section
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 16.0,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 28),
                      onPressed: () {
                        setState(() {
                          _showCurrencyManagement = false;
                          _autoRefreshTimer?.cancel();
                        });
                        // Restore orientation settings when leaving
                        SystemChrome.setPreferredOrientations([
                          DeviceOrientation.portraitUp,
                          DeviceOrientation.portraitDown,
                          DeviceOrientation.landscapeLeft,
                          DeviceOrientation.landscapeRight,
                        ]);
                      },
                    ),
                    const SizedBox(width: 16),
                    Text(
                      _getTranslatedText('currency_management'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Add loading indicator
                    if (_isLoading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),

              // Add SOM button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _showAddSomDialog,
                    icon: const Icon(Icons.add, size: 24),
                    label: Text(
                      _getTranslatedText('add_som'),
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade100,
                      foregroundColor: Colors.blue.shade800,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Currency list
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadCurrencies,
                  child:
                      _currencies.isEmpty
                          ? const Center(
                              child: Text(
                                'No currencies available',
                                style: TextStyle(fontSize: 18, color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _currencies.length,
                              itemBuilder: (context, index) {
                                final currency = _currencies[index];
                                // Format quantity with 2 decimal places
                                final formattedQuantity = NumberFormat.currency(
                                  decimalDigits: 2,
                                  symbol: '',
                                ).format(currency.quantity);

                                // Use different style for SOM currency
                                final bool isSom = currency.code == 'SOM';

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  color: isSom ? Colors.blue.shade50 : null,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    title: Text(
                                      currency.code ?? '',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: isSom ? Colors.blue.shade800 : null,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        '${_getTranslatedText('quantity')}: $formattedQuantity\n'
                                        '${_getTranslatedText('last_updated')}: ${DateFormat('dd-MM-yy HH:mm').format(currency.updatedAt)}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!isSom) ...[
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit,
                                              color: Colors.blue,
                                              size: 26,
                                            ),
                                            onPressed:
                                                () =>
                                                    _showEditCurrencyDialog(currency),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              color: Colors.red,
                                              size: 26,
                                            ),
                                            onPressed:
                                                () => _deleteCurrency(
                                                  currency.id,
                                                  currency.code ?? '',
                                                ),
                                          ),
                                        ] else
                                          const Icon(
                                            Icons.payments,
                                            color: Colors.blue,
                                            size: 26,
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ),

              // Add New Currency button
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: ElevatedButton(
                  onPressed: () => _showAddCurrencyDialog(context),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _getTranslatedText('add_new_currency'),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserManagement() {
    return SizedBox(
      height: MediaQuery.of(context).size.height - 200,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 16.0,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 28),
                  onPressed: () {
                    setState(() {
                      _showUserManagement = false;
                      _autoRefreshTimer?.cancel();
                    });
                  },
                ),
                const SizedBox(width: 16),
                Text(
                  _getTranslatedText('user_management'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Add loading indicator
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                const SizedBox(width: 12),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadUsers,
              child:
                  _users.isEmpty
                      ? Center(
                        child: Text(
                          _getTranslatedText('no_users_available'),
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                      )
                      : ListView.builder(
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor:
                                    user.role == 'admin'
                                        ? Colors.orange
                                        : Colors.blue,
                                child: Icon(
                                  user.role == 'admin'
                                      ? Icons.admin_panel_settings
                                      : Icons.person,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              title: Text(
                                user.username,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  '${_getTranslatedText('role')}: ${_getTranslatedText(user.role)}\n'
                                  '${_getTranslatedText('created')}: ${DateFormat('dd-MM-yy').format(user.createdAt)}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                  size: 26,
                                ),
                                onPressed:
                                    () => _deleteUser(user.id, user.username),
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: () => _showAddUserDialog(context),
              icon: const Icon(Icons.person_add),
              label: Text(
                _getTranslatedText('add_new_user'),
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                minimumSize: const Size(double.infinity, 56),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportSection() {
    return SizedBox(
      height: MediaQuery.of(context).size.height - 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button and title
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 16.0,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 28),
                  onPressed: () {
                    setState(() {
                      _showExportSection = false;
                    });
                  },
                ),
                const SizedBox(width: 16),
                Text(
                  _getTranslatedText('export_data'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Date range and export settings
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getTranslatedText('select_date_range'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Date Range Selection
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _startDateController,
                            decoration: InputDecoration(
                              labelText: _getTranslatedText('start_date'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              suffixIcon: const Icon(Icons.calendar_today),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                            readOnly: true,
                            onTap: () => _selectDate(true),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: _endDateController,
                            decoration: InputDecoration(
                              labelText: _getTranslatedText('end_date'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              suffixIcon: const Icon(Icons.calendar_today),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                            readOnly: true,
                            onTap: () => _selectDate(false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    Text(
                      _getTranslatedText('export_format'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Format Selection
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: Text(
                              _getTranslatedText('excel'),
                              style: const TextStyle(fontSize: 16),
                            ),
                            value: 'excel',
                            groupValue: _selectedFormat,
                            onChanged: (value) {
                              setState(() {
                                _selectedFormat = value!;
                              });
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: Text(
                              _getTranslatedText('pdf'),
                              style: const TextStyle(fontSize: 16),
                            ),
                            value: 'pdf',
                            groupValue: _selectedFormat,
                            onChanged: (value) {
                              setState(() {
                                _selectedFormat = value!;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    Text(
                      _getTranslatedText('export_options'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Export Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _exportType = 'history';
                              });
                              _exportData();
                            },
                            icon: const Icon(Icons.history, size: 24),
                            label: Text(
                              _getTranslatedText('export_history'),
                              style: const TextStyle(fontSize: 14),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _exportType = 'statistics';
                              });
                              _exportData();
                            },
                            icon: const Icon(Icons.analytics, size: 24),
                            label: Text(
                              _getTranslatedText('export_statistics'),
                              style: const TextStyle(fontSize: 14),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
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

  // Date selection method
  Future<void> _selectDate(bool isStartDate) async {
    final initialDate =
        isStartDate ? _startDate ?? DateTime.now() : _endDate ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          _startDateController.text = DateFormat('dd-MM-yyyy').format(picked);
        } else {
          _endDate = picked;
          _endDateController.text = DateFormat('dd-MM-yyyy').format(picked);
        }
      });
    }
  }

  // Method to export data
  Future<void> _exportData() async {
    try {
      // Check start and end dates
      if (_startDate == null || _endDate == null) {
        _showSnackBar(_getTranslatedText('select_date_range_error'));
        return;
      }

      if (_endDate!.isBefore(_startDate!)) {
        _showSnackBar(_getTranslatedText('invalid_date_range'));
        return;
      }

      // Get the Documents directory
      final directory = Directory('/storage/emulated/0/Documents');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final fileName =
          '${_exportType}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';
      String filePath;

      if (_selectedFormat == 'excel') {
        filePath = await _exportToExcel(directory, fileName);
      } else {
        filePath = await _exportToPdf(directory, fileName);
      }

      // Trigger media scan
      await MediaScanner.loadMedia(path: filePath);
      _showSnackBar(_getTranslatedText('export_success'));
    } catch (e) {
      _showSnackBar('${_getTranslatedText('export_error')}: ${e.toString()}');
    }
  }

  Future<String> _exportToExcel(Directory directory, String fileName) async {
    final excel = Excel.createExcel();

    if (fileName.contains('history')) {
      await _exportHistoryData(excel);
    } else {
      await _exportAnalyticsData(excel);
    }

    final filePath = '${directory.path}/${fileName}.xlsx';
    final fileBytes = excel.encode();
    if (fileBytes == null) {
      throw Exception('Failed to generate Excel file');
    }

    final file = File(filePath);
    await file.writeAsBytes(fileBytes);
    return filePath;
  }

  Future<String> _exportToPdf(Directory directory, String fileName) async {
    final pdf = pw.Document();
    late final String filePath;
    late final File file;

    try {
      if (fileName.contains('history')) {
        // Get history data
        final historyData = await _dbHelper.getFilteredHistoryByDate(
          fromDate: _startDate!,
          toDate: _endDate!,
        );

        // Create PDF content for history
        pdf.addPage(
          pw.MultiPage(
            build:
                (context) => [
                  pw.Header(
                    level: 0,
                    child: pw.Text('Transaction History Report'),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    'Period: ${DateFormat('dd-MM-yyyy').format(_startDate!)} to ${DateFormat('dd-MM-yyyy').format(_endDate!)}',
                  ),
                  pw.SizedBox(height: 20),
                  pw.Table.fromTextArray(
                    headers: [
                      'Date',
                      'Currency',
                      'Operation',
                      'Rate',
                      'Quantity',
                      'Total',
                    ],
                    data:
                        historyData
                            .map(
                              (entry) => [
                                DateFormat(
                                  'dd-MM-yyyy HH:mm',
                                ).format(entry.createdAt),
                                entry.currencyCode,
                                entry.operationType,
                                entry.rate.toStringAsFixed(2),
                                entry.quantity.toStringAsFixed(2),
                                entry.total.toStringAsFixed(2),
                              ],
                            )
                            .toList(),
                  ),
                ],
          ),
        );
      } else {
        // Get analytics data
        final analyticsData = await _dbHelper.calculateAnalytics(
          startDate: _startDate,
          endDate: _endDate,
        );

        // Create PDF content for statistics
        pdf.addPage(
          pw.MultiPage(
            build:
                (context) => [
                  pw.Header(
                    level: 0,
                    child: pw.Text('Currency Statistics Report'),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    'Period: ${DateFormat('dd-MM-yyyy').format(_startDate!)} to ${DateFormat('dd-MM-yyyy').format(_endDate!)}',
                  ),
                  pw.SizedBox(height: 20),
                  pw.Table.fromTextArray(
                    headers: [
                      'Currency',
                      'Avg Purchase Rate',
                      'Total Purchased',
                      'Purchase Amount',
                      'Avg Sale Rate',
                      'Total Sold',
                      'Sale Amount',
                      'Current Quantity',
                      'Profit',
                    ],
                    data:
                        (analyticsData['currency_stats'] as List)
                            .map(
                              (stat) => [
                                stat['currency'] as String,
                                (stat['avg_purchase_rate'] as double)
                                    .toStringAsFixed(2),
                                (stat['total_purchased'] as double)
                                    .toStringAsFixed(2),
                                (stat['total_purchase_amount'] as double)
                                    .toStringAsFixed(2),
                                (stat['avg_sale_rate'] as double)
                                    .toStringAsFixed(2),
                                (stat['total_sold'] as double).toStringAsFixed(
                                  2,
                                ),
                                (stat['total_sale_amount'] as double)
                                    .toStringAsFixed(2),
                                (stat['current_quantity'] as double)
                                    .toStringAsFixed(2),
                                (stat['profit'] as double).toStringAsFixed(2),
                              ],
                            )
                            .toList(),
                  ),
                ],
          ),
        );
      }

      filePath = '${directory.path}/${fileName}.pdf';
      file = File(filePath);

      // Generate a unique filename if file exists
      int counter = 1;
      String newFilePath = filePath;
      File newFile = file;

      while (await newFile.exists()) {
        final newFileName = '${fileName}_${counter}';
        newFilePath = '${directory.path}/${newFileName}.pdf';
        newFile = File(newFilePath);
        counter++;
      }

      // Write the PDF file
      final bytes = await pdf.save();
      await newFile.writeAsBytes(bytes, flush: true);

      return newFilePath;
    } catch (e) {
      debugPrint('Error exporting PDF: $e');
      rethrow;
    }
  }

  // Export history data
  Future<void> _exportHistoryData(Excel excel) async {
    // Create a sheet for history data
    final sheet = excel['History'];

    // Add headers
    final headers = [
      'Date',
      'Currency',
      'Operation',
      'Rate',
      'Quantity',
      'Total',
    ];
    for (var i = 0; i < headers.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = headers[i];
    }

    // Get history data
    final historyData = await _dbHelper.getFilteredHistoryByDate(
      fromDate: _startDate!,
      toDate: _endDate!,
    );

    // Add data rows
    for (var i = 0; i < historyData.length; i++) {
      final entry = historyData[i];
      final rowIndex = i + 1; // +1 because headers are at row 0

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
          .value = DateFormat('dd-MM-yyyy HH:mm').format(entry.createdAt);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
          .value = entry.currencyCode;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex))
          .value = entry.operationType;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex))
          .value = entry.rate;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex))
          .value = entry.quantity;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex))
          .value = entry.total;
    }

    // Set column widths
    for (var i = 0; i < headers.length; i++) {
      sheet.setColWidth(i, 20.0);
    }
  }

  // Export analytics data
  Future<void> _exportAnalyticsData(Excel excel) async {
    // Get analytics data
    final analyticsData = await _dbHelper.calculateAnalytics(
      startDate: _startDate,
      endDate: _endDate,
    );

    // Delete all existing sheets
    excel.delete('Sheet1');

    // Create currencies sheet
    final currencySheet = excel['Currency Statistics'];

    // Add headers
    final headers = [
      'Currency',
      'Avg Purchase Rate',
      'Total Purchased',
      'Purchase Amount',
      'Avg Sale Rate',
      'Total Sold',
      'Sale Amount',
      'Current Quantity',
      'Profit',
    ];

    for (var i = 0; i < headers.length; i++) {
      currencySheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = headers[i];
    }

    // Add data rows
    final currencyStats = analyticsData['currency_stats'] as List;
    for (var i = 0; i < currencyStats.length; i++) {
      final stat = currencyStats[i];
      final rowIndex = i + 1;

      currencySheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
          .value = stat['currency'] as String;
      currencySheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
          .value = stat['avg_purchase_rate'] as double;
      currencySheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex))
          .value = stat['total_purchased'] as double;
      currencySheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex))
          .value = stat['total_purchase_amount'] as double;
      currencySheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex))
          .value = stat['avg_sale_rate'] as double;
      currencySheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex))
          .value = stat['total_sold'] as double;
      currencySheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex))
          .value = stat['total_sale_amount'] as double;
      currencySheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex))
          .value = stat['current_quantity'] as double;
      currencySheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex))
          .value = stat['profit'] as double;
    }

    // Set column widths
    for (var i = 0; i < headers.length; i++) {
      currencySheet.setColWidth(i, 20.0);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            message.contains(_getTranslatedText('error'))
                ? Colors.red
                : Colors.green,
      ),
    );
  }

  Future<void> _showEditCurrencyDialog(CurrencyModel currency) async {
    final TextEditingController codeController = TextEditingController(
      text: currency.code,
    );
    final TextEditingController quantityController = TextEditingController(
      text: currency.quantity.toString(),
    );
    final TextEditingController defaultBuyRateController =
        TextEditingController(text: currency.defaultBuyRate.toString());
    final TextEditingController defaultSellRateController =
        TextEditingController(text: currency.defaultSellRate.toString());

    return showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              _getTranslatedText('edit_currency', {
                'code': currency.code ?? '',
              }),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText: _getTranslatedText('currency_code'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    maxLength: 3,
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: quantityController,
                    decoration: InputDecoration(
                      labelText: _getTranslatedText('quantity'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: defaultBuyRateController,
                    decoration: InputDecoration(
                      labelText: _getTranslatedText('default_buy_rate'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: defaultSellRateController,
                    decoration: InputDecoration(
                      labelText: _getTranslatedText('default_sell_rate'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  _getTranslatedText('cancel'),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final newCode = codeController.text.toUpperCase();
                    final newQuantity = double.parse(quantityController.text);
                    final newBuyRate = double.parse(
                      defaultBuyRateController.text,
                    );
                    final newSellRate = double.parse(
                      defaultSellRateController.text,
                    );

                    if (newQuantity < 0 ||
                        newBuyRate <= 0 ||
                        newSellRate <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _getTranslatedText('invalid_values_error'),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    // Check if the new code already exists (if it's different from current code)
                    if (newCode != currency.code) {
                      final existingCurrency = await _dbHelper.getCurrency(
                        newCode,
                      );
                      if (existingCurrency != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _getTranslatedText('currency_exists_error'),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                    }

                    // Update currency with new values
                    final updatedCurrency = currency.copyWith(
                      code: newCode,
                      quantity: newQuantity,
                      defaultBuyRate: newBuyRate,
                      defaultSellRate: newSellRate,
                    );

                    await _dbHelper.updateCurrency(updatedCurrency);
                    if (mounted) {
                      Navigator.pop(context);
                      _loadCurrencies(); // Refresh the list
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _getTranslatedText('invalid_number_error'),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _getTranslatedText('save'),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
    );
  }
}

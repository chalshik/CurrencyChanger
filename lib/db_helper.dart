import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import './models/currency.dart';
import './models/history.dart';
import './models/user.dart';

/// Main database helper class for currency conversion operations
class DatabaseHelper {
  // Singleton instance
  static final DatabaseHelper instance = DatabaseHelper._init();

  // Server URL
  String baseUrl = 'https://chigurick.pythonanywhere.com/api';

  // Offline mode flag
  bool _isOfflineMode = false;
  bool get isOfflineMode => _isOfflineMode;
  set isOfflineMode(bool value) => _isOfflineMode = value;

  DatabaseHelper._init();

  // Core API call handler
  Future<dynamic> _apiCall(
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  }) async {
    if (_isOfflineMode) {
      throw Exception('App is in offline mode. Server connection required.');
    }

    try {
      final uri = Uri.parse(
        '$baseUrl/$endpoint',
      ).replace(queryParameters: queryParams);

      final headers = {'Content-Type': 'application/json'};
      http.Response response;

      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'PUT':
          response = await http.put(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers);
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return null;
        return jsonDecode(response.body);
      } else {
        throw Exception(
          'API Error: ${response.statusCode} - ${response.reasonPhrase} - ${response.body}',
        );
      }
    } catch (e) {
      _isOfflineMode = true;
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // Helper function to safely convert values to double
  double _safeDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  // Check server connection
  Future<bool> verifyServerConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/currencies'))
          .timeout(const Duration(seconds: 5));

      _isOfflineMode = response.statusCode != 200;
      return !_isOfflineMode;
    } catch (e) {
      _isOfflineMode = true;
      return false;
    }
  }

  // ========================
  // CURRENCY CRUD OPERATIONS
  // ========================

  Future<CurrencyModel> createOrUpdateCurrency(CurrencyModel currency) async {
    try {
      final response = await _apiCall(
        'currencies',
        method: 'POST',
        body: currency.toMap(),
      );

      return CurrencyModel.fromMap(response);
    } catch (e) {
      debugPrint('Error in createOrUpdateCurrency: $e');
      rethrow;
    }
  }

  /// Get currency by code
  Future<CurrencyModel?> getCurrency(String code) async {
    try {
      final response = await _apiCall('currencies/$code');
      return CurrencyModel.fromMap(response);
    } catch (e) {
      if (e.toString().contains('Resource not found') ||
          e.toString().contains('404')) {
        return null;
      }
      debugPrint('Error in getCurrency: $e');
      rethrow;
    }
  }

  /// Insert new currency
  Future<int> insertCurrency(CurrencyModel currency) async {
    try {
      final response = await _apiCall(
        'currencies',
        method: 'POST',
        body: currency.toMap(),
      );

      return response['id'] ?? 0;
    } catch (e) {
      debugPrint('Error in insertCurrency: $e');
      rethrow;
    }
  }

  /// Delete currency by ID
  Future<int> deleteCurrency(int id) async {
    try {
      await _apiCall('currencies/$id', method: 'DELETE');
      return 1; // Return 1 to indicate success (similar to SQLite return value)
    } catch (e) {
      debugPrint('Error in deleteCurrency: $e');
      return 0; // Return 0 to indicate failure
    }
  }

  /// Get all currencies
  Future<List<CurrencyModel>> getAllCurrencies() async {
    try {
      final response = await _apiCall('currencies');
      return (response as List)
          .map((json) => CurrencyModel.fromMap(json))
          .toList();
    } catch (e) {
      debugPrint('Error in getAllCurrencies: $e');
      return [];
    }
  }

  /// Update currency
  Future<void> updateCurrency(CurrencyModel currency) async {
    try {
      await _apiCall(
        'currencies/${currency.id}',
        method: 'PUT',
        body: currency.toMap(),
      );
    } catch (e) {
      debugPrint('Error in updateCurrency: $e');
      rethrow;
    }
  }

  /// Update currency quantity
  Future<void> updateCurrencyQuantity(String code, double newQuantity) async {
    try {
      await _apiCall(
        'currencies/$code/quantity',
        method: 'PUT',
        body: {'quantity': newQuantity},
      );
    } catch (e) {
      debugPrint('Error in updateCurrencyQuantity: $e');
      rethrow;
    }
  }

  // =====================
  // SYSTEM OPERATIONS
  // =====================

  /// Reset all data
  Future<void> resetAllData() async {
    try {
      await _apiCall('system/reset', method: 'POST');
    } catch (e) {
      debugPrint('Error in resetAllData: $e');
      rethrow;
    }
  }

  /// Get summary of all currency balances
  Future<Map<String, dynamic>> getCurrencySummary() async {
    try {
      return await _apiCall('system/currency-summary');
    } catch (e) {
      debugPrint('Error in getCurrencySummary: $e');
      return {'som_balance': 0, 'other_currencies': {}};
    }
  }

  // =====================
  // BALANCE OPERATIONS
  // =====================

  /// Add amount to SOM balance
  Future<void> addToSomBalance(double amount) async {
    try {
      // First get the current SOM currency
      final som = await getCurrency('SOM');

      if (som == null) {
        throw Exception('SOM currency not found');
      }

      // Calculate new balance
      final newBalance = som.quantity + amount;

      // Update SOM balance
      await updateCurrencyQuantity('SOM', newBalance);

      // Record deposit in history
      await insertHistory(
        HistoryModel(
          currencyCode: 'SOM',
          operationType: 'Deposit',
          rate: 1.0,
          quantity: amount,
          total: amount,
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      debugPrint('Error in addToSomBalance: $e');
      rethrow;
    }
  }

  /// Check if enough SOM available for purchase
  Future<bool> hasEnoughSomForPurchase(double requiredSom) async {
    try {
      final som = await getCurrency('SOM');
      return som != null && som.quantity >= requiredSom;
    } catch (e) {
      debugPrint('Error in hasEnoughSomForPurchase: $e');
      return false;
    }
  }

  /// Check if enough currency available to sell
  Future<bool> hasEnoughCurrencyToSell(
    String currencyCode,
    double quantity,
  ) async {
    try {
      if (currencyCode == 'SOM') return false;

      final currency = await getCurrency(currencyCode);
      return currency != null && currency.quantity >= quantity;
    } catch (e) {
      debugPrint('Error in hasEnoughCurrencyToSell: $e');
      return false;
    }
  }

  // =====================
  // CURRENCY EXCHANGE
  // =====================

  Future<void> performCurrencyExchange({
    required String currencyCode,
    required String operationType,
    required double rate,
    required double quantity,
  }) async {
    try {
      final totalSom = quantity * rate;

      await _apiCall(
        'system/exchange',
        method: 'POST',
        body: {
          'currency_code': currencyCode,
          'operation_type': operationType,
          'rate': rate,
          'quantity': quantity,
          'total': totalSom,
        },
      );
    } catch (e) {
      debugPrint('Error in performCurrencyExchange: $e');
      rethrow;
    }
  }

  // =====================
  // HISTORY OPERATIONS
  // =====================

  /// Get filtered history by date range
  Future<List<HistoryModel>> getFilteredHistoryByDate({
    required DateTime fromDate,
    required DateTime toDate,
    String? currencyCode,
    String? operationType,
  }) async {
    try {
      final queryParams = {
        'from_date': fromDate.toIso8601String(),
        'to_date': toDate.toIso8601String(),
      };

      if (currencyCode != null && currencyCode.isNotEmpty) {
        queryParams['currency_code'] = currencyCode;
      }

      if (operationType != null && operationType.isNotEmpty) {
        queryParams['operation_type'] = operationType;
      }

      final response = await _apiCall(
        'history/filter',
        queryParams: queryParams,
      );

      return (response as List)
          .map((json) => HistoryModel.fromMap(json))
          .toList();
    } catch (e) {
      debugPrint('Error in getFilteredHistoryByDate: $e');
      return [];
    }
  }

  /// Create new history entry
  Future<HistoryModel> createHistoryEntry(HistoryModel historyEntry) async {
    try {
      final response = await _apiCall(
        'history',
        method: 'POST',
        body: historyEntry.toMap(),
      );

      return HistoryModel.fromMap(response);
    } catch (e) {
      debugPrint('Error in createHistoryEntry: $e');
      rethrow;
    }
  }

  /// Get history entries with optional filters
  Future<List<HistoryModel>> getHistoryEntries({
    int? limit,
    String? currencyCode,
  }) async {
    try {
      final queryParams = <String, String>{};

      if (limit != null) {
        queryParams['limit'] = limit.toString();
      }

      if (currencyCode != null && currencyCode.isNotEmpty) {
        queryParams['currency_code'] = currencyCode;
      }

      final response = await _apiCall('history', queryParams: queryParams);

      return (response as List)
          .map((json) => HistoryModel.fromMap(json))
          .toList();
    } catch (e) {
      debugPrint('Error in getHistoryEntries: $e');
      return [];
    }
  }

  /// Update history
  Future<int> updateHistory({
    required HistoryModel newHistory,
    required HistoryModel oldHistory,
  }) async {
    try {
      await _apiCall(
        'history/${newHistory.id}',
        method: 'PUT',
        body: newHistory.toMap(),
      );

      return 1; // Return 1 to indicate success
    } catch (e) {
      debugPrint('Error in updateHistory: $e');
      return 0; // Return 0 to indicate failure
    }
  }

  /// Delete history
  Future<int> deleteHistory(dynamic history) async {
    try {
      final id = history is HistoryModel ? history.id : history as int;

      await _apiCall('history/$id', method: 'DELETE');

      return 1; // Return 1 to indicate success
    } catch (e) {
      debugPrint('Error in deleteHistory: $e');
      return 0; // Return 0 to indicate failure
    }
  }

  /// Get list of unique currency codes from history
  Future<List<String>> getHistoryCurrencyCodes() async {
    try {
      final response = await _apiCall('system/history-codes');
      return List<String>.from(response);
    } catch (e) {
      debugPrint('Error in getHistoryCurrencyCodes: $e');
      return [];
    }
  }

  /// Get list of unique operation types from history
  Future<List<String>> getHistoryOperationTypes() async {
    try {
      final response = await _apiCall('system/history-types');
      return List<String>.from(response);
    } catch (e) {
      debugPrint('Error in getHistoryOperationTypes: $e');
      return [];
    }
  }

  /// Insert history
  Future<int> insertHistory(HistoryModel history) async {
    try {
      final response = await _apiCall(
        'history',
        method: 'POST',
        body: history.toMap(),
      );

      return response['id'] ?? 0;
    } catch (e) {
      debugPrint('Error in insertHistory: $e');
      return 0;
    }
  }

  // =====================
  // ANALYTICS OPERATIONS
  // =====================

  /// Calculate currency statistics for analytics
  Future<Map<String, dynamic>> calculateAnalytics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // Get data from multiple APIs and combine
      final profitData = await getMostProfitableCurrencies(
        startDate: startDate ?? DateTime(2000),
        endDate: endDate ?? DateTime.now(),
      );

      // Get currencies for current quantity and details
      final currencies = await getAllCurrencies();

      // Combine data into the same format expected by the existing API
      final currencyStats = <Map<String, dynamic>>[];
      double totalProfit = 0.0;

      for (var currency in currencies) {
        // Find matching profit data
        final profitEntry = profitData.firstWhere(
          (p) => p['currency_code'] == currency.code,
          orElse:
              () => <String, dynamic>{
                'amount': 0.0,
                'avg_purchase_rate': 0.0,
                'avg_sale_rate': 0.0,
                'total_purchased': 0.0,
                'total_sold': 0.0,
              },
        );

        final profit = profitEntry['amount'] ?? 0.0;

        if (currency.code != 'SOM') {
          totalProfit += profit;
        }

        currencyStats.add({
          'currency': currency.code,
          'avg_purchase_rate': profitEntry['avg_purchase_rate'] ?? 0.0,
          'total_purchased': profitEntry['total_purchased'] ?? 0.0,
          'total_purchase_amount':
              (profitEntry['avg_purchase_rate'] ?? 0.0) *
              (profitEntry['total_purchased'] ?? 0.0),
          'avg_sale_rate': profitEntry['avg_sale_rate'] ?? 0.0,
          'total_sold': profitEntry['total_sold'] ?? 0.0,
          'total_sale_amount':
              (profitEntry['avg_sale_rate'] ?? 0.0) *
              (profitEntry['total_sold'] ?? 0.0),
          'current_quantity': currency.quantity,
          'profit': profit,
        });
      }

      return {'currency_stats': currencyStats, 'total_profit': totalProfit};
    } catch (e) {
      debugPrint('Error in calculateAnalytics: $e');
      return {'currency_stats': [], 'total_profit': 0.0};
    }
  }

  /// Enhanced pie chart data with multiple metrics
  Future<Map<String, dynamic>> getEnhancedPieChartData({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final queryParams = <String, String>{};

      if (startDate != null) {
        queryParams['from_date'] = startDate.toIso8601String();
      }

      if (endDate != null) {
        queryParams['to_date'] = endDate.toIso8601String();
      } else {
        queryParams['to_date'] = DateTime.now().toIso8601String();
      }

      final response = await _apiCall(
        'analytics/pie-chart-data',
        queryParams: queryParams,
      );

      // Ensure data is properly formatted with numeric values
      if (response.containsKey('purchases') && response['purchases'] is List) {
        final purchases = List<Map<String, dynamic>>.from(
          response['purchases'],
        );
        response['purchases'] =
            purchases.map((item) {
              // Make sure total_value is a proper number
              if (item.containsKey('total_value')) {
                final value = item['total_value'];
                if (value is String) {
                  item['total_value'] = double.tryParse(value) ?? 0.0;
                } else if (value is int) {
                  item['total_value'] = value.toDouble();
                } else if (!(value is double)) {
                  item['total_value'] = 0.0;
                }
              } else {
                item['total_value'] = 0.0;
              }
              return item;
            }).toList();
      }

      if (response.containsKey('sales') && response['sales'] is List) {
        final sales = List<Map<String, dynamic>>.from(response['sales']);
        response['sales'] =
            sales.map((item) {
              // Make sure total_value is a proper number
              if (item.containsKey('total_value')) {
                final value = item['total_value'];
                if (value is String) {
                  item['total_value'] = double.tryParse(value) ?? 0.0;
                } else if (value is int) {
                  item['total_value'] = value.toDouble();
                } else if (!(value is double)) {
                  item['total_value'] = 0.0;
                }
              } else {
                item['total_value'] = 0.0;
              }
              return item;
            }).toList();
      }

      debugPrint('Returning pie chart data with:');
      debugPrint('Purchases: ${(response['purchases'] as List).length} items');
      debugPrint('Sales: ${(response['sales'] as List).length} items');

      return response;
    } catch (e) {
      debugPrint('Error in getEnhancedPieChartData: $e');
      return {'purchases': [], 'sales': []};
    }
  }

  Future<List<Map<String, dynamic>>> getDailyData({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final queryParams = {
        'from_date': startDate.toIso8601String(),
        'to_date': endDate.toIso8601String(),
      };

      final response = await _apiCall(
        'analytics/daily-data',
        queryParams: queryParams,
      );

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error in getDailyData: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getMostProfitableCurrencies({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 5,
  }) async {
    try {
      final queryParams = {
        'from_date': startDate.toIso8601String(),
        'to_date': endDate.toIso8601String(),
        'limit': limit.toString(),
      };

      final response = await _apiCall(
        'analytics/profitable-currencies',
        queryParams: queryParams,
      );

      // Convert response to proper list and ensure numeric values
      final result = List<Map<String, dynamic>>.from(response);

      return result.map((item) {
        // Ensure profit is a proper number
        if (item.containsKey('profit')) {
          final profit = item['profit'];
          if (profit is String) {
            item['profit'] = double.tryParse(profit) ?? 0.0;
          } else if (profit is int) {
            item['profit'] = profit.toDouble();
          } else if (!(profit is double)) {
            item['profit'] = 0.0;
          }
        } else {
          item['profit'] = 0.0;
        }

        // Make sure currency_code exists
        if (!item.containsKey('currency_code') ||
            item['currency_code'] == null) {
          item['currency_code'] = 'Unknown';
        }

        return item;
      }).toList();
    } catch (e) {
      debugPrint('Error in getMostProfitableCurrencies: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getDailyDataByCurrency({
    required DateTime startDate,
    required DateTime endDate,
    required String currencyCode,
  }) async {
    try {
      final queryParams = {
        'from_date': startDate.toIso8601String(),
        'to_date': endDate.toIso8601String(),
        'currency_code': currencyCode,
      };

      final response = await _apiCall(
        'analytics/daily-data',
        queryParams: queryParams,
      );

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error in getDailyDataByCurrency: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getBatchAnalyticsData({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final queryParams = {
        'from_date': startDate.toIso8601String(),
        'to_date': endDate.toIso8601String(),
      };

      return await _apiCall('analytics/batch-data', queryParams: queryParams);
    } catch (e) {
      debugPrint('Error in getBatchAnalyticsData: $e');
      return {
        'pieChartData': {'purchases': [], 'sales': []},
        'profitData': [],
        'barChartData': [],
      };
    }
  }

  // Add connection methods
  Future<bool> checkHeartbeat() async {
    try {
      final baseUrlWithoutApi = baseUrl.replaceAll('/api', '');

      final response = await http
          .get(Uri.parse(baseUrlWithoutApi))
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Heartbeat check failed: $e');
      return false;
    }
  }

  Future<bool> retryConnection({
    int maxAttempts = 3,
    int delaySeconds = 1,
  }) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (await verifyServerConnection()) {
          _isOfflineMode = false;
          return true;
        }
        await Future.delayed(Duration(seconds: delaySeconds));
      } catch (e) {
        if (attempt == maxAttempts) {
          _isOfflineMode = true;
          return false;
        }
      }
    }
    _isOfflineMode = true;
    return false;
  }

  // =====================
  // USER OPERATIONS
  // =====================

  /// Get user by username and password (for login)
  Future<UserModel?> getUserByCredentials(
    String username,
    String password,
  ) async {
    // Special case for admin user to allow offline access
    if (username == 'a' && password == 'a') {
      return UserModel(
        id: 1,
        username: 'a',
        role: 'admin',
        createdAt: DateTime.now(),
        password: 'a',
      );
    }

    try {
      final response = await _apiCall(
        'users/login',
        method: 'POST',
        body: {'username': username, 'password': password},
      );

      return UserModel.fromMap(response);
    } catch (e) {
      if (e.toString().contains('Invalid credentials') ||
          e.toString().contains('401')) {
        return null;
      }
      debugPrint('Error in getUserByCredentials: $e');
      rethrow;
    }
  }

  /// Get all users
  Future<List<UserModel>> getAllUsers() async {
    try {
      final response = await _apiCall('users');
      return (response as List).map((json) => UserModel.fromMap(json)).toList();
    } catch (e) {
      debugPrint('Error in getAllUsers: $e');
      return [];
    }
  }

  /// Create new user
  Future<int> createUser(UserModel user) async {
    try {
      final response = await _apiCall(
        'users',
        method: 'POST',
        body: user.toMap(),
      );

      return response['id'] ?? 0;
    } catch (e) {
      debugPrint('Error in createUser: $e');
      rethrow;
    }
  }

  /// Update user
  Future<int> updateUser(UserModel user) async {
    try {
      await _apiCall('users/${user.id}', method: 'PUT', body: user.toMap());

      return 1; // Return 1 to indicate success
    } catch (e) {
      debugPrint('Error in updateUser: $e');
      return 0; // Return 0 to indicate failure
    }
  }

  /// Delete user
  Future<int> deleteUser(int id) async {
    try {
      await _apiCall('users/$id', method: 'DELETE');
      return 1; // Return 1 to indicate success
    } catch (e) {
      debugPrint('Error in deleteUser: $e');
      return 0; // Return 0 to indicate failure
    }
  }

  /// Check if a username already exists
  Future<bool> usernameExists(String username) async {
    try {
      final response = await _apiCall(
        'users/check-username',
        method: 'POST',
        body: {'username': username},
      );

      return response['exists'] ?? false;
    } catch (e) {
      debugPrint('Error in usernameExists: $e');
      return false;
    }
  }
}

// Extension methods for model copying
extension CurrencyModelCopy on CurrencyModel {
  CurrencyModel copyWith({
    int? id,
    String? code,
    double? quantity,
    DateTime? updatedAt,
    double? defaultBuyRate,
    double? defaultSellRate,
  }) {
    return CurrencyModel(
      id: id ?? this.id,
      code: code ?? this.code,
      quantity: quantity ?? this.quantity,
      updatedAt: updatedAt ?? this.updatedAt,
      defaultBuyRate: defaultBuyRate ?? this.defaultBuyRate,
      defaultSellRate: defaultSellRate ?? this.defaultSellRate,
    );
  }
}

extension HistoryModelCopy on HistoryModel {
  HistoryModel copyWith({
    int? id,
    String? currencyCode,
    String? operationType,
    double? rate,
    double? quantity,
    double? total,
    DateTime? createdAt,
  }) {
    return HistoryModel(
      id: id ?? this.id,
      currencyCode: currencyCode ?? this.currencyCode,
      operationType: operationType ?? this.operationType,
      rate: rate ?? this.rate,
      quantity: quantity ?? this.quantity,
      total: total ?? this.total,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

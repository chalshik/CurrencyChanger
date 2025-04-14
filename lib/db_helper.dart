import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/currency.dart';
import '../models/history.dart';
import '../models/user.dart';
import '../screens/login_screen.dart';

class DatabaseHelper {
  // Singleton instance
  static final DatabaseHelper instance = DatabaseHelper._init();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isInitialized = false;
  
  // Add cache for currencies
  static List<CurrencyModel> _currenciesCache = [];
  static DateTime _lastCurrenciesLoadTime = DateTime(2000); // Set to old date initially
  static bool _currenciesCacheDirty = true; // Flag to indicate if cache needs refresh

  // Add public getter for last load time
  DateTime get lastCurrenciesLoadTime => _lastCurrenciesLoadTime;

  // Private constructor
  DatabaseHelper._init();

  // Collections
  static const String collectionCurrencies = 'currencies';
  static const String collectionHistory = 'history';
  static const String collectionUsers = 'users';
  static const String collectionArchive = 'archive'; // New collection for statistics archives

  // Add method to mark cache as dirty (call this when currencies are modified)
  void invalidateCurrenciesCache() {
    _currenciesCacheDirty = true;
  }

  // Method to check if cache needs refresh
  bool shouldRefreshCurrenciesCache() {
    // If cache is marked dirty, it needs refresh
    if (_currenciesCacheDirty) return true;
    
    // If cache is empty, it needs refresh
    if (_currenciesCache.isEmpty) return true;
    
    // If last load time is more than 5 minutes ago, refresh for safety
    final cacheAge = DateTime.now().difference(_lastCurrenciesLoadTime);
    return cacheAge.inMinutes > 5;
  }

  Future<void> initialize() async {
    if (!_isInitialized) {
      await Firebase.initializeApp();
      _isInitialized = true;
    }
  }

  Future<void> initDatabase() async {
    try {
      debugPrint("Starting database initialization...");

      // Initialize Firebase if not already initialized
      if (!_isInitialized) {
        await initialize();
        debugPrint("Firebase initialized successfully");
      }

      // Ensure admin user exists
      final adminExists = await ensureAdminUserExists();
      debugPrint(
        "Admin user verification complete: ${adminExists ? 'exists' : 'failed to create'}",
      );

      // Initialize default data (SOM currency)
      await _initializeDefaultData();
      debugPrint("Default data initialization complete");

      debugPrint("Database initialization completed successfully");
    } catch (e) {
      debugPrint("Error during database initialization: $e");
      if (e is FirebaseException) {
        debugPrint("Firebase error code: ${e.code}");
        debugPrint("Firebase error message: ${e.message}");
      }
      // Don't rethrow - we want to handle errors gracefully
    }
  }

  // Create collections and documents in Firestore
  Future<void> initializeFirestoreData() async {
    try {
      debugPrint("Initializing Firestore data...");

      // Add default SOM currency
      await _firestore.collection(collectionCurrencies).doc('SOM').set({
        'code': 'SOM',
        'quantity': 0.0,
        'updated_at': DateTime.now().toIso8601String(),
        'default_buy_rate': 1.0,
        'default_sell_rate': 1.0,
      });
      debugPrint("SOM currency initialized");

      // Create admin user with document ID 'a'
      await _firestore.collection(collectionUsers).doc('a').set({
        'username': 'a',
        'password': 'a',
        'role': 'admin',
        'created_at': DateTime.now().toIso8601String(),
      });
      debugPrint("Admin user initialized");

      debugPrint("Firestore collections and documents initialized.");
    } catch (e) {
      debugPrint("Error initializing Firestore data: $e");
    }
  }

  // Helper method to check if Firestore collection exists (you can modify this for specific collection/document)
  Future<bool> doesDocumentExist(String collection, String docId) async {
    try {
      final docSnapshot =
          await _firestore.collection(collection).doc(docId).get();
      return docSnapshot.exists;
    } catch (e) {
      debugPrint("Error checking document existence: $e");
      return false;
    }
  }

  // Check database availability - always returns true since Firestore is cloud-based
  Future<bool> verifyDatabaseAvailability() async {
    return true; // Firestore is always available when Firebase is initialized
  }

  // ========================
  // CURRENCY CRUD OPERATIONS
  // ========================

  Future<CurrencyModel> createOrUpdateCurrency(CurrencyModel currency) async {
    try {
      // Reference to the currency document by its code
      DocumentReference currencyRef = _firestore
          .collection(collectionCurrencies)
          .doc(currency.code);

      // Check if the document exists by fetching it
      DocumentSnapshot snapshot = await currencyRef.get();

      if (snapshot.exists) {
        // Update existing currency
        await currencyRef.update(currency.toMap());
      } else {
        // Insert new currency with default zero values
        final currencyData = {
          'code': currency.code,
          'quantity': 0.0,
          'updated_at': DateTime.now().toIso8601String(),
          'default_buy_rate': 0.0, // Set to zero (will be ignored in UI)
          'default_sell_rate': 0.0, // Set to zero (will be ignored in UI)
        };
        await currencyRef.set(currencyData);
      }
      
      // Invalidate cache
      invalidateCurrenciesCache();
      debugPrint('Currency created/updated and cache invalidated: ${currency.code}');

      return currency;
    } catch (e) {
      debugPrint('Error in createOrUpdateCurrency: $e');
      rethrow;
    }
  }

  // Get currency by code (this method is now inside the DatabaseHelper class)
  Future<CurrencyModel?> getCurrency(String code) async {
    try {
      final doc =
          await _firestore.collection(collectionCurrencies).doc(code).get();
      if (doc.exists && doc.data() != null) {
        return CurrencyModel.fromFirestore(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting currency: $e');
      return null;
    }
  }

  Future<void> insertCurrency(CurrencyModel currency) async {
    try {
      // Reference to the currency document by its code
      DocumentReference currencyRef = _firestore
          .collection(collectionCurrencies)
          .doc(currency.code);

      // Prepare data with default values for all fields except code
      final Map<String, dynamic> currencyData = {
        'code': currency.code,
        'quantity': 0.0,
        'updated_at': DateTime.now().toIso8601String(),
        'default_buy_rate': 0.0, // Set to zero (will be ignored in UI)
        'default_sell_rate': 0.0, // Set to zero (will be ignored in UI)
      };

      // Insert new currency (set data in Firestore)
      await currencyRef.set(currencyData);
      
      // Invalidate cache
      invalidateCurrenciesCache();
      debugPrint('Currency inserted and cache invalidated: ${currency.code}');
    } catch (e) {
      debugPrint('Error in insertCurrency: $e');
      rethrow;
    }
  }

  // Delete currency by code
  Future<void> deleteCurrency(String code) async {
    try {
      // Reference to the currency document by its code
      DocumentReference currencyRef = _firestore
          .collection(collectionCurrencies)
          .doc(code);

      // Delete the currency document
      await currencyRef.delete();
      
      // Invalidate cache
      invalidateCurrenciesCache();
      debugPrint('Currency deleted and cache invalidated: $code');
    } catch (e) {
      debugPrint('Error in deleteCurrency: $e');
      rethrow;
    }
  }

  Future<List<CurrencyModel>> getAllCurrencies() async {
    try {
      // Check if we can use the cached data
      if (!shouldRefreshCurrenciesCache()) {
        debugPrint('Using cached currencies data (${_currenciesCache.length} currencies)');
        return _currenciesCache;
      }

      // Need to fetch fresh data
      debugPrint('Fetching fresh currencies data from Firestore');
      final snapshot = await _firestore.collection(collectionCurrencies).get();

      // Convert Firestore documents to CurrencyModel objects
      final currencies =
          snapshot.docs
              .map((doc) => CurrencyModel.fromFirestore(doc.data(), doc.id))
              .toList();

      // Update cache
      _currenciesCache = currencies;
      _lastCurrenciesLoadTime = DateTime.now();
      _currenciesCacheDirty = false;
      
      debugPrint('Updated currencies cache with ${currencies.length} currencies');
      return currencies;
    } catch (e) {
      debugPrint('Error getting all currencies: $e');
      // If there was an error but we have cached data, return it
      if (_currenciesCache.isNotEmpty) {
        debugPrint('Returning cached currencies despite error');
        return _currenciesCache;
      }
      return [];
    }
  }

  // Update currency
  Future<void> updateCurrency(CurrencyModel currency) async {
    try {
      // Reference to the currency document by its code
      DocumentReference currencyRef = _firestore
          .collection(collectionCurrencies)
          .doc(currency.code);

      // Update the currency document with the new data
      await currencyRef.update(currency.toMap());
      
      // Invalidate cache
      invalidateCurrenciesCache();
      debugPrint('Currency updated and cache invalidated: ${currency.code}');
    } catch (e) {
      debugPrint('Error in updateCurrency: $e');
      rethrow;
    }
  }

  Future<void> updateCurrencyQuantity(
    String currencyCode,
    double newQuantity,
  ) async {
    try {
      final currencyRef = _firestore.collection('currencies').doc(currencyCode);

      // Use transaction to ensure atomic updates
      await _firestore.runTransaction((transaction) async {
        final currencyDoc = await transaction.get(currencyRef);

        if (!currencyDoc.exists) {
          throw Exception('Currency $currencyCode not found');
        }

        // Special handling for SOM currency
        if (currencyCode == 'SOM') {
          // Verify the change is valid (prevent negative balance)
          if (newQuantity < 0) {
            throw Exception('Cannot set SOM quantity below 0');
          }

          // Update SOM quantity atomically
          transaction.update(currencyRef, {
            'quantity': newQuantity,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        } else {
          // For other currencies, update normally
          transaction.update(currencyRef, {
            'quantity': newQuantity,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }
      });
      
      // Invalidate cache after quantity update
      invalidateCurrenciesCache();
      debugPrint('Currency quantity updated and cache invalidated: $currencyCode');
    } catch (e) {
      debugPrint('Error updating currency quantity: $e');
      rethrow;
    }
  }

  // =====================
  // SYSTEM OPERATIONS
  // =====================

  /// Reset all data
  // Reset all data in Firestore
  Future<void> resetAllData() async {
    try {
      debugPrint('Starting data reset process...');
      
      // First, create a backup of the current statistics
      debugPrint('Creating backup before reset...');
      final backupSuccess = await backupStatistics();
      if (backupSuccess) {
        debugPrint('Backup created successfully before reset');
      } else {
        debugPrint('Warning: Failed to create backup before reset');
        // Continue with reset even if backup fails
      }
      
      // Clear history collection
      debugPrint('Clearing transaction history...');
      await _firestore.collection(collectionHistory).get().then((
        snapshot,
      ) async {
        for (var doc in snapshot.docs) {
          await doc.reference.delete();
        }
      });

      // Reset ALL currencies to 0, including SOM
      debugPrint('Resetting all currency quantities to zero...');
      final currenciesSnapshot =
          await _firestore.collection(collectionCurrencies).get();
      for (var doc in currenciesSnapshot.docs) {
        await doc.reference.update({
          'quantity': 0.0,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      debugPrint(
        'Reset completed: Transaction history cleared. All currency quantities reset to 0. Users preserved.',
      );
    } catch (e) {
      debugPrint('Error in resetAllData: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
      }
      rethrow;
    }
  }

  // Get summary of all currency balances
  Future<Map<String, dynamic>> getCurrencySummary() async {
    try {
      // Get SOM balance
      final somDoc =
          await _firestore.collection(collectionCurrencies).doc('SOM').get();
      double somBalance = 0.0;
      if (somDoc.exists) {
        somBalance = somDoc.data()?['quantity'] ?? 0.0;
      }

      // Get other currencies
      final otherCurrencies = <String, dynamic>{};
      final currenciesSnapshot =
          await _firestore.collection(collectionCurrencies).get();
      for (var doc in currenciesSnapshot.docs) {
        if (doc.id != 'SOM') {
          otherCurrencies[doc.id] = {
            'quantity': doc.data()?['quantity'] ?? 0.0,
            'default_buy_rate': doc.data()?['default_buy_rate'] ?? 0.0,
            'default_sell_rate': doc.data()?['default_sell_rate'] ?? 0.0,
          };
        }
      }

      return {'som_balance': somBalance, 'other_currencies': otherCurrencies};
    } catch (e) {
      debugPrint('Error in getCurrencySummary: $e');
      return {'som_balance': 0, 'other_currencies': {}};
    }
  }

  // =====================
  // BALANCE OPERATIONS
  // =====================

  /// Add amount to SOM balance
  // Add to SOM balance in Firestore
  Future<void> addToSomBalance(double amount) async {
    try {
      // Reference to the SOM currency document
      DocumentReference somRef = _firestore
          .collection(collectionCurrencies)
          .doc('SOM');

      // Get current SOM currency document
      DocumentSnapshot somSnapshot = await somRef.get();

      if (!somSnapshot.exists) {
        throw Exception('SOM currency not found');
      }

      final somData = somSnapshot.data() as Map<String, dynamic>;

      // Calculate new balance
      final newBalance = somData['quantity'] + amount;

      // Update SOM balance
      await somRef.update({
        'quantity': newBalance,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Record deposit in history
      await _firestore.collection(collectionHistory).add({
        'currency_code': 'SOM',
        'operation_type': 'Deposit',
        'rate': 1.0,
        'quantity': amount,
        'total': amount,
        'created_at': DateTime.now().toIso8601String(),
      });
      
      // Invalidate cache after balance update
      invalidateCurrenciesCache();
      debugPrint('SOM balance updated and cache invalidated');
    } catch (e) {
      debugPrint('Error in addToSomBalance: $e');
      rethrow;
    }
  }

  // Check if there is enough SOM for a purchase in Firestore
  Future<bool> hasEnoughSomForPurchase(double requiredSom) async {
    try {
      // Reference to the SOM currency document
      DocumentReference somRef = _firestore
          .collection(collectionCurrencies)
          .doc('SOM');

      // Get current SOM currency document
      DocumentSnapshot somSnapshot = await somRef.get();

      if (!somSnapshot.exists) {
        return false; // SOM currency not found
      }

      final somData = somSnapshot.data() as Map<String, dynamic>;

      // Check if the quantity is sufficient
      return somData['quantity'] >= requiredSom;
    } catch (e) {
      debugPrint('Error in hasEnoughSomForPurchase: $e');
      return false;
    }
  }

  /// Check if enough currency available to sell
  // Check if there is enough currency to sell (other than SOM)
  Future<bool> hasEnoughCurrencyToSell(
    String currencyCode,
    double quantity,
  ) async {
    try {
      if (currencyCode == 'SOM') return false;

      // Reference to the currency document
      DocumentReference currencyRef = _firestore
          .collection(collectionCurrencies)
          .doc(currencyCode);

      // Get current currency document
      DocumentSnapshot currencySnapshot = await currencyRef.get();

      if (!currencySnapshot.exists) {
        return false; // Currency not found
      }

      final currencyData = currencySnapshot.data() as Map<String, dynamic>;

      // Check if the quantity is sufficient
      return currencyData['quantity'] >= quantity;
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
      // Reference to the SOM and foreign currency documents
      DocumentReference somRef = _firestore
          .collection(collectionCurrencies)
          .doc('SOM');
      DocumentReference currencyRef = _firestore
          .collection(collectionCurrencies)
          .doc(currencyCode);

      // Start a Firestore transaction
      await _firestore.runTransaction((transaction) async {
        // Get current SOM document
        DocumentSnapshot somSnapshot = await transaction.get(somRef);
        if (!somSnapshot.exists) {
          throw Exception('SOM currency not found');
        }
        final somData = somSnapshot.data() as Map<String, dynamic>;

        // Calculate the total SOM required
        final totalSom = quantity * rate;

        if (operationType == 'Buy') {
          // Check if we have enough SOM for the purchase
          if (somData['quantity'] < totalSom) {
            throw Exception('Insufficient SOM balance for purchase');
          }

          // Update SOM quantity (decrease)
          transaction.update(somRef, {
            'quantity': somData['quantity'] - totalSom,
            'updated_at': DateTime.now().toIso8601String(),
          });

          // Get current foreign currency document
          DocumentSnapshot currencySnapshot = await transaction.get(
            currencyRef,
          );
          if (currencySnapshot.exists) {
            final currencyData =
                currencySnapshot.data() as Map<String, dynamic>;

            // Update foreign currency quantity (increase)
            transaction.update(currencyRef, {
              'quantity': currencyData['quantity'] + quantity,
              'updated_at': DateTime.now().toIso8601String(),
            });
          } else {
            // Create new foreign currency if not found
            transaction.set(currencyRef, {
              'code': currencyCode,
              'quantity': quantity,
              'updated_at': DateTime.now().toIso8601String(),
              'default_buy_rate': 0.0, // Use 0.0 instead of rate
              'default_sell_rate': 0.0, // Use 0.0 instead of markup
            });
          }
        } else if (operationType == 'Sell') {
          // Get current foreign currency document
          DocumentSnapshot currencySnapshot = await transaction.get(
            currencyRef,
          );
          if (!currencySnapshot.exists) {
            throw Exception('Currency not found: $currencyCode');
          }

          final currencyData = currencySnapshot.data() as Map<String, dynamic>;
          if (currencyData['quantity'] < quantity) {
            throw Exception('Insufficient $currencyCode balance for sale');
          }

          // Update foreign currency quantity (decrease)
          transaction.update(currencyRef, {
            'quantity': currencyData['quantity'] - quantity,
            'updated_at': DateTime.now().toIso8601String(),
          });

          // Update SOM quantity (increase)
          transaction.update(somRef, {
            'quantity': somData['quantity'] + totalSom,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }

        // Record the transaction in history
        await transaction.set(_firestore.collection(collectionHistory).doc(), {
          'currency_code': currencyCode,
          'operation_type': operationType,
          'rate': rate,
          'quantity': quantity,
          'total': totalSom,
          'created_at': DateTime.now().toIso8601String(),
        });
      });
      
      // Invalidate currencies cache after exchange
      invalidateCurrenciesCache();
      debugPrint('Currency exchange completed and cache invalidated');
    } catch (e) {
      debugPrint('Error in performCurrencyExchange: $e');
      rethrow;
    }
  }

  // =====================
  // HISTORY OPERATIONS
  // =====================

  /// Get filtered history by date range, currency code, and operation type
  Future<List<HistoryModel>> getFilteredHistoryByDate({
    DateTime? startDate,
    DateTime? endDate,
    String? currencyCode,
    String? operationType,
  }) async {
    try {
      debugPrint('Getting filtered history...');
      debugPrint(
        'Current user: ${currentUser?.username}, Role: ${currentUser?.role}',
      );

      // Start with a query on the history collection
      Query query = _firestore.collection(collectionHistory);

      // If current user is not admin, filter by username first
      if (currentUser != null && currentUser!.role != 'admin') {
        debugPrint('Filtering by username: ${currentUser!.username}');
        query = query.where('username', isEqualTo: currentUser!.username);
      }

      // Add date range filters if provided
      if (startDate != null) {
        query = query.where(
          'created_at',
          isGreaterThanOrEqualTo: startDate.toIso8601String(),
        );
      }

      if (endDate != null) {
        query = query.where(
          'created_at',
          isLessThanOrEqualTo: endDate.toIso8601String(),
        );
      }

      // Add currency code filter if provided
      if (currencyCode != null && currencyCode.isNotEmpty) {
        query = query.where('currency_code', isEqualTo: currencyCode);
      }

      // Add operation type filter if provided
      if (operationType != null && operationType.isNotEmpty) {
        query = query.where('operation_type', isEqualTo: operationType);
      }

      // Order by created_at in descending order
      query = query.orderBy('created_at', descending: true);

      // Execute the query
      final querySnapshot = await query.get();
      debugPrint('Found ${querySnapshot.docs.length} history documents');

      // Convert Firestore documents to HistoryModel objects
      final historyEntries =
          querySnapshot.docs
              .map(
                (doc) => HistoryModel.fromFirestore(
                  doc.data() as Map<String, dynamic>,
                  doc.id,
                ),
              )
              .toList();

      // Debug output to verify the entries
      for (var entry in historyEntries) {
        debugPrint(
          'History entry: ${entry.currencyCode}, ${entry.operationType}, ${entry.username}',
        );
      }

      return historyEntries;
    } catch (e) {
      debugPrint('Error in getFilteredHistoryByDate: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
      }
      return [];
    }
  }

  /// Create a new history entry
  Future<HistoryModel> createHistoryEntry(HistoryModel historyEntry) async {
    try {
      // Add username to history entry if not already set
      final entryWithUsername =
          historyEntry.username.isEmpty && currentUser != null
              ? historyEntry.copyWith(username: currentUser!.username)
              : historyEntry;

      // Add the history entry to Firestore
      final docRef = await _firestore
          .collection(collectionHistory)
          .add(entryWithUsername.toMap());

      // Return the history entry with the new document ID
      return entryWithUsername.copyWith(id: docRef.id);
    } catch (e) {
      debugPrint('Error in createHistoryEntry: $e');
      rethrow;
    }
  }

  /// Get history entries with optional filters
  Future<List<HistoryModel>> getHistoryEntries({
    String? currencyCode,
    String? operationType,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    try {
      debugPrint('Getting history entries...');
      debugPrint(
        'Current user: ${currentUser?.username}, Role: ${currentUser?.role}',
      );

      // Start with a query on the history collection
      Query query = _firestore.collection(collectionHistory);

      // If current user is not admin, filter by username
      if (currentUser != null && currentUser!.role != 'admin') {
        query = query.where(
          'username',
          isEqualTo: currentUser!.username.toLowerCase(),
        );
      }

      // Apply currency code filter if provided
      if (currencyCode != null && currencyCode.isNotEmpty) {
        query = query.where('currency_code', isEqualTo: currencyCode);
      }

      // Apply operation type filter if provided
      if (operationType != null && operationType.isNotEmpty) {
        query = query.where('operation_type', isEqualTo: operationType);
      }

      // Apply date range filters if provided
      if (startDate != null) {
        query = query.where(
          'created_at',
          isGreaterThanOrEqualTo: startDate.toIso8601String(),
        );
      }
      if (endDate != null) {
        query = query.where(
          'created_at',
          isLessThanOrEqualTo: endDate.toIso8601String(),
        );
      }

      // Order by creation date (newest first)
      query = query.orderBy('created_at', descending: true);

      // Apply limit if provided
      if (limit != null) {
        query = query.limit(limit);
      }

      // Get all history documents
      final querySnapshot = await query.get();
      debugPrint('Found ${querySnapshot.docs.length} history documents');

      // Convert to HistoryModel objects
      final List<HistoryModel> historyEntries = [];
      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          historyEntries.add(HistoryModel.fromFirestore(data, doc.id));
        }
      }

      return historyEntries;
    } catch (e) {
      debugPrint('Error in getHistoryEntries: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
      }
      return [];
    }
  }

  /// Update history
  Future<bool> updateHistory({
    required HistoryModel newHistory,
    required HistoryModel oldHistory,
  }) async {
    try {
      // Debug output to track the update process
      debugPrint('Updating history entry:');
      debugPrint('Old entry: ${oldHistory.toString()}');
      debugPrint('New entry: ${newHistory.toString()}');

      // Convert to maps for detailed comparison
      final oldMap = oldHistory.toMap();
      final newMap = newHistory.toMap();

      // Print what changed
      final changes = <String>[];
      newMap.forEach((key, value) {
        if (oldMap[key] != value && key != 'id') {
          changes.add('$key: ${oldMap[key]} -> $value');
        }
      });

      debugPrint('Changes: ${changes.join(', ')}');
      debugPrint('Using ID for update: ${newHistory.id}');

      // Check if we need to update currency balances
      bool needsBalanceUpdate =
          newHistory.operationType != oldHistory.operationType ||
          newHistory.currencyCode != oldHistory.currencyCode ||
          newHistory.quantity != oldHistory.quantity ||
          newHistory.total != oldHistory.total;

      if (needsBalanceUpdate) {
        // Get references to the affected currency documents
        final oldCurrencyRef = _firestore
            .collection(collectionCurrencies)
            .doc(oldHistory.currencyCode);
        final newCurrencyRef = _firestore
            .collection(collectionCurrencies)
            .doc(newHistory.currencyCode);
        final somRef = _firestore.collection(collectionCurrencies).doc('SOM');

        // Fetch all required documents BEFORE starting the transaction
        final oldCurrencyDoc = await oldCurrencyRef.get();
        final newCurrencyDoc = await newCurrencyRef.get();
        final somDoc = await somRef.get();

        if (!oldCurrencyDoc.exists ||
            !newCurrencyDoc.exists ||
            !somDoc.exists) {
          throw Exception('Required currency documents not found');
        }

        // Extract data from documents
        final oldCurrencyData = oldCurrencyDoc.data() as Map<String, dynamic>;
        final newCurrencyData = newCurrencyDoc.data() as Map<String, dynamic>;
        final somData = somDoc.data() as Map<String, dynamic>;

        // Get current quantities
        double oldCurrencyQuantity = oldCurrencyData['quantity'] ?? 0.0;
        double newCurrencyQuantity = newCurrencyData['quantity'] ?? 0.0;
        double somQuantity = somData['quantity'] ?? 0.0;

        // Calculate adjustments based on old history entry (reverse its effect)
        switch (oldHistory.operationType) {
          case 'Purchase':
            oldCurrencyQuantity -=
                oldHistory.quantity; // Remove the purchased currency
            somQuantity += oldHistory.total; // Add back the SOM that was spent
            break;
          case 'Sale':
            oldCurrencyQuantity +=
                oldHistory.quantity; // Add back the sold currency
            somQuantity -= oldHistory.total; // Remove the SOM that was received
            break;
          case 'Deposit':
            if (oldHistory.currencyCode == 'SOM') {
              somQuantity -= oldHistory.quantity; // Remove the deposited SOM
            }
            break;
        }

        // Calculate adjustments based on new history entry (apply its effect)
        // Only apply if different from old currency (for same currency, effects combine)
        if (newHistory.currencyCode != oldHistory.currencyCode) {
          switch (newHistory.operationType) {
            case 'Purchase':
              newCurrencyQuantity +=
                  newHistory.quantity; // Add the purchased currency
              somQuantity -= newHistory.total; // Remove the SOM spent
              break;
            case 'Sale':
              newCurrencyQuantity -=
                  newHistory.quantity; // Remove the sold currency
              somQuantity += newHistory.total; // Add the SOM received
              break;
            case 'Deposit':
              if (newHistory.currencyCode == 'SOM') {
                somQuantity += newHistory.quantity; // Add the deposited SOM
              }
              break;
          }
        } else {
          // Same currency, need to apply combined effect
          switch (newHistory.operationType) {
            case 'Purchase':
              oldCurrencyQuantity +=
                  newHistory.quantity; // Add the purchased currency
              somQuantity -= newHistory.total; // Remove the SOM spent
              break;
            case 'Sale':
              oldCurrencyQuantity -=
                  newHistory.quantity; // Remove the sold currency
              somQuantity += newHistory.total; // Add the SOM received
              break;
            case 'Deposit':
              if (newHistory.currencyCode == 'SOM') {
                somQuantity += newHistory.quantity; // Add the deposited SOM
              }
              break;
          }
        }

        // Ensure quantities don't go negative
        oldCurrencyQuantity = oldCurrencyQuantity < 0 ? 0 : oldCurrencyQuantity;
        newCurrencyQuantity = newCurrencyQuantity < 0 ? 0 : newCurrencyQuantity;
        somQuantity = somQuantity < 0 ? 0 : somQuantity;

        // Now start the transaction with all reads complete
        await _firestore.runTransaction((transaction) async {
          // Update the history document first
          transaction.update(
            _firestore.collection(collectionHistory).doc(newHistory.id),
            newHistory.toMap(),
          );

          // Update the old currency (if not SOM and if different from new currency)
          if (oldHistory.currencyCode != 'SOM' &&
              oldHistory.currencyCode != newHistory.currencyCode) {
            transaction.update(oldCurrencyRef, {
              'quantity': oldCurrencyQuantity,
              'updated_at': DateTime.now().toIso8601String(),
            });
          }

          // Update the new currency (if not SOM and if different from old currency)
          if (newHistory.currencyCode != 'SOM' &&
              oldHistory.currencyCode != newHistory.currencyCode) {
            transaction.update(newCurrencyRef, {
              'quantity': newCurrencyQuantity,
              'updated_at': DateTime.now().toIso8601String(),
            });
          }

          // If both are the same currency but not SOM, update it once
          if (oldHistory.currencyCode == newHistory.currencyCode &&
              oldHistory.currencyCode != 'SOM') {
            transaction.update(oldCurrencyRef, {
              'quantity': oldCurrencyQuantity,
              'updated_at': DateTime.now().toIso8601String(),
            });
          }

          // Always update SOM
          transaction.update(somRef, {
            'quantity': somQuantity,
            'updated_at': DateTime.now().toIso8601String(),
          });
        });
      } else {
        // Just update the history entry without adjusting currency balances
        await _firestore
            .collection(collectionHistory)
            .doc(newHistory.id)
            .update(newHistory.toMap());
      }

      // Debug the result
      debugPrint('Update successful');

      return true;
    } catch (e) {
      debugPrint('Error in updateHistory: $e');
      return false; // Return false to indicate failure
    }
  }

  /// Delete history
  Future<bool> deleteHistory(dynamic history) async {
    try {
      final HistoryModel historyEntry;
      if (history is HistoryModel) {
        historyEntry = history;
      } else {
        // If only ID was passed, fetch the full history entry
        final doc =
            await _firestore
                .collection(collectionHistory)
                .doc(history as String)
                .get();
        if (!doc.exists) {
          throw Exception('History entry not found');
        }
        historyEntry = HistoryModel.fromFirestore(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }

      debugPrint(
        'Deleting history entry: ${historyEntry.currencyCode}, ${historyEntry.operationType}, ${historyEntry.quantity}',
      );

      // Use a transaction to ensure the history deletion and currency updates are atomic
      await _firestore.runTransaction((transaction) async {
        // First, reverse the currency balance changes
        await _reverseHistoryImpact(transaction, historyEntry);

        // Then delete the history entry
        transaction.delete(
          _firestore.collection(collectionHistory).doc(historyEntry.id),
        );
      });

      debugPrint('History entry deleted successfully and balances updated');
      return true;
    } catch (e) {
      debugPrint('Error in deleteHistory: $e');
      return false; // Return false to indicate failure
    }
  }

  /// Reverse the impact of a history entry on currency balances
  Future<void> _reverseHistoryImpact(
    Transaction transaction,
    HistoryModel entry,
  ) async {
    try {
      final operationType = entry.operationType;
      final currencyCode = entry.currencyCode;
      final quantity = entry.quantity;
      final total = entry.total;

      // Get references to the affected currency documents
      final currencyRef = _firestore
          .collection(collectionCurrencies)
          .doc(currencyCode);
      final somRef = _firestore.collection(collectionCurrencies).doc('SOM');

      // Get current data for the affected currencies
      final currencyDoc = await transaction.get(currencyRef);
      final somDoc = await transaction.get(somRef);

      if (!currencyDoc.exists || !somDoc.exists) {
        throw Exception('Currency documents not found');
      }

      final currencyData = currencyDoc.data() as Map<String, dynamic>;
      final somData = somDoc.data() as Map<String, dynamic>;

      double currencyQuantity = currencyData['quantity'] ?? 0.0;
      double somQuantity = somData['quantity'] ?? 0.0;

      switch (operationType) {
        case 'Purchase':
          // For a purchase: decrease currency quantity and increase SOM
          currencyQuantity -= quantity;
          somQuantity += total; // Add back the SOM spent
          break;
        case 'Sale':
          // For a sale: increase currency quantity and decrease SOM
          currencyQuantity += quantity;
          somQuantity -= total; // Remove the SOM received
          break;
        case 'Deposit':
          // For a deposit of SOM, just decrease SOM balance
          if (currencyCode == 'SOM') {
            somQuantity -= quantity;
          }
          break;
      }

      // Ensure quantities don't go negative
      currencyQuantity = currencyQuantity < 0 ? 0 : currencyQuantity;
      somQuantity = somQuantity < 0 ? 0 : somQuantity;

      // Update the currency quantities
      if (currencyCode != 'SOM') {
        transaction.update(currencyRef, {
          'quantity': currencyQuantity,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      transaction.update(somRef, {
        'quantity': somQuantity,
        'updated_at': DateTime.now().toIso8601String(),
      });

      debugPrint(
        'Reversed impact - ${currencyCode}: ${currencyQuantity}, SOM: ${somQuantity}',
      );
    } catch (e) {
      debugPrint('Error in _reverseHistoryImpact: $e');
      rethrow;
    }
  }

  /// Get list of unique currency codes from history
  Future<List<String>> getHistoryCurrencyCodes() async {
    try {
      debugPrint('Getting history currency codes...');
      debugPrint(
        'Current user: ${currentUser?.username}, Role: ${currentUser?.role}',
      );

      // Start with a query on the history collection
      Query query = _firestore.collection(collectionHistory);

      // If current user is not admin, filter by username
      if (currentUser != null && currentUser!.role != 'admin') {
        query = query.where('username', isEqualTo: currentUser!.username);
      }

      // Get all history documents
      final querySnapshot = await query.get();
      debugPrint('Found ${querySnapshot.docs.length} history documents');

      // Extract unique currency codes
      final Set<String> currencyCodes = {};
      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null && data.containsKey('currency_code')) {
          currencyCodes.add(data['currency_code'] as String);
        }
      }

      // Convert to list and sort
      final result = currencyCodes.toList()..sort();
      debugPrint('Final currency codes: $result');
      return result;
    } catch (e) {
      debugPrint('Error in getHistoryCurrencyCodes: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
      }
      return [];
    }
  }

  /// Get list of unique operation types from history
  Future<List<String>> getHistoryOperationTypes() async {
    try {
      debugPrint('Getting history operation types...');
      debugPrint(
        'Current user: ${currentUser?.username}, Role: ${currentUser?.role}',
      );

      // Start with a query on the history collection
      Query query = _firestore.collection(collectionHistory);

      // If current user is not admin, filter by username
      if (currentUser != null && currentUser!.role != 'admin') {
        query = query.where('username', isEqualTo: currentUser!.username);
      }

      // Get all history documents
      final querySnapshot = await query.get();
      debugPrint('Found ${querySnapshot.docs.length} history documents');

      // Extract unique operation types
      final Set<String> operationTypes = {};
      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        debugPrint('History document data: $data');

        if (data != null && data.containsKey('operation_type')) {
          operationTypes.add(data['operation_type'] as String);
          debugPrint('Added operation type: ${data['operation_type']}');
        }
      }

      // Convert to list and sort
      final result = operationTypes.toList()..sort();
      debugPrint('Final operation types: $result');
      return result;
    } catch (e) {
      debugPrint('Error in getHistoryOperationTypes: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
      }
      return [];
    }
  }

  /// Insert a new history entry
  Future<String> insertHistory({
    required String currencyCode,
    required String operationType,
    required double rate,
    required double quantity,
    required double total,
  }) async {
    try {
      if (currentUser == null) {
        throw Exception('No user logged in');
      }

      // Create a new history entry
      final history = HistoryModel(
        id: '', // Firestore will generate this
        currencyCode: currencyCode,
        operationType: operationType,
        rate: rate,
        quantity: quantity,
        total: total,
        createdAt: DateTime.now(),
        username: currentUser!.username,
      );

      // Add to Firestore using toMap method
      final docRef = await _firestore
          .collection(collectionHistory)
          .add(history.toMap());
      return docRef.id;
    } catch (e) {
      debugPrint('Error in insertHistory: $e');
      return '';
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
      // Set default date range if not provided
      final fromDate = startDate ?? DateTime(2000);
      final toDate = endDate ?? DateTime.now();

      // Get profitable currencies data
      final profitData = await getStat(
        startDate: fromDate,
        endDate: toDate,
        limit: 1000, // High limit to get all currencies
      );

      // Get all currencies
      final currencies = await getAllCurrencies();

      // Combine data
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
                'cost_of_sold': 0.0,
              },
        );

        final profit = _safeDouble(profitEntry['amount']);

        if (currency.code != 'SOM') {
          totalProfit += profit;
        }

        // Calculate totals correctly
        final avgPurchaseRate = _safeDouble(profitEntry['avg_purchase_rate']);
        final avgSaleRate = _safeDouble(profitEntry['avg_sale_rate']);
        final totalPurchased = _safeDouble(profitEntry['total_purchased']);
        final totalSold = _safeDouble(profitEntry['total_sold']);

        // Calculate proper total amounts
        final totalPurchaseAmount = avgPurchaseRate * totalPurchased;
        final totalSaleAmount = avgSaleRate * totalSold;

        currencyStats.add({
          'currency': currency.code,
          'avg_purchase_rate': avgPurchaseRate,
          'total_purchased': totalPurchased,
          'total_purchase_amount': totalPurchaseAmount,
          'avg_sale_rate': avgSaleRate,
          'total_sold': totalSold,
          'total_sale_amount': totalSaleAmount,
          'current_quantity': currency.quantity,
          'profit': profit,
          'cost_of_sold': _safeDouble(profitEntry['cost_of_sold']),
        });

        // Debug statistics
        debugPrint(
          'Stats - ${currency.code}: ' +
              'avgPurchase=$avgPurchaseRate, ' +
              'avgSale=$avgSaleRate, ' +
              'totalPurchased=$totalPurchased, ' +
              'totalSold=$totalSold, ' +
              'purchaseAmount=$totalPurchaseAmount, ' +
              'saleAmount=$totalSaleAmount, ' +
              'profit=$profit',
        );
      }

      return {'currency_stats': currencyStats, 'total_profit': totalProfit};
    } catch (e) {
      debugPrint('Error in calculateAnalytics: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
      }
      return {'currency_stats': [], 'total_profit': 0.0};
    }
  }

  /// Enhanced pie chart data with multiple metrics
  Future<Map<String, dynamic>> getEnhancedPieChartData({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // Set default date range if not provided
      final fromDate = startDate ?? DateTime(2000);
      final toDate = endDate ?? DateTime.now();

      final fromDateStr = fromDate.toIso8601String().split('T')[0]; // YYYY-MM-DD format
      final toDateStr = toDate.toIso8601String().split('T')[0]; // YYYY-MM-DD format

      debugPrint('Fetching pie chart data from $fromDateStr to $toDateStr');

      // Find relevant archives within date range
      final archiveQuery = await _firestore.collection(collectionArchive)
          .where('date', isGreaterThanOrEqualTo: fromDateStr)
          .where('date', isLessThanOrEqualTo: toDateStr)
          .orderBy('date', descending: true)
              .get();

      debugPrint('Found ${archiveQuery.docs.length} archive records');

      // If no archives in range, return empty results
      if (archiveQuery.docs.isEmpty) {
        debugPrint('No archive data found, returning empty results');
        return {'purchases': [], 'sales': []};
      }

      // Process purchase and sales data from archived statistics
      final Map<String, Map<String, dynamic>> purchaseData = {};
      final Map<String, Map<String, dynamic>> salesData = {};

      // Use the most recent archive record in the date range
      final archiveDoc = archiveQuery.docs.first.data();
      if (!archiveDoc.containsKey('currencies')) {
        debugPrint('Archive record missing currencies data');
        return {'purchases': [], 'sales': []};
      }

      // Process currencies data to extract purchase and sales information
      final currenciesData = List<Map<String, dynamic>>.from(archiveDoc['currencies'] ?? []);
      for (var currency in currenciesData) {
        final currencyCode = currency['currency_code'] as String;
        
        // Skip SOM currency
        if (currencyCode == 'SOM') continue;

        // Extract purchase data
        final totalPurchased = _safeDouble(currency['total_purchased']);
        final totalPurchaseAmount = _safeDouble(currency['total_purchase_amount']);
        
        if (totalPurchased > 0) {
            purchaseData[currencyCode] = {
              'currency': currencyCode,
            'total_value': totalPurchaseAmount,
            'count': 1, // Simplified count since we're aggregating from archive
          };
        }
        
        // Extract sales data
        final totalSold = _safeDouble(currency['total_sold']);
        final totalSaleAmount = _safeDouble(currency['total_sale_amount']);
        
        if (totalSold > 0) {
            salesData[currencyCode] = {
              'currency': currencyCode,
            'total_value': totalSaleAmount,
            'count': 1, // Simplified count since we're aggregating from archive
            };
        }
      }

      // Convert to lists and sort by total_value
      final purchases = purchaseData.values.toList()
        ..sort((a, b) => (_safeDouble(b['total_value']) - _safeDouble(a['total_value'])).toInt());

      final sales = salesData.values.toList()
        ..sort((a, b) => (_safeDouble(b['total_value']) - _safeDouble(a['total_value'])).toInt());

      debugPrint('Processed ${purchases.length} purchase currencies and ${sales.length} sales currencies');

      return {'purchases': purchases, 'sales': sales};
    } catch (e) {
      debugPrint('Error in getEnhancedPieChartData: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
      }
      return {'purchases': [], 'sales': []};
    }
  }

  Future<List<Map<String, dynamic>>> getDailyData({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final fromDateStr = startDate.toIso8601String().split('T')[0]; // YYYY-MM-DD format
      final toDateStr = endDate.toIso8601String().split('T')[0]; // YYYY-MM-DD format

      debugPrint('Fetching daily data from $fromDateStr to $toDateStr');

      // Get all archive records in the date range
      final archiveQuery = await _firestore.collection(collectionArchive)
          .where('date', isGreaterThanOrEqualTo: fromDateStr)
          .where('date', isLessThanOrEqualTo: toDateStr)
          .orderBy('date')
          .get();

      debugPrint('Found ${archiveQuery.docs.length} archive records');

      // Build daily data from archive records
      final List<Map<String, dynamic>> dailyData = [];
      
      for (var doc in archiveQuery.docs) {
        final data = doc.data();
        final date = data['date'] as String;
        
        // Create daily data structure with default zeroes to ensure consistent format
        final dayData = {
          'day': date,  // Use ISO date format consistently: YYYY-MM-DD
            'purchases': 0.0,
            'sales': 0.0,
            'profit': 0.0,
            'deposits': 0.0,
            'currencies': <String, Map<String, dynamic>>{},
          };
        
        // Process currency-specific data
        if (data.containsKey('currencies')) {
          final currenciesData = List<Map<String, dynamic>>.from(data['currencies'] ?? []);
          
          double dailyPurchaseTotal = 0.0;
          double dailySaleTotal = 0.0;
          double dailyProfitTotal = 0.0;
          
          for (var currency in currenciesData) {
            final currencyCode = currency['currency_code'] as String;
            
            // Skip SOM for daily aggregates
            if (currencyCode == 'SOM') continue;
            
            final purchaseAmount = _safeDouble(currency['total_purchase_amount']);
            final saleAmount = _safeDouble(currency['total_sale_amount']);
            final profit = _safeDouble(currency['profit']);
            
            // Add to daily totals
            dailyPurchaseTotal += purchaseAmount;
            dailySaleTotal += saleAmount;
            dailyProfitTotal += profit;
            
            // Add currency-specific data
            (dayData['currencies'] as Map)[currencyCode] = {
              'currency': currencyCode,
              'purchase_amount': purchaseAmount,
              'purchase_quantity': _safeDouble(currency['total_purchased']),
              'sale_amount': saleAmount,
              'sale_quantity': _safeDouble(currency['total_sold']),
              'count_purchase': 1, // Simplified since we don't have actual counts
              'count_sale': 1,     // Simplified since we don't have actual counts
            };
          }
          
          // Set aggregated values
          dayData['purchases'] = dailyPurchaseTotal;
          dayData['sales'] = dailySaleTotal;
          dayData['profit'] = dailyProfitTotal;
        }
        
        // Add summary data if available (overrides currency-specific calculations)
        if (data.containsKey('summary')) {
          final summary = data['summary'] as Map<String, dynamic>;
          dayData['purchases'] = _safeDouble(summary['total_purchased']);
          dayData['sales'] = _safeDouble(summary['total_sold']);
          dayData['profit'] = _safeDouble(summary['total_profit']);
        }
        
        dailyData.add(dayData);
      }

      // Sort by date
      dailyData.sort((a, b) => (a['day'] as String).compareTo(b['day'] as String));
      
      if (dailyData.isNotEmpty) {
        debugPrint('First day data: ${dailyData.first}');
      }

      return dailyData;
    } catch (e) {
      debugPrint('Error in getDailyData: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
      }
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getDailyDataByCurrency({
    required DateTime startDate,
    required DateTime endDate,
    required String currencyCode,
  }) async {
    try {
      final fromDateStr = startDate.toIso8601String().split('T')[0]; // YYYY-MM-DD format
      final toDateStr = endDate.toIso8601String().split('T')[0]; // YYYY-MM-DD format

      debugPrint('Fetching daily data for currency $currencyCode from $fromDateStr to $toDateStr');

      // Get all archive records in the date range
      final archiveQuery = await _firestore.collection(collectionArchive)
          .where('date', isGreaterThanOrEqualTo: fromDateStr)
          .where('date', isLessThanOrEqualTo: toDateStr)
          .orderBy('date')
          .get();

      debugPrint('Found ${archiveQuery.docs.length} archive records');

      // Prepare daily data structure
      final List<Map<String, dynamic>> dailyData = [];

      // Process each archive record
      for (var doc in archiveQuery.docs) {
        final data = doc.data();
        final date = data['date'] as String;
        
        // Skip if archive doesn't have currencies data
        if (!data.containsKey('currencies')) continue;
        
        final currenciesData = List<Map<String, dynamic>>.from(data['currencies'] ?? []);
        
        // Find data for the requested currency
        final currencyData = currenciesData.firstWhere(
          (c) => c['currency_code'] == currencyCode,
          orElse: () => {},
        );
        
        // Skip if currency not found in this archive
        if (currencyData.isEmpty) continue;
        
        // Extract data for this currency with safe conversion
        final purchaseAmount = _safeDouble(currencyData['total_purchase_amount']);
        final purchaseQuantity = _safeDouble(currencyData['total_purchased']);
        final saleAmount = _safeDouble(currencyData['total_sale_amount']);
        final saleQuantity = _safeDouble(currencyData['total_sold']);
        final profit = _safeDouble(currencyData['profit']);
        
        // Create daily entry with consistent format
        dailyData.add({
          'day': date,  // Use ISO date format consistently: YYYY-MM-DD
          'purchases': purchaseAmount,
          'purchase_quantity': purchaseQuantity,
          'sales': saleAmount,
          'sale_quantity': saleQuantity,
          'profit': profit,
          'deposits': 0.0, // Archive doesn't typically store deposit information
        });
      }

      // Sort by date
      dailyData.sort((a, b) => (a['day'] as String).compareTo(b['day'] as String));
      
      if (dailyData.isNotEmpty) {
        debugPrint('First day data for $currencyCode: ${dailyData.first}');
        } else {
        debugPrint('No daily data found for currency $currencyCode');
      }

      return dailyData;
    } catch (e) {
      debugPrint('Error in getDailyDataByCurrency: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
      }
      return [];
    }
  }

  Future<Map<String, dynamic>> getBatchAnalyticsData({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      // Get all the required data
      final pieChartData = await getEnhancedPieChartData(
        startDate: startDate,
        endDate: endDate,
      );

      final profitData = await getMostProfitableCurrencies(
        startDate: startDate,
        endDate: endDate,
      );

      final barChartData = await getDailyData(
        startDate: startDate,
        endDate: endDate,
      );

      return {
        'pieChartData': pieChartData,
        'profitData': profitData,
        'barChartData': barChartData,
      };
    } catch (e) {
      debugPrint('Error in getBatchAnalyticsData: $e');
      return {
        'pieChartData': {'purchases': [], 'sales': []},
        'profitData': [],
        'barChartData': [],
      };
    }
  }

  // =====================
  // USER OPERATIONS
  // =====================

  /// Get user by username and password (for login)
  Future<UserModel?> getUserByCredentials(
    String username,
    String password,
  ) async {
    try {
      debugPrint('Attempting login for username: $username');

      // Special case for admin user
      if (username == 'a' && password == 'a') {
        debugPrint('Admin credentials detected');

        // First check if admin exists in Firestore
        final adminDoc =
            await _firestore.collection(collectionUsers).doc('a').get();

        if (!adminDoc.exists) {
          debugPrint('Admin user not found in Firestore, creating...');
          // Create admin user in Firestore first
          await _firestore.collection(collectionUsers).doc('a').set({
            'username': 'a',
            'password': 'a',
            'role': 'admin',
            'created_at': DateTime.now().toIso8601String(),
          });
          debugPrint('Admin user created in Firestore');
        }

        // Sign in with Firebase Auth
        try {
          await _auth.signInWithEmailAndPassword(
            email: 'admin@currencychanger.com',
            password: 'a',
          );
          debugPrint('Admin user signed in with Firebase Auth');
        } catch (e) {
          if (e is FirebaseException && e.code == 'user-not-found') {
            // Create the admin user in Firebase Auth
            await _auth.createUserWithEmailAndPassword(
              email: 'admin@currencychanger.com',
              password: 'a',
            );
            debugPrint('Admin user created in Firebase Auth');
          } else {
            debugPrint('Error signing in admin with Firebase Auth: $e');
          }
        }

        // Return admin user model
        return UserModel(id: 'a', username: 'a', password: 'a', role: 'admin');
      }

      // For non-admin users, check Firestore
      final querySnapshot =
          await _firestore
              .collection(collectionUsers)
              .where('username', isEqualTo: username)
              .where('password', isEqualTo: password)
              .get();

      if (querySnapshot.docs.isNotEmpty) {
        final userData = querySnapshot.docs.first.data();
        debugPrint('User found in Firestore');

        // Sign in with Firebase Auth
        try {
          await _auth.signInWithEmailAndPassword(
            email: '${username}@currencychanger.com',
            password: password,
          );
          debugPrint('User signed in with Firebase Auth');
        } catch (e) {
          if (e is FirebaseException && e.code == 'user-not-found') {
            // Create the user in Firebase Auth
            await _auth.createUserWithEmailAndPassword(
              email: '${username}@currencychanger.com',
              password: password,
            );
            debugPrint('User created in Firebase Auth');
          } else {
            debugPrint('Error signing in with Firebase Auth: $e');
          }
        }

        return UserModel.fromFirestore(userData, querySnapshot.docs.first.id);
      }

      debugPrint('Authentication failed - No matching user found');
      return null;
    } catch (e) {
      debugPrint('Error in getUserByCredentials: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
      }
      return null;
    }
  }

  /// Get all users
  Future<List<UserModel>> getAllUsers() async {
    try {
      // Get all users from Firestore
      final querySnapshot = await _firestore.collection(collectionUsers).get();

      // Convert Firestore documents to UserModel objects
      return querySnapshot.docs
          .map((doc) => UserModel.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('Error in getAllUsers: $e');
      return [];
    }
  }

  /// Create new user
  Future<String> createUser(UserModel user) async {
    try {
      debugPrint('Creating new user: ${user.username}');

      // Validate username
      if (user.username.isEmpty) {
        throw Exception('Username cannot be empty');
      }

      // Check if username already exists
      final exists = await usernameExists(user.username);
      if (exists) {
        throw Exception('Username already exists');
      }

      // Special case for admin user
      if (user.username == 'a' && user.password == 'a') {
        debugPrint('Creating admin user');

        // Create admin user in Firestore
        await _firestore.collection(collectionUsers).doc('a').set({
          'username': 'a',
          'password': 'a',
          'role': 'admin',
          'created_at': DateTime.now().toIso8601String(),
        });

        debugPrint('Admin user created successfully');
        return 'a';
      }

      // For non-admin users, check if admin exists
      final adminDoc =
          await _firestore.collection(collectionUsers).doc('a').get();
      if (!adminDoc.exists) {
        throw Exception(
          'Admin user does not exist. Please create admin user first.',
        );
      }

      // Generate a document ID based on username
      final docId = user.username.toLowerCase().replaceAll(' ', '_');

      // Add the user to Firestore with specific document ID
      await _firestore.collection(collectionUsers).doc(docId).set({
        ...user.toMap(),
        'created_at': DateTime.now().toIso8601String(),
      });

      debugPrint('User created successfully with ID: $docId');
      return docId;
    } catch (e) {
      debugPrint('Error in createUser: $e');
      rethrow;
    }
  }

  /// Update user
  Future<bool> updateUser(UserModel user) async {
    try {
      // Update the user document in Firestore
      await _firestore
          .collection(collectionUsers)
          .doc(user.id)
          .update(user.toMap());

      return true;
    } catch (e) {
      debugPrint('Error in updateUser: $e');
      return false; // Return false to indicate failure
    }
  }

  /// Delete user
  Future<bool> deleteUser(String id) async {
    try {
      // Delete the user document from Firestore
      await _firestore.collection(collectionUsers).doc(id).delete();

      return true;
    } catch (e) {
      debugPrint('Error in deleteUser: $e');
      return false; // Return false to indicate failure
    }
  }

  /// Check if a username already exists
  Future<bool> usernameExists(String username) async {
    try {
      // Query Firestore for a user with the given username
      final querySnapshot =
          await _firestore
              .collection(collectionUsers)
              .where('username', isEqualTo: username)
              .get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error in usernameExists: $e');
      return false;
    }
  }

  // Helper method to safely convert values to double
  double _safeDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) {
      try {
        return double.parse(value);
      } catch (e) {
        return 0.0;
      }
    }
    return 0.0;
  }

  /// Convert Firestore document to CurrencyModel
  CurrencyModel _currencyFromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CurrencyModel.fromMap({...data, 'id': int.tryParse(doc.id) ?? 0});
  }

  /// Convert Firestore document to HistoryModel
  HistoryModel _historyFromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return HistoryModel.fromFirestore(data, doc.id);
  }

  // Convert Firestore document to UserModel
  UserModel _userFromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserModel.fromFirestore(data, doc.id);
  }

  // Verify admin user exists
  Future<bool> ensureAdminUserExists() async {
    try {
      debugPrint('Checking if admin user exists...');

      // First check by document ID
      final adminDoc =
          await _firestore.collection(collectionUsers).doc('a').get();

      if (adminDoc.exists) {
        debugPrint('Admin user exists with document ID "a"');
        return true;
      }

      debugPrint('Admin user not found with document ID "a", creating...');

      // Create admin user in Firestore first (without Firebase Auth)
      try {
        await _firestore.collection(collectionUsers).doc('a').set({
          'username': 'a',
          'password': 'a',
          'role': 'admin',
          'created_at': DateTime.now().toIso8601String(),
        });
        debugPrint('Admin user created in Firestore');

        // Now try to create Firebase Auth user
        try {
          final userCredential = await _auth.createUserWithEmailAndPassword(
            email: 'a@currencychanger.com',
            password: 'a',
          );

          if (userCredential.user != null) {
            // Update admin user with Firebase Auth UID
            await _firestore.collection(collectionUsers).doc('a').update({
              'uid': userCredential.user!.uid,
            });
            debugPrint('Admin user updated with Firebase Auth UID');
          }
        } catch (authError) {
          debugPrint('Error creating Firebase Auth user: $authError');
          // Continue anyway since we have the Firestore user
        }

        return true;
      } catch (firestoreError) {
        debugPrint('Error creating admin user in Firestore: $firestoreError');
        if (firestoreError is FirebaseException) {
          debugPrint('Firebase error code: ${firestoreError.code}');
          debugPrint('Firebase error message: ${firestoreError.message}');
        }
        return false;
      }
    } catch (e) {
      debugPrint('Error in ensureAdminUserExists: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
      }
      return false;
    }
  }

  // Check if admin user exists and print all users
  Future<void> checkFirestoreUsers() async {
    try {
      debugPrint('Checking Firestore users collection...');

      // Get all users from Firestore
      final querySnapshot = await _firestore.collection(collectionUsers).get();

      debugPrint('Total users in Firestore: ${querySnapshot.docs.length}');

      if (querySnapshot.docs.isEmpty) {
        debugPrint('No users found in Firestore. Creating admin user...');
        // Create admin user
        await _firestore.collection(collectionUsers).doc('a').set({
          'username': 'a',
          'password': 'a',
          'role': 'admin',
          'created_at': DateTime.now().toIso8601String(),
        });
        debugPrint('Admin user created successfully');
      } else {
        // Print all users
        for (var doc in querySnapshot.docs) {
          final data = doc.data();
          debugPrint(
            'User found - ID: ${doc.id}, Username: ${data['username']}, Role: ${data['role']}',
          );
        }

        // Check if admin user exists
        final adminExists = querySnapshot.docs.any(
          (doc) =>
              doc.data()['username'] == 'a' && doc.data()['password'] == 'a',
        );

        if (!adminExists) {
          debugPrint('Admin user not found. Creating admin user...');
          // Create admin user
          await _firestore.collection(collectionUsers).doc('a').set({
            'username': 'a',
            'password': 'a',
            'role': 'admin',
            'created_at': DateTime.now().toIso8601String(),
          });
          debugPrint('Admin user created successfully');
        } else {
          debugPrint('Admin user already exists in Firestore');
        }
      }
    } catch (e) {
      debugPrint('Error checking Firestore users: $e');
    }
  }

  Future<void> _initializeDefaultData() async {
    try {
      debugPrint("Starting default data initialization...");

      // First ensure admin user exists
      await ensureAdminUserExists();

      // Initialize SOM currency if needed
      final somDoc =
          await _firestore.collection(collectionCurrencies).doc('SOM').get();
      if (!somDoc.exists) {
        await _firestore.collection(collectionCurrencies).doc('SOM').set({
          'code': 'SOM',
          'quantity': 0.0,
          'updated_at': DateTime.now().toIso8601String(),
          'default_buy_rate': 0.0, // Set to zero instead of 1.0
          'default_sell_rate': 0.0, // Set to zero instead of 1.0
        });
        debugPrint("SOM currency initialized");
      }

      // Check if currencies other than SOM exist
      final querySnapshot =
          await _firestore
              .collection(collectionCurrencies)
              .where(FieldPath.documentId, isNotEqualTo: 'SOM')
              .get();

      if (querySnapshot.docs.isEmpty) {
        // Add default currencies with empty quantities and rates
        final defaultCurrencies = [
          {
            'code': 'USD',
            'quantity': 0.0,
            'updated_at': DateTime.now().toIso8601String(),
            'default_buy_rate': 0.0,
            'default_sell_rate': 0.0,
          },
          {
            'code': 'EUR',
            'quantity': 0.0,
            'updated_at': DateTime.now().toIso8601String(),
            'default_buy_rate': 0.0,
            'default_sell_rate': 0.0,
          },
          {
            'code': 'RUB',
            'quantity': 0.0,
            'updated_at': DateTime.now().toIso8601String(),
            'default_buy_rate': 0.0,
            'default_sell_rate': 0.0,
          },
        ];

        for (var currency in defaultCurrencies) {
          await _firestore
              .collection(collectionCurrencies)
              .doc(currency['code'] as String)
              .set(currency);
        }
        debugPrint("Default currencies initialized");
      }

      debugPrint("Default data initialization completed");
    } catch (e) {
      debugPrint("Error initializing default data: $e");
      if (e is FirebaseException) {
        debugPrint("Firebase error code: ${e.code}");
        debugPrint("Firebase error message: ${e.message}");
      }
      rethrow;
    }
  }

  /// Verify and repair SOM currency document
  Future<void> verifySomCurrency() async {
    try {
      debugPrint("Verifying SOM currency document...");
      final somDoc =
          await _firestore.collection(collectionCurrencies).doc('SOM').get();

      if (!somDoc.exists) {
        debugPrint("SOM currency document not found, creating it...");
        await _firestore.collection(collectionCurrencies).doc('SOM').set({
          'code': 'SOM',
          'quantity': 0.0,
          'updated_at': DateTime.now().toIso8601String(),
          'default_buy_rate': 0.0, // Set to zero instead of 1.0
          'default_sell_rate': 0.0, // Set to zero instead of 1.0
        });
        debugPrint("SOM currency document created successfully");
        return;
      }

      // Verify document has all required fields
      final data = somDoc.data();
      if (data == null) {
        throw Exception('SOM currency document data is null');
      }

      bool needsUpdate = false;
      final Map<String, dynamic> updates = {};

      if (!data.containsKey('quantity')) {
        updates['quantity'] = 0.0;
        needsUpdate = true;
      }
      if (!data.containsKey('updated_at')) {
        updates['updated_at'] = DateTime.now().toIso8601String();
        needsUpdate = true;
      }
      if (!data.containsKey('default_buy_rate')) {
        updates['default_buy_rate'] = 0.0; // Set to zero instead of 1.0
        needsUpdate = true;
      }
      if (!data.containsKey('default_sell_rate')) {
        updates['default_sell_rate'] = 0.0; // Set to zero instead of 1.0
        needsUpdate = true;
      }

      if (needsUpdate) {
        debugPrint("Updating SOM currency document with missing fields...");
        await _firestore
            .collection(collectionCurrencies)
            .doc('SOM')
            .update(updates);
        debugPrint("SOM currency document updated successfully");
      } else {
        debugPrint("SOM currency document is valid");
      }
    } catch (e) {
      debugPrint("Error verifying SOM currency: $e");
      rethrow;
    }
  }

  /// Recalculate SOM balance from transaction history
  Future<void> recalculateSomBalance() async {
    try {
      debugPrint("Recalculating SOM balance from transaction history...");

      // Get all transactions involving SOM
      final querySnapshot =
          await _firestore
              .collection(collectionHistory)
              .orderBy('created_at')
              .get();

      double calculatedBalance = 0.0;

      // Process all transactions in chronological order
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final operationType = data['operation_type'] as String;
        final total = _safeDouble(data['total']);

        switch (operationType) {
          case 'Purchase':
            calculatedBalance -= total; // Subtract SOM spent
            break;
          case 'Sale':
            calculatedBalance += total; // Add SOM received
            break;
          case 'Deposit':
            calculatedBalance += total; // Add SOM deposited
            break;
        }
      }

      debugPrint("Calculated SOM balance: $calculatedBalance");

      // Update SOM currency document with calculated balance
      await _firestore.collection(collectionCurrencies).doc('SOM').update({
        'quantity': calculatedBalance,
        'updated_at': DateTime.now().toIso8601String(),
      });

      debugPrint("SOM balance updated successfully");
    } catch (e) {
      debugPrint("Error recalculating SOM balance: $e");
      rethrow;
    }
  }

  // Get currency quantity by code
  Future<double> getCurrencyQuantity(String code) async {
    try {
      // Get the currency document
      final doc =
          await _firestore.collection(collectionCurrencies).doc(code).get();

      // Check if the document exists and has data
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        // Return the quantity as a double, defaulting to 0.0 if not found
        return (data['quantity'] as num?)?.toDouble() ?? 0.0;
      }

      // Return 0.0 if currency doesn't exist
      return 0.0;
    } catch (e) {
      debugPrint('Error in getCurrencyQuantity: $e');
      // Return 0.0 on error
      return 0.0;
    }
  }

  // Add history entry
  Future<bool> addHistoryEntry(HistoryModel historyEntry) async {
    try {
      // Create a new document with auto-generated ID
      DocumentReference historyRef =
          _firestore.collection(collectionHistory).doc();

      // Convert history entry to map
      Map<String, dynamic> historyData = historyEntry.toMap();

      // Add the entry to Firestore
      await historyRef.set(historyData);

      debugPrint('History entry added successfully with ID: ${historyRef.id}');
      return true;
    } catch (e) {
      debugPrint('Error in addHistoryEntry: $e');
      return false;
    }
  }

  // Update currency quantity
  Future<bool> adjustCurrencyQuantity(
    String code,
    double amount,
    bool isAddition,
  ) async {
    try {
      // Reference to the currency document
      DocumentReference currencyRef = _firestore
          .collection(collectionCurrencies)
          .doc(code);

      // Get the current document
      DocumentSnapshot doc = await currencyRef.get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        // Get current quantity, defaulting to 0.0 if not found
        double currentQuantity = (data['quantity'] as num?)?.toDouble() ?? 0.0;

        // Calculate new quantity based on operation
        double newQuantity =
            isAddition ? currentQuantity + amount : currentQuantity - amount;

        // Ensure quantity doesn't go below zero (except for SOM which can be negative)
        if (newQuantity < 0 && code != 'SOM') {
          newQuantity = 0;
        }

        // Update the quantity and timestamp
        await currencyRef.update({
          'quantity': newQuantity,
          'updated_at': DateTime.now().toIso8601String(),
        });

        // Invalidate cache after quantity adjustment
        invalidateCurrenciesCache();
        debugPrint('Currency $code quantity adjusted and cache invalidated');
        return true;
      } else {
        // If currency doesn't exist, create it with the given amount (if adding)
        if (isAddition) {
          await currencyRef.set({
            'code': code,
            'quantity': amount,
            'updated_at': DateTime.now().toIso8601String(),
            'default_buy_rate': 0.0,
            'default_sell_rate': 0.0,
          });
          
          // Invalidate cache after creating new currency
          invalidateCurrenciesCache();
          debugPrint('Currency $code created with quantity: $amount and cache invalidated');
          return true;
        } else {
          debugPrint('Cannot subtract from non-existent currency: $code');
          return false;
        }
      }
    } catch (e) {
      debugPrint('Error in adjustCurrencyQuantity: $e');
      return false;
    }
  }

  /// Archive current statistics to Firestore
  Future<bool> backupStatistics() async {
    try {
      debugPrint('Creating statistics backup in archive collection...');
      
      // Calculate today's statistics (use all available data)
      final analytics = await calculateAnalytics();
      
      // Create timestamp for archive record
      final now = DateTime.now();
      final dateStr = now.toIso8601String().split('T')[0]; // YYYY-MM-DD format
      
      // Prepare archive document
      final archiveDocument = {
        'timestamp': now.toIso8601String(),
        'date': dateStr,
        'total_profit': analytics['total_profit'] ?? 0.0,
        'currencies': [],
      };
      
      // Process each currency's statistics
      final List<Map<String, dynamic>> currenciesData = [];
      
      if (analytics.containsKey('currency_stats')) {
        for (var stat in analytics['currency_stats']) {
          // Skip if not a valid map
          if (stat is! Map<String, dynamic> || !stat.containsKey('currency')) {
            continue;
          }
          
          final currencyCode = stat['currency'];
          
          // Prepare currency data - excluding avg rates, current quantity, and cost of sold
          final currencyData = {
            'currency_code': currencyCode,
            'total_purchased': stat['total_purchased'] ?? 0.0,
            'total_purchase_amount': stat['total_purchase_amount'] ?? 0.0,
            'total_sold': stat['total_sold'] ?? 0.0,
            'total_sale_amount': stat['total_sale_amount'] ?? 0.0,
            'profit': stat['profit'] ?? 0.0,
          };
          
          currenciesData.add(currencyData);
        }
      }
      
      // Add currencies data to archive document
      archiveDocument['currencies'] = currenciesData;
      
      // Add additional summary data
      double totalPurchased = 0.0;
      double totalSold = 0.0;
      
      for (var currency in currenciesData) {
        if (currency['currency_code'] != 'SOM') {
          totalPurchased += _safeDouble(currency['total_purchase_amount']);
          totalSold += _safeDouble(currency['total_sale_amount']);
        }
      }
      
      archiveDocument['summary'] = {
        'total_purchased': totalPurchased,
        'total_sold': totalSold,
        'total_profit': analytics['total_profit'] ?? 0.0,
        'som_balance': _getSomBalanceFromAnalytics(analytics),
      };
      
      // Create a document ID with date for easy retrieval
      final docId = 'stats_${dateStr}';
      
      // Save to Firestore
      await _firestore.collection(collectionArchive).doc(docId).set(archiveDocument);
      
      debugPrint('Statistics backup created successfully: $docId');
      return true;
    } catch (e) {
      debugPrint('Error creating statistics backup: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
      }
      return false;
    }
  }
  
  // Helper method to extract SOM balance from analytics data
  double _getSomBalanceFromAnalytics(Map<String, dynamic> analytics) {
    if (!analytics.containsKey('currency_stats')) return 0.0;
    
    final currencyStats = analytics['currency_stats'] as List<dynamic>;
    final somCurrency = currencyStats.firstWhere(
      (stat) => stat is Map<String, dynamic> && stat['currency'] == 'SOM',
      orElse: () => {'current_quantity': 0.0}
    );
    
    if (somCurrency is Map<String, dynamic>) {
      return _safeDouble(somCurrency['current_quantity']);
    }
    
    return 0.0;
  }

  /// Get archived statistics from a specific date
  Future<Map<String, dynamic>?> getArchivedStatistics(String date) async {
    try {
      final docId = 'stats_$date';
      final docSnapshot = await _firestore.collection(collectionArchive).doc(docId).get();
      
      if (docSnapshot.exists && docSnapshot.data() != null) {
        return docSnapshot.data()!;
      }
      
      return null;
    } catch (e) {
      debugPrint('Error retrieving archived statistics: $e');
      return null;
    }
  }
  
  /// Get list of available archived statistics dates
  Future<List<String>> getArchiveDates() async {
    try {
      final querySnapshot = await _firestore.collection(collectionArchive).get();
      
      final dates = querySnapshot.docs
          .map((doc) => doc.id.startsWith('stats_') ? doc.id.substring(6) : null)
          .where((date) => date != null)
          .map((date) => date!)
          .toList();
      
      // Sort dates in descending order (newest first)
      dates.sort((a, b) => b.compareTo(a));
      
      return dates;
    } catch (e) {
      debugPrint('Error retrieving archive dates: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getMostProfitableCurrencies({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 5,
  }) async {
    try {
      final fromDateStr = startDate.toIso8601String().split('T')[0]; // YYYY-MM-DD format
      final toDateStr = endDate.toIso8601String().split('T')[0]; // YYYY-MM-DD format

      debugPrint('Fetching most profitable currencies from $fromDateStr to $toDateStr from archive collection');

      // Query the archive collection instead of history
      final archiveQuery = await _firestore.collection(collectionArchive)
          .where('date', isGreaterThanOrEqualTo: fromDateStr)
          .where('date', isLessThanOrEqualTo: toDateStr)
          .get();
      
      debugPrint('Found ${archiveQuery.docs.length} archive entries for profit calculation');
      
      // Maps to track statistics by currency
      final Map<String, Map<String, dynamic>> currencyStats = {};
      
      // Process each archive entry
      for (var doc in archiveQuery.docs) {
        final data = doc.data();
        
        // Skip if archive doesn't have currencies data
        if (!data.containsKey('currencies')) continue;
        
        final currenciesData = List<Map<String, dynamic>>.from(data['currencies'] ?? []);
        
        // Process each currency in this archive entry
        for (var currencyData in currenciesData) {
          final currencyCode = currencyData['currency_code'] as String;
          
          // Skip SOM for profit calculation
          if (currencyCode == 'SOM') continue;
          
          // Initialize currency stats if needed
          if (!currencyStats.containsKey(currencyCode)) {
            currencyStats[currencyCode] = {
              'total_purchased': 0.0,
              'total_purchase_amount': 0.0,
              'total_sold': 0.0,
              'total_sale_amount': 0.0,
              'profit': 0.0,
            };
          }
          
          // Aggregate the statistics from archive
          currencyStats[currencyCode]!['total_purchased'] += _safeDouble(currencyData['total_purchased']);
          currencyStats[currencyCode]!['total_purchase_amount'] += _safeDouble(currencyData['total_purchase_amount']);
          currencyStats[currencyCode]!['total_sold'] += _safeDouble(currencyData['total_sold']);
          currencyStats[currencyCode]!['total_sale_amount'] += _safeDouble(currencyData['total_sale_amount']);
          currencyStats[currencyCode]!['profit'] += _safeDouble(currencyData['profit']);
        }
      }

      // Convert to format needed for the UI
      final List<Map<String, dynamic>> profitData = [];
      
      // Get current currencies for display
      final currencies = await getAllCurrencies();
      
      for (var currency in currencies) {
        final currencyCode = currency.code!;
        
        // Skip SOM
        if (currencyCode == 'SOM') continue;
        
        final stats = currencyStats[currencyCode] ?? {
          'total_purchased': 0.0,
          'total_purchase_amount': 0.0,
          'total_sold': 0.0,
          'total_sale_amount': 0.0,
          'profit': 0.0,
        };
        
        // Calculate averages
        final totalPurchased = _safeDouble(stats['total_purchased']);
        final totalPurchaseAmount = _safeDouble(stats['total_purchase_amount']);
        final totalSold = _safeDouble(stats['total_sold']);
        final totalSaleAmount = _safeDouble(stats['total_sale_amount']);
        final profit = _safeDouble(stats['profit']);
        
        final avgPurchaseRate = totalPurchased > 0 ? totalPurchaseAmount / totalPurchased : 0.0;
        final avgSaleRate = totalSold > 0 ? totalSaleAmount / totalSold : 0.0;
        final costOfSold = totalSold * avgPurchaseRate;
        
        profitData.add({
          'currency_code': currencyCode,
          'amount': profit,
          'avg_purchase_rate': avgPurchaseRate,
          'avg_sale_rate': avgSaleRate,
          'total_purchased': totalPurchased,
          'total_sold': totalSold,
          'cost_of_sold': costOfSold,
          'total_purchase_amount': totalPurchaseAmount,
          'total_sale_amount': totalSaleAmount,
        });
        
        // Debug output
        debugPrint('Archive Stats - ${currencyCode}: ' +
            'avgPurchase=$avgPurchaseRate, ' +
            'avgSale=$avgSaleRate, ' +
            'totalPurchased=$totalPurchased, ' +
            'totalSold=$totalSold, ' +
            'purchaseAmount=$totalPurchaseAmount, ' +
            'saleAmount=$totalSaleAmount, ' +
            'profit=$profit'
        );
      }

      // Sort by profit and limit
      profitData.sort((a, b) => (_safeDouble(b['amount']) - _safeDouble(a['amount'])).toInt());
      
      debugPrint('Found ${profitData.length} currencies with profit data from archive');
      if (profitData.isNotEmpty) {
        debugPrint('Most profitable: ${profitData.first['currency_code']}, profit: ${profitData.first['amount']}');
      }

      if (limit > 0 && profitData.length > limit) {
        return profitData.sublist(0, limit);
      }

      return profitData;
    } catch (e) {
      debugPrint('Error in getMostProfitableCurrencies: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
      }
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getStat({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 5,
  }) async {
    try {
      final fromDateStr = startDate.toIso8601String();
      final toDateStr = endDate.toIso8601String();

      debugPrint('Fetching currency statistics from $fromDateStr to $toDateStr from history collection');

      // Query the history collection directly instead of archive
      final historyQuery = await _firestore.collection(collectionHistory)
          .where('created_at', isGreaterThanOrEqualTo: fromDateStr)
          .where('created_at', isLessThanOrEqualTo: toDateStr)
          .get();
      
      debugPrint('Found ${historyQuery.docs.length} history entries for calculation');
      
      // Maps to track statistics by currency
      final Map<String, Map<String, dynamic>> currencyStats = {};
      
      // Process each history entry
      for (var doc in historyQuery.docs) {
        final data = doc.data();
        final currencyCode = data['currency_code'] as String;
        final operationType = data['operation_type'] as String;
        final rate = _safeDouble(data['rate']);
        final quantity = _safeDouble(data['quantity']);
        final total = _safeDouble(data['total']);
        
        // Skip SOM for direct calculations
        if (currencyCode == 'SOM') continue;
        
        // Initialize currency stats if needed
        if (!currencyStats.containsKey(currencyCode)) {
          currencyStats[currencyCode] = {
            'purchase_count': 0,
            'sale_count': 0,
            'total_purchased': 0.0,
            'total_purchase_amount': 0.0,
            'total_sold': 0.0,
            'total_sale_amount': 0.0,
          };
        }
        
        // Aggregate data based on operation type
        if (operationType == 'Buy' || operationType == 'Purchase') {
          currencyStats[currencyCode]!['purchase_count'] = (currencyStats[currencyCode]!['purchase_count'] ?? 0) + 1;
          currencyStats[currencyCode]!['total_purchased'] = (currencyStats[currencyCode]!['total_purchased'] ?? 0.0) + quantity;
          currencyStats[currencyCode]!['total_purchase_amount'] = (currencyStats[currencyCode]!['total_purchase_amount'] ?? 0.0) + total;
        } else if (operationType == 'Sell' || operationType == 'Sale') {
          currencyStats[currencyCode]!['sale_count'] = (currencyStats[currencyCode]!['sale_count'] ?? 0) + 1;
          currencyStats[currencyCode]!['total_sold'] = (currencyStats[currencyCode]!['total_sold'] ?? 0.0) + quantity;
          currencyStats[currencyCode]!['total_sale_amount'] = (currencyStats[currencyCode]!['total_sale_amount'] ?? 0.0) + total;
        }
      }

      // Convert to format needed for the UI
      final List<Map<String, dynamic>> resultData = [];
      
      // Get current currencies for display
      final currencies = await getAllCurrencies();
      
      for (var currency in currencies) {
        final currencyCode = currency.code!;
        
        // Skip SOM
        if (currencyCode == 'SOM') continue;
        
        // Get stats or initialize with zeros if no transactions found
        final stats = currencyStats[currencyCode] ?? {
          'purchase_count': 0,
          'sale_count': 0,
          'total_purchased': 0.0,
          'total_purchase_amount': 0.0,
          'total_sold': 0.0,
          'total_sale_amount': 0.0,
        };
        
        // Calculate averages and profit
        final totalPurchased = _safeDouble(stats['total_purchased']);
        final totalPurchaseAmount = _safeDouble(stats['total_purchase_amount']);
        final totalSold = _safeDouble(stats['total_sold']);
        final totalSaleAmount = _safeDouble(stats['total_sale_amount']);
        
        final avgPurchaseRate = totalPurchased > 0 ? totalPurchaseAmount / totalPurchased : 0.0;
        final avgSaleRate = totalSold > 0 ? totalSaleAmount / totalSold : 0.0;
        
        // Calculate cost of sold units (using average purchase rate)
        final costOfSold = totalSold * avgPurchaseRate;
        
        // Profit = (Sale amount) - (Cost of units sold)
        final profit = totalSaleAmount - costOfSold;
        
        resultData.add({
          'currency_code': currencyCode,
          'amount': profit,
          'avg_purchase_rate': avgPurchaseRate,
          'avg_sale_rate': avgSaleRate,
          'total_purchased': totalPurchased,
          'total_sold': totalSold,
          'cost_of_sold': costOfSold,
          'total_purchase_amount': totalPurchaseAmount,
          'total_sale_amount': totalSaleAmount,
          'purchase_count': stats['purchase_count'] ?? 0,
          'sale_count': stats['sale_count'] ?? 0,
        });
        
        // Debug output
        debugPrint('History Stats - ${currencyCode}: ' +
            'avgPurchase=$avgPurchaseRate, ' +
            'avgSale=$avgSaleRate, ' +
            'totalPurchased=$totalPurchased, ' +
            'totalSold=$totalSold, ' +
            'purchaseAmount=$totalPurchaseAmount, ' +
            'saleAmount=$totalSaleAmount, ' +
            'profit=$profit'
        );
      }

      // Sort by profit and limit
      resultData.sort((a, b) => (_safeDouble(b['amount']) - _safeDouble(a['amount'])).toInt());
      
      debugPrint('Found ${resultData.length} currencies with data from history');
      if (resultData.isNotEmpty) {
        debugPrint('Most profitable: ${resultData.first['currency_code']}, profit: ${resultData.first['amount']}');
      }

      if (limit > 0 && resultData.length > limit) {
        return resultData.sublist(0, limit);
      }

      return resultData;
    } catch (e) {
      debugPrint('Error in getStat: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
      }
      return [];
    }
  }
}

// Extension methods for model copying
extension CurrencyModelCopy on CurrencyModel {
  CurrencyModel copyWith({
    String? id,
    String? code,
    double? quantity,
    DateTime? updatedAt,
    double? defaultBuyRate,
    double? defaultSellRate,
  }) {
    return CurrencyModel(
      id: id != null ? int.tryParse(id) : this.id,
      code: code ?? this.code,
      quantity: quantity ?? this.quantity,
      updatedAt: updatedAt ?? this.updatedAt,
      defaultBuyRate: defaultBuyRate ?? this.defaultBuyRate,
      defaultSellRate: defaultSellRate ?? this.defaultSellRate,
    );
  }
}

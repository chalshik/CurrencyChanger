import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // Private constructor
  DatabaseHelper._init();

  // Collections
  static const String collectionCurrencies = 'currencies';
  static const String collectionHistory = 'history';
  static const String collectionUsers = 'users';

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
    } catch (e) {
      debugPrint('Error in deleteCurrency: $e');
      rethrow;
    }
  }

  Future<List<CurrencyModel>> getAllCurrencies() async {
    try {
      // Get all currencies from Firestore
      final snapshot = await _firestore.collection(collectionCurrencies).get();

      // Convert Firestore documents to CurrencyModel objects
      final currencies =
          snapshot.docs
              .map((doc) => CurrencyModel.fromFirestore(doc.data(), doc.id))
              .toList();

      return currencies;
    } catch (e) {
      debugPrint('Error getting all currencies: $e');
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
      // Clear history collection
      await _firestore.collection(collectionHistory).get().then((
        snapshot,
      ) async {
        for (var doc in snapshot.docs) {
          await doc.reference.delete();
        }
      });

      // Reset ALL currencies to 0, including SOM
      final currenciesSnapshot =
          await _firestore.collection(collectionCurrencies).get();
      for (var doc in currenciesSnapshot.docs) {
        await doc.reference.update({
          'quantity': 0.0,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      debugPrint(
        'Transaction history reset. All currency quantities reset to 0. Users preserved.',
      );
    } catch (e) {
      debugPrint('Error in resetAllData: $e');
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
      final profitData = await getMostProfitableCurrencies(
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

      final fromDateStr = fromDate.toIso8601String();
      final toDateStr = toDate.toIso8601String();

      debugPrint('Fetching data from $fromDateStr to $toDateStr');

      // Get all transactions within the date range
      final querySnapshot =
          await _firestore
              .collection(collectionHistory)
              .where('created_at', isGreaterThanOrEqualTo: fromDateStr)
              .where('created_at', isLessThanOrEqualTo: toDateStr)
              .get();

      debugPrint('Found ${querySnapshot.docs.length} total transactions');

      // Process purchase data
      final Map<String, Map<String, dynamic>> purchaseData = {};
      // Process sales data
      final Map<String, Map<String, dynamic>> salesData = {};

      // Process all transactions
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final operationType = data['operation_type'] as String;
        final currencyCode = data['currency_code'] as String;
        final total = _safeDouble(data['total']);

        // Skip if currency code is SOM
        if (currencyCode == 'SOM') continue;

        // Process based on operation type
        if (operationType == 'Purchase') {
          if (!purchaseData.containsKey(currencyCode)) {
            purchaseData[currencyCode] = {
              'currency': currencyCode,
              'total_value': 0.0,
              'count': 0,
            };
          }
          purchaseData[currencyCode]!['total_value'] =
              _safeDouble(purchaseData[currencyCode]!['total_value']) + total;
          purchaseData[currencyCode]!['count'] =
              _safeDouble(purchaseData[currencyCode]!['count']) + 1;
        } else if (operationType == 'Sale') {
          if (!salesData.containsKey(currencyCode)) {
            salesData[currencyCode] = {
              'currency': currencyCode,
              'total_value': 0.0,
              'count': 0,
            };
          }
          salesData[currencyCode]!['total_value'] =
              _safeDouble(salesData[currencyCode]!['total_value']) + total;
          salesData[currencyCode]!['count'] =
              _safeDouble(salesData[currencyCode]!['count']) + 1;
        }
      }

      // Convert to lists and sort by total_value
      final purchases =
          purchaseData.values.toList()..sort(
            (a, b) =>
                (_safeDouble(b['total_value']) - _safeDouble(a['total_value']))
                    .toInt(),
          );

      final sales =
          salesData.values.toList()..sort(
            (a, b) =>
                (_safeDouble(b['total_value']) - _safeDouble(a['total_value']))
                    .toInt(),
          );

      debugPrint('Processed ${purchases.length} purchase currencies');
      debugPrint('Processed ${sales.length} sales currencies');

      if (purchases.isNotEmpty) {
        debugPrint('Sample purchase data: ${purchases.first}');
        debugPrint(
          'All purchase currencies: ${purchases.map((p) => p['currency']).join(', ')}',
        );
      }
      if (sales.isNotEmpty) {
        debugPrint('Sample sales data: ${sales.first}');
      }

      return {'purchases': purchases, 'sales': sales};
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
      final fromDateStr = startDate.toIso8601String();
      final toDateStr = endDate.toIso8601String();

      debugPrint('Fetching daily data from $fromDateStr to $toDateStr');

      // Get ALL transactions without complex queries
      final querySnapshot =
          await _firestore.collection(collectionHistory).get();

      debugPrint('Total history records: ${querySnapshot.docs.length}');

      // Group transactions by date first
      final Map<String, Map<String, dynamic>> dailyData = {};

      // Process all transactions and filter by date in code
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final createdAt = data['created_at'] as String;

        // Parse the date string to DateTime for comparison
        final transactionDate = DateTime.parse(createdAt);

        // Skip if outside the date range
        if (transactionDate.isBefore(startDate) ||
            transactionDate.isAfter(endDate)) {
          continue;
        }

        final date = createdAt.substring(
          0,
          10,
        ); // Extract date part (YYYY-MM-DD)
        final operationType = data['operation_type'] as String;
        final currencyCode = data['currency_code'] as String;
        final total = _safeDouble(data['total']);
        final quantity = _safeDouble(data['quantity']);

        // Skip if currency code is SOM
        if (currencyCode == 'SOM') continue;

        // Initialize daily data entry
        if (!dailyData.containsKey(date)) {
          dailyData[date] = {
            'day': date,
            'purchases': 0.0,
            'sales': 0.0,
            'profit': 0.0,
            'deposits': 0.0,
            'currencies': <String, Map<String, dynamic>>{},
          };
        }

        // Initialize currency entry for this day
        if (!(dailyData[date]!['currencies'] as Map).containsKey(
          currencyCode,
        )) {
          (dailyData[date]!['currencies'] as Map)[currencyCode] = {
            'currency': currencyCode,
            'purchase_amount': 0.0,
            'purchase_quantity': 0.0,
            'sale_amount': 0.0,
            'sale_quantity': 0.0,
            'count_purchase': 0,
            'count_sale': 0,
          };
        }

        // Add transaction data
        final currencyData =
            (dailyData[date]!['currencies'] as Map)[currencyCode]
                as Map<String, dynamic>;

        if (operationType == 'Purchase') {
          dailyData[date]!['purchases'] =
              (dailyData[date]!['purchases'] as double) + total;
          currencyData['purchase_amount'] =
              (currencyData['purchase_amount'] as double) + total;
          currencyData['purchase_quantity'] =
              (currencyData['purchase_quantity'] as double) + quantity;
          currencyData['count_purchase'] =
              (currencyData['count_purchase'] as int) + 1;
        } else if (operationType == 'Sale') {
          dailyData[date]!['sales'] =
              (dailyData[date]!['sales'] as double) + total;
          currencyData['sale_amount'] =
              (currencyData['sale_amount'] as double) + total;
          currencyData['sale_quantity'] =
              (currencyData['sale_quantity'] as double) + quantity;
          currencyData['count_sale'] = (currencyData['count_sale'] as int) + 1;
        } else if (operationType == 'Deposit') {
          dailyData[date]!['deposits'] =
              (dailyData[date]!['deposits'] as double) + total;
        }
      }

      // Now calculate profit based on selling cost only for sold currencies
      for (var date in dailyData.keys) {
        final dayData = dailyData[date]!;
        double dailyProfit = 0.0;

        debugPrint('Calculating profit for date: $date');

        // For each currency, calculate profit on the sold amount
        for (var currencyCode in (dayData['currencies'] as Map).keys) {
          final currencyData =
              (dayData['currencies'] as Map)[currencyCode]
                  as Map<String, dynamic>;
          final saleAmount = currencyData['sale_amount'] as double;
          final saleQuantity = currencyData['sale_quantity'] as double;

          debugPrint(
            '  Currency: $currencyCode, Sale Amount: $saleAmount, Sale Quantity: $saleQuantity',
          );

          if (saleQuantity > 0) {
            // Get average purchase rate for this currency up to this date
            // Instead of querying Firestore again, we'll use the data we already have
            double totalQuantity = 0.0;
            double totalAmount = 0.0;

            // Find all purchase transactions for this currency up to this date
            for (var doc in querySnapshot.docs) {
              final data = doc.data();
              final docDate = data['created_at'] as String;

              // Skip if after the current date
              if (docDate.compareTo('$date 23:59:59.999Z') > 0) continue;

              final docCurrencyCode = data['currency_code'] as String;
              final docOperationType = data['operation_type'] as String;

              // Only count purchase transactions for this currency
              if (docCurrencyCode == currencyCode &&
                  docOperationType == 'Purchase') {
                totalQuantity += _safeDouble(data['quantity']);
                totalAmount += _safeDouble(data['total']);
              }
            }

            final avgPurchaseRate =
                totalQuantity > 0 ? totalAmount / totalQuantity : 0.0;

            // Calculate cost of sold currency
            final costOfSold = saleQuantity * avgPurchaseRate;

            // Calculate profit for this currency on this day
            final currencyProfit = saleAmount - costOfSold;

            debugPrint(
              '    Avg Purchase Rate: $avgPurchaseRate, Cost of Sold: $costOfSold, Profit: $currencyProfit',
            );

            // Add to daily profit
            dailyProfit += currencyProfit;
          }
        }

        // Update daily profit
        dayData['profit'] = dailyProfit;
        debugPrint('  Total daily profit for $date: $dailyProfit');

        // Extra validation to ensure profit field is properly set
        if (!dayData.containsKey('profit') || dayData['profit'] == null) {
          debugPrint(
            '  WARNING: Profit field was null or missing, setting to 0.0',
          );
          dayData['profit'] = 0.0;
        }
      }

      // Convert to list and sort by date
      final formattedResult = dailyData.values.toList();
      formattedResult.sort(
        (a, b) => (a['day'] as String).compareTo(b['day'] as String),
      );

      if (formattedResult.isNotEmpty) {
        debugPrint('First day data: ${formattedResult.first}');
      }

      return formattedResult;
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
      final fromDateStr = startDate.toIso8601String();
      final toDateStr = endDate.toIso8601String();

      // Get all transactions for the date range
      final querySnapshot =
          await _firestore.collection(collectionHistory).get();

      // Process transactions locally
      final Map<String, Map<String, dynamic>> purchaseData = {};
      final Map<String, Map<String, dynamic>> salesData = {};

      // Group transactions by type and currency
      for (var doc in querySnapshot.docs) {
        final data = doc.data();

        // Check if the transaction is within our date range
        final createdAt = data['created_at'] as String;
        if (createdAt.compareTo(fromDateStr) < 0 ||
            createdAt.compareTo(toDateStr) > 0) {
          continue; // Skip transactions outside date range
        }

        final currencyCode = data['currency_code'] as String;
        final operationType = data['operation_type'] as String;
        final quantity = _safeDouble(data['quantity']);
        final rate = _safeDouble(data['rate']);
        final total = _safeDouble(data['total']);

        // Skip SOM currency for profit calculations
        if (currencyCode == 'SOM') continue;

        if (operationType == 'Purchase') {
          if (!purchaseData.containsKey(currencyCode)) {
            purchaseData[currencyCode] = {
              'currency_code': currencyCode,
              'total_quantity': 0.0,
              'total_spent': 0.0,
              'avg_rate': 0.0,
            };
          }
          purchaseData[currencyCode]!['total_quantity'] =
              _safeDouble(purchaseData[currencyCode]!['total_quantity']) +
              quantity;
          purchaseData[currencyCode]!['total_spent'] =
              _safeDouble(purchaseData[currencyCode]!['total_spent']) + total;
        } else if (operationType == 'Sale') {
          if (!salesData.containsKey(currencyCode)) {
            salesData[currencyCode] = {
              'currency_code': currencyCode,
              'total_quantity': 0.0,
              'total_earned': 0.0,
              'avg_rate': 0.0,
            };
          }
          salesData[currencyCode]!['total_quantity'] =
              _safeDouble(salesData[currencyCode]!['total_quantity']) +
              quantity;
          salesData[currencyCode]!['total_earned'] =
              _safeDouble(salesData[currencyCode]!['total_earned']) + total;
        }
      }

      // Calculate average rates properly: total amount ÷ total quantity
      for (var code in purchaseData.keys) {
        final totalQuantity = _safeDouble(
          purchaseData[code]!['total_quantity'],
        );
        final totalSpent = _safeDouble(purchaseData[code]!['total_spent']);
        purchaseData[code]!['avg_rate'] =
            totalQuantity > 0 ? totalSpent / totalQuantity : 0.0;

        // Debug purchases
        debugPrint(
          'Purchase - $code: totalSpent=$totalSpent, totalQuantity=$totalQuantity, avgRate=${purchaseData[code]!['avg_rate']}',
        );
      }

      for (var code in salesData.keys) {
        final totalQuantity = _safeDouble(salesData[code]!['total_quantity']);
        final totalEarned = _safeDouble(salesData[code]!['total_earned']);
        salesData[code]!['avg_rate'] =
            totalQuantity > 0 ? totalEarned / totalQuantity : 0.0;

        // Debug sales
        debugPrint(
          'Sale - $code: totalEarned=$totalEarned, totalQuantity=$totalQuantity, avgRate=${salesData[code]!['avg_rate']}',
        );
      }

      // Get all currency codes
      final Set<String> allCurrencyCodes = {};
      allCurrencyCodes.addAll(purchaseData.keys);
      allCurrencyCodes.addAll(salesData.keys);

      // Calculate profits locally
      final List<Map<String, dynamic>> profitData = [];

      for (var code in allCurrencyCodes) {
        final buyData =
            purchaseData[code] ??
            {'total_quantity': 0.0, 'total_spent': 0.0, 'avg_rate': 0.0};
        final sellData =
            salesData[code] ??
            {'total_quantity': 0.0, 'total_earned': 0.0, 'avg_rate': 0.0};

        final totalQuantityPurchased = _safeDouble(buyData['total_quantity']);
        final totalQuantitySold = _safeDouble(sellData['total_quantity']);
        final avgPurchaseRate = _safeDouble(buyData['avg_rate']);
        final avgSaleRate = _safeDouble(sellData['avg_rate']);

        // Calculate profit as (average sale - average purchase) * sold quantity
        final profit = (avgSaleRate - avgPurchaseRate) * totalQuantitySold;

        // Debug profit
        debugPrint(
          'Profit - $code: avgSaleRate=$avgSaleRate, avgPurchaseRate=$avgPurchaseRate, soldQty=$totalQuantitySold, profit=$profit',
        );

        final shouldAdd =
            true; // Include all currencies for statistics, even if no sales or purchases

        if (shouldAdd) {
          profitData.add({
            'currency_code': code,
            'amount': profit,
            'avg_purchase_rate': avgPurchaseRate,
            'avg_sale_rate': avgSaleRate,
            'total_purchased': totalQuantityPurchased,
            'total_sold': totalQuantitySold,
            'cost_of_sold': totalQuantitySold * avgPurchaseRate,
          });
        }
      }

      // Sort by profit and limit locally
      profitData.sort(
        (a, b) => (_safeDouble(b['amount']) - _safeDouble(a['amount'])).toInt(),
      );

      if (profitData.length > limit) {
        return profitData.sublist(0, limit);
      }

      return profitData;
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
      final fromDateStr = startDate.toIso8601String();
      final toDateStr = endDate.toIso8601String();

      debugPrint(
        'Fetching daily data for currency $currencyCode from $fromDateStr to $toDateStr',
      );

      // Get ALL transactions without complex queries
      final querySnapshot =
          await _firestore.collection(collectionHistory).get();

      debugPrint('Total history records: ${querySnapshot.docs.length}');

      // Group transactions by date
      final Map<String, Map<String, dynamic>> dailyData = {};

      // Process all transactions and filter by date and currency in code
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final createdAt = data['created_at'] as String;

        // Parse the date string to DateTime for comparison
        final transactionDate = DateTime.parse(createdAt);

        // Skip if outside the date range
        if (transactionDate.isBefore(startDate) ||
            transactionDate.isAfter(endDate)) {
          continue;
        }

        // Skip if not the requested currency
        final docCurrencyCode = data['currency_code'] as String;
        if (docCurrencyCode != currencyCode) {
          continue;
        }

        final date = createdAt.substring(
          0,
          10,
        ); // Extract date part (YYYY-MM-DD)
        final operationType = data['operation_type'] as String;
        final amount = _safeDouble(data['total']);
        final quantity = _safeDouble(data['quantity']);

        debugPrint(
          'Processing $date - $operationType: Amount=$amount, Quantity=$quantity',
        );

        // Initialize daily data entry
        if (!dailyData.containsKey(date)) {
          dailyData[date] = {
            'day': date,
            'purchases': 0.0,
            'purchase_quantity': 0.0,
            'sales': 0.0,
            'sale_quantity': 0.0,
            'profit': 0.0,
            'deposits': 0.0,
          };
        }

        // Add transaction data
        if (operationType == 'Purchase') {
          dailyData[date]!['purchases'] =
              (dailyData[date]!['purchases'] as double) + amount;
          dailyData[date]!['purchase_quantity'] =
              (dailyData[date]!['purchase_quantity'] as double) + quantity;
        } else if (operationType == 'Sale') {
          dailyData[date]!['sales'] =
              (dailyData[date]!['sales'] as double) + amount;
          dailyData[date]!['sale_quantity'] =
              (dailyData[date]!['sale_quantity'] as double) + quantity;
        } else if (operationType == 'Deposit') {
          dailyData[date]!['deposits'] =
              (dailyData[date]!['deposits'] as double) + amount;
        }
      }

      // Calculate profit for each day based on sold quantity
      for (var date in dailyData.keys) {
        final dayData = dailyData[date]!;
        final saleAmount = dayData['sales'] as double;
        final saleQuantity = dayData['sale_quantity'] as double;

        debugPrint(
          'Calculating profit for $date - Sale Amount: $saleAmount, Sale Quantity: $saleQuantity',
        );

        if (saleQuantity > 0) {
          // Get average purchase rate for this currency up to this date
          // Instead of querying Firestore again, we'll use the data we already have
          double totalQuantity = 0.0;
          double totalAmount = 0.0;

          // Find all purchase transactions for this currency up to this date
          for (var doc in querySnapshot.docs) {
            final data = doc.data();
            final docDate = data['created_at'] as String;

            // Skip if after the current date
            if (docDate.compareTo('$date 23:59:59.999Z') > 0) continue;

            final docCurrencyCode = data['currency_code'] as String;
            final docOperationType = data['operation_type'] as String;

            // Only count purchase transactions for this currency
            if (docCurrencyCode == currencyCode &&
                docOperationType == 'Purchase') {
              totalQuantity += _safeDouble(data['quantity']);
              totalAmount += _safeDouble(data['total']);
            }
          }

          final avgPurchaseRate =
              totalQuantity > 0 ? totalAmount / totalQuantity : 0.0;

          // Calculate cost of sold currency
          final costOfSold = saleQuantity * avgPurchaseRate;

          // Calculate profit for this currency on this day (sale amount minus cost of sold)
          final profit = saleAmount - costOfSold;
          dayData['profit'] = profit;

          debugPrint(
            '  Avg Purchase Rate: $avgPurchaseRate, Cost of Sold: $costOfSold, Profit: $profit',
          );
        } else {
          // If nothing was sold, profit is 0 (not negative)
          dayData['profit'] = 0.0;
          debugPrint('  No sales, profit is 0');
        }

        // Extra validation to ensure profit field is properly set
        if (!dayData.containsKey('profit') || dayData['profit'] == null) {
          debugPrint(
            '  WARNING: Profit field was null or missing, setting to 0.0',
          );
          dayData['profit'] = 0.0;
        }
      }

      // Convert to list and sort by date
      final formattedResult = dailyData.values.toList();
      formattedResult.sort(
        (a, b) => (a['day'] as String).compareTo(b['day'] as String),
      );

      if (formattedResult.isNotEmpty) {
        debugPrint('First day formatted data: ${formattedResult.first}');
      }

      return formattedResult;
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

        debugPrint('Currency $code quantity updated to: $newQuantity');
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
          debugPrint('Currency $code created with quantity: $amount');
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

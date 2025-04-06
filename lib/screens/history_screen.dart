import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';
import '../models/history.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<HistoryModel> _historyEntries = [];
  List<HistoryModel> _filteredEntries = [];
  bool _isLoading = true;
  int _netBalance = 0;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // Date filters
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  final TextEditingController _fromDateController = TextEditingController();
  final TextEditingController _toDateController = TextEditingController();

  // Other filters
  String? _selectedCurrency;
  String? _selectedOperationType;
  List<String> _currencyCodes = [];
  List<String> _operationTypes = [];

  // Controllers for edit dialog
  final TextEditingController _editQuantityController = TextEditingController();
  final TextEditingController _editRateController = TextEditingController();
  final TextEditingController _editDateController = TextEditingController();
  String? _editOperationType;
  String? _editCurrencyCode;

  @override
  void initState() {
    super.initState();
    _fromDateController.text = DateFormat('dd/MM/yy').format(_fromDate);
    _toDateController.text = DateFormat('dd/MM/yy').format(_toDate);
    _loadFilters();
    _loadHistory();
    _searchController.addListener(_filterEntries);
  }

  @override
  void dispose() {
    _fromDateController.dispose();
    _toDateController.dispose();
    _editQuantityController.dispose();
    _editRateController.dispose();
    _editDateController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFilters() async {
    try {
      final currencies = await _dbHelper.getHistoryCurrencyCodes();
      final operations = await _dbHelper.getHistoryOperationTypes();

      if (mounted) {
        setState(() {
          _currencyCodes = currencies;
          _operationTypes = operations;
        });
      }
    } catch (e) {
      debugPrint('Error loading filters: $e');
    }
  }

  void _filterEntries() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredEntries = List.from(_historyEntries);
      });
      return;
    }

    setState(() {
      _filteredEntries =
          _historyEntries.where((entry) {
            // Search by currency code or operation type
            final basicMatch =
                entry.currencyCode.toLowerCase().contains(query) ||
                entry.operationType.toLowerCase().contains(query);

            // Search by amount - check if query is part of formatted amount string
            final amountString = entry.quantity.toStringAsFixed(2);
            final totalString = entry.total.toStringAsFixed(2);
            final amountMatch =
                amountString.contains(query) || totalString.contains(query);

            return basicMatch || amountMatch;
          }).toList();
    });
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final fromDate = DateFormat('dd/MM/yy').parse(_fromDateController.text);
      final toDate = DateFormat('dd/MM/yy').parse(_toDateController.text);

      final adjustedToDate = DateTime(
        toDate.year,
        toDate.month,
        toDate.day,
        23,
        59,
        59,
      );

      final entries = await _dbHelper.getFilteredHistoryByDate(
        fromDate: fromDate,
        toDate: adjustedToDate,
        currencyCode:
            _selectedCurrency == null || _selectedCurrency!.isEmpty
                ? null
                : _selectedCurrency,
        operationType:
            _selectedOperationType == null || _selectedOperationType!.isEmpty
                ? null
                : _selectedOperationType,
      );

      if (!mounted) return;
      setState(() {
        _historyEntries = entries;
        _filteredEntries = List.from(entries);
        _isLoading = false;
        _calculateTotals();
      });
      _filterEntries();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _calculateTotals() {
    int balance = 0;
    for (var entry in _historyEntries) {
      if (entry.operationType == 'Purchase') {
        balance -= entry.total.toInt();
      } else if (entry.operationType == 'Sale') {
        balance += entry.total.toInt();
      } else if (entry.operationType == 'Deposit') {
        balance += entry.total.toInt();
      }
    }
    _netBalance = balance;
  }

  Future<void> _selectDate(BuildContext context, bool isFromDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isFromDate ? _fromDate : _toDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isFromDate) {
          _fromDate = picked;
          _fromDateController.text = DateFormat('dd/MM/yy').format(picked);
        } else {
          _toDate = picked;
          _toDateController.text = DateFormat('dd/MM/yy').format(picked);
        }
      });
      _loadHistory();
    }
  }

  void _resetFilters() {
    if (!mounted) return;

    setState(() {
      _fromDate = DateTime.now().subtract(const Duration(days: 30));
      _toDate = DateTime.now();
      _fromDateController.text = DateFormat('dd/MM/yy').format(_fromDate);
      _toDateController.text = DateFormat('dd/MM/yy').format(_toDate);
      _selectedCurrency = null;
      _selectedOperationType = null;
    });
    _loadHistory();
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    HistoryModel entry,
  ) async {
    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(_getTranslatedText("delete_transaction")),
            content: Text(
              _getTranslatedText("delete_transaction_confirm", {
                "type": entry.operationType.toLowerCase(),
              }),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_getTranslatedText("cancel")),
              ),
              TextButton(
                onPressed: () async {
                  await _dbHelper.deleteHistory(entry);
                  if (mounted) {
                    Navigator.pop(context);
                    _loadHistory();
                  }
                },
                child: Text(
                  _getTranslatedText("delete"),
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  void _confirmDelete(HistoryModel entry) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(_getTranslatedText("delete_transaction")),
            content: Text(
              _getTranslatedText("delete_transaction_confirm", {
                "type": entry.operationType.toLowerCase(),
              }),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_getTranslatedText("cancel")),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  _getTranslatedText("delete"),
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (shouldDelete == true) {
      await _dbHelper.deleteHistory(entry);
      if (mounted) {
        _loadHistory();
      }
    }
  }

  void _saveEditedEntry(HistoryModel oldEntry, HistoryModel newEntry) async {
    await _dbHelper.updateHistory(newHistory: newEntry, oldHistory: oldEntry);
    if (mounted) {
      Navigator.pop(context);
      _loadHistory();
    }
  }

  Future<void> _showEditDialog(BuildContext context, HistoryModel entry) async {
    _editQuantityController.text = entry.quantity.toStringAsFixed(2);
    _editRateController.text = entry.rate.toStringAsFixed(2);
    _editDateController.text = DateFormat(
      'dd/MM/yy HH:mm',
    ).format(entry.createdAt);
    _editOperationType = entry.operationType;
    _editCurrencyCode = entry.currencyCode;

    final DateTime initialDate = entry.createdAt;
    DateTime selectedDate = initialDate;

    final bool isDeposit = entry.operationType == 'Deposit';

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text(_getTranslatedText("edit_transaction")),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isDeposit) ...[
                        DropdownButtonFormField<String>(
                          value: _editOperationType,
                          decoration: InputDecoration(
                            labelText: _getTranslatedText("type"),
                          ),
                          items:
                              _operationTypes
                                  .where((type) => type != 'Deposit')
                                  .map((type) {
                                    return DropdownMenuItem<String>(
                                      value: type,
                                      child: Text(
                                        _getTranslatedText(type.toLowerCase()),
                                      ),
                                    );
                                  })
                                  .toList(),
                          onChanged: (value) {
                            setState(() {
                              _editOperationType = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _editCurrencyCode,
                          decoration: InputDecoration(
                            labelText: _getTranslatedText("currency"),
                          ),
                          items:
                              _currencyCodes.map((code) {
                                return DropdownMenuItem<String>(
                                  value: code,
                                  child: Text(code),
                                );
                              }).toList(),
                          onChanged:
                              isDeposit
                                  ? null
                                  : (value) {
                                    setState(() {
                                      _editCurrencyCode = value;
                                    });
                                  },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _editQuantityController,
                          decoration: InputDecoration(
                            labelText: _getTranslatedText("amount_label"),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _editRateController,
                          decoration: InputDecoration(
                            labelText: _getTranslatedText("rate"),
                          ),
                          keyboardType: TextInputType.number,
                          readOnly: isDeposit,
                        ),
                      ] else ...[
                        TextFormField(
                          controller: _editQuantityController,
                          decoration: InputDecoration(
                            labelText: _getTranslatedText("amount_label"),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "${_getTranslatedText("type")}: ${_getTranslatedText("deposit")}",
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "${_getTranslatedText("currency")}: ${entry.currencyCode}",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            final TimeOfDay? time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(selectedDate),
                            );
                            if (time != null) {
                              setState(() {
                                selectedDate = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                  time.hour,
                                  time.minute,
                                );
                                _editDateController.text = DateFormat(
                                  'dd/MM/yy HH:mm',
                                ).format(selectedDate);
                              });
                            }
                          }
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: _getTranslatedText("date_time"),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_editDateController.text),
                              const Icon(Icons.calendar_today),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _resetFilters();
                        },
                        child: Text(_getTranslatedText("reset_filters")),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(_getTranslatedText("cancel")),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: LinearGradient(
                            colors: [Colors.blue.shade400, Colors.blue.shade700],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _loadHistory();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size(50, 36),
                            elevation: 0,
                          ),
                          child: Text(
                            _getTranslatedText("apply"),
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width >= 600;
    final isLandscape = screenSize.width > screenSize.height;
    final isWideTablet = isTablet && isLandscape;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade600, Colors.blue.shade800],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title:
            _isSearching
                ? TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: _getTranslatedText("search_transactions"),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                    contentPadding: EdgeInsets.all(8.0),
                    filled: false,
                  ),
                  style: TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  autofocus: true,
                )
                : Text(
                    _getTranslatedText("transaction_history"),
                    style: TextStyle(color: Colors.white),
                  ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSummaryCard(),
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredEntries.isEmpty
                    ? _buildEmptyHistoryMessage()
                    : isWideTablet
                    ? _buildTabletHistoryTable()
                    : _buildMobileHistoryList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletFilters() {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: TextField(
            controller: _fromDateController,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: _getTranslatedText("from"),
              prefixIcon: const Icon(Icons.calendar_today, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            readOnly: true,
            onTap: () => _selectDate(context, true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: TextField(
            controller: _toDateController,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: _getTranslatedText("to"),
              prefixIcon: const Icon(Icons.calendar_today, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            readOnly: true,
            onTap: () => _selectDate(context, false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCurrency,
                hint: Text(_getTranslatedText("currency")),
                isExpanded: true,
                items: [
                  DropdownMenuItem<String>(
                    value: '',
                    child: Text(_getTranslatedText("all_currencies")),
                  ),
                  ..._currencyCodes.map((String currency) {
                    return DropdownMenuItem<String>(
                      value: currency,
                      child: Text(currency),
                    );
                  }).toList(),
                ],
                onChanged: (String? value) {
                  setState(() {
                    _selectedCurrency = value;
                  });
                  _loadHistory();
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedOperationType,
                hint: Text(_getTranslatedText("type")),
                isExpanded: true,
                items: [
                  DropdownMenuItem<String>(
                    value: '',
                    child: Text(_getTranslatedText("all_types")),
                  ),
                  ..._operationTypes.map((String type) {
                    return DropdownMenuItem<String>(
                      value: type,
                      child: Text(_getTranslatedText(type.toLowerCase())),
                    );
                  }).toList(),
                ],
                onChanged: (String? value) {
                  setState(() {
                    _selectedOperationType = value;
                  });
                  _loadHistory();
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _resetFilters,
          icon: const Icon(Icons.refresh),
          tooltip: _getTranslatedText("reset_filters"),
          color: Colors.blue.shade700,
        ),
      ],
    );
  }

  Widget _buildMobileFilters() {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: TextField(
            controller: _fromDateController,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: _getTranslatedText("from"),
              prefixIcon: const Icon(Icons.calendar_today, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            readOnly: true,
            onTap: () => _selectDate(context, true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: TextField(
            controller: _toDateController,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: _getTranslatedText("to"),
              prefixIcon: const Icon(Icons.calendar_today, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            readOnly: true,
            onTap: () => _selectDate(context, false),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _showFilterDialog,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:
                  (_selectedCurrency != null &&
                              _selectedCurrency!.isNotEmpty) ||
                          (_selectedOperationType != null &&
                              _selectedOperationType!.isNotEmpty)
                      ? Colors.blue.shade100
                      : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    (_selectedCurrency != null &&
                                _selectedCurrency!.isNotEmpty) ||
                            (_selectedOperationType != null &&
                                _selectedOperationType!.isNotEmpty)
                        ? Colors.blue.shade300
                        : Colors.grey.shade300,
              ),
            ),
            child: Icon(
              Icons.filter_list,
              color:
                  (_selectedCurrency != null &&
                              _selectedCurrency!.isNotEmpty) ||
                          (_selectedOperationType != null &&
                              _selectedOperationType!.isNotEmpty)
                      ? Colors.blue.shade700
                      : Colors.grey.shade600,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabletHistoryTable() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: DataTable(
          headingRowColor: MaterialStateProperty.resolveWith<Color>((
            Set<MaterialState> states,
          ) {
            return Theme.of(context).colorScheme.primary.withOpacity(0.1);
          }),
          dataRowMaxHeight: 60,
          columns: [
            DataColumn(
              label: Text(
                _getTranslatedText("date_time"),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                _getTranslatedText("currency"),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                _getTranslatedText("type"),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                _getTranslatedText("rate"),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                _getTranslatedText("amount_label"),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                _getTranslatedText("total"),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                _getTranslatedText("operation"),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          rows:
              _filteredEntries.map((entry) {
                final dateFormat = DateFormat('dd-MM-yy HH:mm');
                final formattedDate = dateFormat.format(entry.createdAt);
                final backgroundColor =
                    entry.operationType == 'Purchase'
                        ? Colors.red.shade50
                        : (entry.operationType == 'Sale'
                            ? Colors.green.shade50
                            : Colors.blue.shade50);

                return DataRow(
                  color: MaterialStateProperty.all(backgroundColor),
                  cells: [
                    DataCell(Text(formattedDate)),
                    DataCell(Text(entry.currencyCode)),
                    DataCell(
                      Text(
                        _getTranslatedText(entry.operationType.toLowerCase()),
                      ),
                    ),
                    DataCell(Text('${entry.rate.toStringAsFixed(2)}')),
                    DataCell(Text('${entry.quantity.toStringAsFixed(2)}')),
                    DataCell(
                      Text(
                        '${entry.total.toStringAsFixed(2)} SOM',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color:
                              entry.operationType == 'Purchase'
                                  ? Colors.red.shade700
                                  : (entry.operationType == 'Sale'
                                      ? Colors.green.shade700
                                      : Colors.blue.shade700),
                        ),
                      ),
                    ),
                    DataCell(
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: entry.operationType == 'Deposit' 
                                ? null // Disable edit button for deposit entries
                                : () => _showEditDialog(context, entry),
                          ),
                          GestureDetector(
                            onLongPress: () {
                              if (entry.operationType != 'Deposit') {
                                _showDeleteDialog(context, entry);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: entry.operationType != 'Deposit' 
                                  ? Icon(
                                      Icons.delete_outline,
                                      color: Colors.transparent,
                                      size: 0,
                                    ) 
                                  : SizedBox(width: 0),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildMobileHistoryList() {
    return ListView.builder(
      itemCount: _filteredEntries.length,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemBuilder: (context, index) {
        final entry = _filteredEntries[index];
        final dateFormat = DateFormat('dd-MM-yy HH:mm');
        final formattedDate = dateFormat.format(entry.createdAt);

        // Choose background color based on operation type
        Color backgroundColor;
        IconData operationIcon;
        Color iconColor;

        if (entry.operationType == 'Purchase') {
          backgroundColor = Colors.red.shade50;
          operationIcon = Icons.arrow_downward;
          iconColor = Colors.red.shade700;
        } else if (entry.operationType == 'Sale') {
          backgroundColor = Colors.green.shade50;
          operationIcon = Icons.arrow_upward;
          iconColor = Colors.green.shade700;
        } else {
          backgroundColor = Colors.blue.shade50;
          operationIcon = Icons.account_balance_wallet;
          iconColor = Colors.blue.shade700;
        }

        // Wrap Card with Dismissible for non-Deposit entries
        if (entry.operationType != 'Deposit') {
          return Dismissible(
            key: Key(entry.id.toString()),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20.0),
              color: Colors.red,
              child: const Icon(
                Icons.delete,
                color: Colors.white,
              ),
            ),
            confirmDismiss: (direction) async {
              return await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text(_getTranslatedText("delete_transaction")),
                    content: Text(
                      _getTranslatedText("delete_transaction_confirm", {
                        "type": entry.operationType.toLowerCase(),
                      }),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(_getTranslatedText("cancel")),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(
                          _getTranslatedText("delete"),
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
            onDismissed: (direction) {
              _dbHelper.deleteHistory(entry);
              setState(() {
                _filteredEntries.removeAt(index);
                _historyEntries.remove(entry);
                _calculateTotals();
              });
            },
            child: _buildHistoryCard(entry, backgroundColor, operationIcon, iconColor, formattedDate),
          );
        } else {
          return _buildHistoryCard(entry, backgroundColor, operationIcon, iconColor, formattedDate);
        }
      },
    );
  }

  // Helper method to build the history card
  Widget _buildHistoryCard(HistoryModel entry, Color backgroundColor, IconData operationIcon, Color iconColor, String formattedDate) {
    // Determine gradient colors based on operation type
    List<Color> gradientColors;
    if (entry.operationType == 'Purchase') {
      gradientColors = [Colors.red.shade50, Colors.red.shade100];
    } else if (entry.operationType == 'Sale') {
      gradientColors = [Colors.green.shade50, Colors.green.shade100];
    } else {
      gradientColors = [Colors.blue.shade50, Colors.blue.shade100];
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          onTap: entry.operationType == 'Deposit' 
              ? null // Disable tap for deposit entries
              : () {
                  _showEditDialog(context, entry);
                },
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                // Left side (icon and main content)
                Expanded(
                  child: Row(
                    children: [
                      // Icon
                      Container(
                        margin: const EdgeInsets.only(right: 12),
                        child: CircleAvatar(
                          backgroundColor: Colors.white.withOpacity(0.7),
                          child: Icon(operationIcon, color: iconColor),
                        ),
                      ),
                      // Main content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  entry.currencyCode,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  '${entry.total.toStringAsFixed(2)} SOM',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: iconColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _getTranslatedText(
                                    entry.operationType.toLowerCase(),
                                  ),
                                  style: TextStyle(
                                    color: iconColor,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '${_getTranslatedText("amount_label")}: ${entry.quantity.toStringAsFixed(2)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_getTranslatedText("rate")}: ${entry.rate.toStringAsFixed(2)}  |  $formattedDate',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Empty SizedBox instead of lock icon or spacer
                const SizedBox(width: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade600, Colors.blue.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade200.withOpacity(0.5),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getTranslatedText("net_som_balance"),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
              Text(
                '${_netBalance.toString()} SOM',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 0.5,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Divider(color: Colors.white.withOpacity(0.3), height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                _getTranslatedText("transactions"),
                _filteredEntries.length.toString(),
                Icons.swap_horiz,
              ),
              _buildStatItem(
                _getTranslatedText("currencies"),
                _currencyCodes.length.toString(),
                Icons.monetization_on,
              ),
              _buildStatItem(
                _getTranslatedText("date_range"),
                DateFormat('dd/MM/yy').format(_fromDate) + 
                ' - ' + 
                DateFormat('dd/MM/yy').format(_toDate),
                Icons.date_range,
                fontSize: 11,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon, {
    double fontSize = 14,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: fontSize,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyHistoryMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.history, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            _searchController.text.isNotEmpty
                ? _getTranslatedText("no_results", {
                  "query": _searchController.text,
                })
                : _getTranslatedText("no_transaction_history"),
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_searchController.text.isEmpty)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  colors: [Colors.blue.shade400, Colors.blue.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.shade200.withOpacity(0.5),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _resetFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text(
                  _getTranslatedText("reset_filters"),
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setStateDialog) => AlertDialog(
                  title: Text(_getTranslatedText("filter_history")),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getTranslatedText("date_range"),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _fromDateController,
                                style: TextStyle(fontSize: 15.5),
                                decoration: InputDecoration(
                                  labelText: _getTranslatedText("from"),
                                  labelStyle: TextStyle(fontSize: 16),
                                  suffixIcon: Icon(Icons.calendar_today, size: 20),
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                ),
                                readOnly: true,
                                onTap: () {
                                  _selectDate(dialogContext, true);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _toDateController,
                                style: TextStyle(fontSize: 15.5),
                                decoration: InputDecoration(
                                  labelText: _getTranslatedText("to"),
                                  labelStyle: TextStyle(fontSize: 12),
                                  suffixIcon: Icon(Icons.calendar_today, size: 20),
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                ),
                                readOnly: true,
                                onTap: () {
                                  _selectDate(dialogContext, false);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _getTranslatedText("currency"),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                          value: _selectedCurrency,
                          hint: Text(_getTranslatedText("all_currencies")),
                          isExpanded: true,
                          items: [
                            DropdownMenuItem<String>(
                              value: null,
                              child: Text(_getTranslatedText("all_currencies")),
                            ),
                            ..._currencyCodes.map((String code) {
                              return DropdownMenuItem<String>(
                                value: code,
                                child: Text(code),
                              );
                            }).toList(),
                          ],
                          onChanged: (value) {
                            setStateDialog(() {
                              _selectedCurrency = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _getTranslatedText("type"),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                          value: _selectedOperationType,
                          hint: Text(_getTranslatedText("all_types")),
                          isExpanded: true,
                          items: [
                            DropdownMenuItem<String>(
                              value: null,
                              child: Text(_getTranslatedText("all_types")),
                            ),
                            ..._operationTypes.map((String type) {
                              return DropdownMenuItem<String>(
                                value: type,
                                child: Text(
                                  _getTranslatedText(type.toLowerCase()),
                                ),
                              );
                            }).toList(),
                          ],
                          onChanged: (value) {
                            setStateDialog(() {
                              _selectedOperationType = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _resetFilters();
                          },
                          child: Text(_getTranslatedText("reset_filters")),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(_getTranslatedText("cancel")),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: LinearGradient(
                              colors: [Colors.blue.shade400, Colors.blue.shade700],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _loadHistory();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: Size(50, 36),
                              elevation: 0,
                            ),
                            child: Text(
                              _getTranslatedText("apply"),
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
}

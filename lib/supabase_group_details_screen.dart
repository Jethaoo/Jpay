import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'app_theme.dart';
import 'backend/backend_models.dart';
import 'backend/jpay_repository.dart';
import 'debt_calculations.dart';
import 'network_status.dart';
import 'services/receipt_scanner.dart';
import 'widgets/app_ui.dart';
import 'widgets/expense_maps.dart';
import 'widgets/group_name_dialog.dart';

class SupabaseGroupDetailsScreen extends StatefulWidget {
  final String groupId;
  final String initialName;
  final JpayRepository repository;

  const SupabaseGroupDetailsScreen({
    super.key,
    required this.groupId,
    required this.initialName,
    required this.repository,
  });

  @override
  State<SupabaseGroupDetailsScreen> createState() =>
      _SupabaseGroupDetailsScreenState();
}

class _SupabaseGroupDetailsScreenState
    extends State<SupabaseGroupDetailsScreen> {
  List<GroupFriendRecord> _latestFriends = const [];
  List<ExpenseRecord> _latestExpenses = const [];
  final _expenseSearchController = TextEditingController();
  Timer? _searchTimer;
  List<ExpenseRecord>? _searchResults;
  bool _searching = false;
  bool _showMap = false;
  String? _categoryFilter;
  bool? _proofFilter;
  String _merchantFilter = '';
  String _locationFilter = '';
  DateTimeRange? _dateFilter;

  bool get _hasDiscoveryFilter =>
      _expenseSearchController.text.trim().isNotEmpty ||
      _categoryFilter != null ||
      _proofFilter != null ||
      _merchantFilter.isNotEmpty ||
      _locationFilter.isNotEmpty ||
      _dateFilter != null;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _expenseSearchController.dispose();
    super.dispose();
  }

  Future<void> _renameGroup(String currentName) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          GroupNameDialog(title: 'Rename group', initialValue: currentName),
    );
    if (name == null || name == currentName) return;
    try {
      await widget.repository.renameGroup(widget.groupId, name);
    } catch (error) {
      _showError(error, 'rename this group');
    }
  }

  Future<void> _manageFriends() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ManageFriendsDialog(
        groupId: widget.groupId,
        repository: widget.repository,
        initialFriends: _latestFriends,
      ),
    );
  }

  Future<void> _addExpense(List<GroupFriendRecord> friends) async {
    if (friends.isEmpty) {
      await _manageFriends();
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _ExpenseEditorDialog(
          groupId: widget.groupId,
          repository: widget.repository,
          friends: friends,
        ),
      ),
    );
  }

  Future<void> _editExpense(
    ExpenseRecord expense,
    List<ExpenseShareRecord> shares,
    List<GroupFriendRecord> friends,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _ExpenseEditorDialog(
          groupId: widget.groupId,
          repository: widget.repository,
          friends: friends,
          expense: expense,
          existingShares: shares,
        ),
      ),
    );
  }

  ExpenseQuery get _expenseQuery => ExpenseQuery(
    text: _expenseSearchController.text,
    categoryId: _categoryFilter,
    merchant: _merchantFilter,
    location: _locationFilter,
    fromDate: _dateFilter?.start,
    toDate: _dateFilter == null
        ? null
        : DateTime(
            _dateFilter!.end.year,
            _dateFilter!.end.month,
            _dateFilter!.end.day,
            23,
            59,
            59,
          ),
    hasProof: _proofFilter,
    limit: 500,
  );

  void _scheduleSearch() {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), _refreshSearch);
  }

  Future<void> _refreshSearch() async {
    if (!_hasDiscoveryFilter) {
      if (mounted) setState(() => _searchResults = null);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await widget.repository.searchExpenses(
        widget.groupId,
        _expenseQuery,
      );
      if (mounted) setState(() => _searchResults = results);
    } catch (error) {
      _showError(error, 'search expense history');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _showFilters() async {
    final availableCategories = await widget.repository
        .watchExpenseCategories()
        .first;
    if (!mounted) return;
    final categories = orderExpenseCategoriesByUsage(
      availableCategories,
      _latestExpenses.map((expense) => expense.categoryId),
    );
    var category = _categoryFilter;
    var proof = _proofFilter;
    var merchant = _merchantFilter;
    var location = _locationFilter;
    var fieldRevision = 0;
    var dates = _dateFilter;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Filter expenses',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    ...categories.map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    ),
                  ],
                  onChanged: (value) => setSheetState(() => category = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<bool?>(
                  initialValue: proof,
                  decoration: const InputDecoration(labelText: 'Proof'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Any')),
                    DropdownMenuItem(value: true, child: Text('Has proof')),
                    DropdownMenuItem(value: false, child: Text('No proof')),
                  ],
                  onChanged: (value) => setSheetState(() => proof = value),
                ),
                const SizedBox(height: 12),
                _OwnedModalTextField(
                  key: ValueKey('merchant-$fieldRevision'),
                  initialValue: merchant,
                  label: 'Merchant',
                  onChanged: (value) => merchant = value,
                ),
                const SizedBox(height: 12),
                _OwnedModalTextField(
                  key: ValueKey('location-$fieldRevision'),
                  initialValue: location,
                  label: 'Location',
                  onChanged: (value) => location = value,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                      initialDateRange: dates,
                    );
                    if (picked != null) {
                      setSheetState(() => dates = picked);
                    }
                  },
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    dates == null
                        ? 'Any date'
                        : '${dates!.start.day}/${dates!.start.month}/${dates!.start.year}'
                              ' – ${dates!.end.day}/${dates!.end.month}/${dates!.end.year}',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setSheetState(() {
                          category = null;
                          proof = null;
                          dates = null;
                          merchant = '';
                          location = '';
                          fieldRevision++;
                        });
                      },
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      child: const Text('Apply filters'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == true && mounted) {
      setState(() {
        _categoryFilter = category;
        _proofFilter = proof;
        _merchantFilter = merchant.trim();
        _locationFilter = location.trim();
        _dateFilter = dates;
      });
      await _refreshSearch();
    }
  }

  Future<void> _deleteExpense(ExpenseRecord expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(
          'Delete “${expense.title}” permanently from expense history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppPalette.red),
            child: const Text('Delete expense'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteExpense(expense.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Expense deleted')));
    } catch (error) {
      _showError(error, 'delete this expense');
    }
  }

  Future<void> _openProofs(ExpenseRecord expense) async {
    try {
      final attachments = await widget.repository
          .watchExpenseAttachments(expense.id)
          .first;
      if (!mounted) return;
      if (attachments.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No proof images are attached.')),
        );
        return;
      }
      final urls = await Future.wait(
        attachments.map(
          (attachment) =>
              widget.repository.createExpenseProofUrl(attachment.storagePath),
        ),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: _ProofViewer(
            expenseTitle: expense.title,
            items: [
              for (var index = 0; index < attachments.length; index++)
                _ProofViewerItem(
                  filename: attachments[index].originalFilename,
                  sizeBytes: attachments[index].sizeBytes,
                  remoteUrl: urls[index],
                  scanReviewed: attachments[index].extraction != null,
                ),
            ],
          ),
        ),
      );
    } catch (error) {
      _showError(error, 'open expense proof');
    }
  }

  Future<void> _markSharePaid(ExpenseShareRecord share) async {
    try {
      final changed = await widget.repository.markExpenseSharePaid(share.id);
      if (!mounted || !changed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${share.friendName} marked as paid')),
      );
    } catch (error) {
      _showError(error, 'mark this share as paid');
    }
  }

  Future<void> _markFriendPaid(String name, double amount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark all as paid?'),
        content: Text(
          'Mark all outstanding shares for $name '
          '(RM ${amount.toStringAsFixed(2)}) as paid?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mark paid'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final paid = await widget.repository.markFriendSharesPaid(
        widget.groupId,
        name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('RM ${paid.toStringAsFixed(2)} settled')),
      );
    } catch (error) {
      _showError(error, 'settle these shares');
    }
  }

  void _showError(Object error, String action) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(networkAwareErrorMessage(error, action: action))),
    );
  }

  GroupRecord? _currentGroup(List<GroupRecord>? groups) {
    if (groups == null) return null;
    for (final group in groups) {
      if (group.id == widget.groupId) return group;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GroupRecord>>(
      stream: widget.repository.watchGroups(),
      builder: (context, groupSnapshot) {
        final group = _currentGroup(groupSnapshot.data);
        final groupName = group?.name ?? widget.initialName;
        return Scaffold(
          appBar: AppBar(
            title: Text(groupName),
            actions: [
              IconButton(
                onPressed: _manageFriends,
                tooltip: 'Manage friends',
                icon: const Icon(Icons.group_outlined),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'rename') _renameGroup(groupName);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Rename group'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addExpense(_latestFriends),
            icon: Icon(
              _latestFriends.isEmpty
                  ? Icons.group_add_outlined
                  : Icons.add_rounded,
            ),
            label: Text(_latestFriends.isEmpty ? 'Add friends' : 'Add expense'),
          ),
          body: StreamBuilder<List<GroupFriendRecord>>(
            stream: widget.repository.watchFriends(widget.groupId),
            builder: (context, friendSnapshot) {
              if (friendSnapshot.hasError) {
                return _LoadError(
                  message: networkAwareErrorMessage(
                    friendSnapshot.error!,
                    action: 'load group friends',
                  ),
                );
              }
              if (!friendSnapshot.hasData) {
                return const AppLoadingList(itemCount: 4);
              }
              final friends = friendSnapshot.data!;
              _latestFriends = friends;
              return StreamBuilder<List<ExpenseRecord>>(
                stream: widget.repository.watchExpenses(widget.groupId),
                builder: (context, expenseSnapshot) {
                  if (expenseSnapshot.hasError) {
                    return _LoadError(
                      message: networkAwareErrorMessage(
                        expenseSnapshot.error!,
                        action: 'load expense history',
                      ),
                    );
                  }
                  if (!expenseSnapshot.hasData) {
                    return const AppLoadingList(itemCount: 4);
                  }
                  final expenses = expenseSnapshot.data!;
                  _latestExpenses = expenses;
                  return StreamBuilder<List<ExpenseShareRecord>>(
                    stream: widget.repository.watchAllExpenseShares(),
                    builder: (context, shareSnapshot) {
                      if (shareSnapshot.hasError) {
                        return _LoadError(
                          message: networkAwareErrorMessage(
                            shareSnapshot.error!,
                            action: 'load expense shares',
                          ),
                        );
                      }
                      if (!shareSnapshot.hasData) {
                        return const AppLoadingList(itemCount: 4);
                      }
                      final expenseIds = expenses
                          .map((expense) => expense.id)
                          .toSet();
                      final shares = shareSnapshot.data!
                          .where(
                            (share) => expenseIds.contains(share.expenseId),
                          )
                          .toList();
                      return _buildGroupContent(friends, expenses, shares);
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildGroupContent(
    List<GroupFriendRecord> friends,
    List<ExpenseRecord> expenses,
    List<ExpenseShareRecord> shares,
  ) {
    final visibleExpenses = _searchResults ?? expenses;
    final hasLocatedExpenses = visibleExpenses.any(
      (expense) => expense.location != null,
    );
    final balances = <String, _FriendBalance>{};
    for (final share in shares) {
      if (share.paid) continue;
      final key = share.friendName.trim().toLowerCase();
      final existing = balances[key];
      balances[key] = _FriendBalance(
        name: existing?.name ?? share.friendName,
        amount: roundCurrency((existing?.amount ?? 0) + share.amount),
      );
    }
    final balanceList = balances.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final outstandingTotal = balanceList.fold<double>(
      0,
      (total, balance) => total + balance.amount,
    );

    final sharesByExpense = <String, List<ExpenseShareRecord>>{};
    for (final share in shares) {
      sharesByExpense.putIfAbsent(share.expenseId, () => []).add(share);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF202A33), AppPalette.surface],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppPalette.blue.withValues(alpha: 0.42)),
          ),
          child: ExpansionTile(
            initiallyExpanded: false,
            maintainState: true,
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.fromLTRB(18, 9, 14, 9),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            iconColor: Colors.white,
            collapsedIconColor: Colors.white,
            leading: const Icon(
              Icons.account_balance_wallet_outlined,
              color: Colors.white,
            ),
            title: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Outstanding to you',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'RM ${outstandingTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: balanceList.isEmpty
                        ? AppPalette.green
                        : AppPalette.orange,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              balanceList.isEmpty
                  ? 'Everyone is settled'
                  : '${balanceList.length} ${balanceList.length == 1 ? 'friend has' : 'friends have'} unpaid shares',
              style: TextStyle(
                color: balanceList.isEmpty
                    ? AppPalette.green
                    : Colors.white.withValues(alpha: 0.72),
              ),
            ),
            children: balanceList.isEmpty
                ? const [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 18),
                      child: Text(
                        'No outstanding shares.',
                        style: TextStyle(color: AppPalette.secondaryLabel),
                      ),
                    ),
                  ]
                : balanceList
                      .map(
                        (balance) => Container(
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 17,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.15,
                              ),
                              child: Text(
                                balance.name[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(
                              balance.name,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              'RM ${balance.amount.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            trailing: TextButton(
                              onPressed: () =>
                                  _markFriendPaid(balance.name, balance.amount),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Settle'),
                            ),
                          ),
                        ),
                      )
                      .toList(),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Expense history',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: _manageFriends,
              icon: const Icon(Icons.group_outlined, size: 18),
              label: Text(
                '${friends.length} ${friends.length == 1 ? 'friend' : 'friends'}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _expenseSearchController,
          textInputAction: TextInputAction.search,
          onChanged: (_) => _scheduleSearch(),
          onSubmitted: (_) => _refreshSearch(),
          decoration: InputDecoration(
            hintText: 'Search merchant, place, notes or receipt',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _expenseSearchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _expenseSearchController.clear();
                      _refreshSearch();
                    },
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: _showFilters,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(_hasDiscoveryFilter ? 'Edit filters' : 'Filter'),
            ),
            if (_searching) ...[
              const SizedBox(width: 12),
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
            const Spacer(),
            if (hasLocatedExpenses)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.view_list_rounded),
                    tooltip: 'List view',
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.map_outlined),
                    tooltip: 'Map view',
                  ),
                ],
                selected: {_showMap},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _showMap = selection.first);
                },
              ),
          ],
        ),
        if (_hasDiscoveryFilter) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildActiveFilters(expenses),
        ],
        const SizedBox(height: 12),
        if (visibleExpenses.isEmpty)
          _hasDiscoveryFilter
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      'No expenses match this search.',
                      style: TextStyle(color: AppPalette.secondaryLabel),
                    ),
                  ),
                )
              : _EmptyExpenseState(hasFriends: friends.isNotEmpty)
        else if (_showMap && hasLocatedExpenses)
          ExpenseHistoryMap(
            expenses: visibleExpenses,
            onSelected: (expense) {
              final expenseShares = sharesByExpense[expense.id] ?? const [];
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (context) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: _ExpenseHistoryCard(
                    expense: expense,
                    shares: expenseShares,
                    onEdit: () {
                      Navigator.pop(context);
                      _editExpense(expense, expenseShares, friends);
                    },
                    onDelete: () {
                      Navigator.pop(context);
                      _deleteExpense(expense);
                    },
                    onMarkPaid: _markSharePaid,
                    onOpenProof: () => _openProofs(expense),
                  ),
                ),
              );
            },
          )
        else
          ...visibleExpenses.map((expense) {
            final expenseShares = sharesByExpense[expense.id] ?? const [];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ExpenseHistoryCard(
                expense: expense,
                shares: expenseShares,
                onEdit: () => _editExpense(expense, expenseShares, friends),
                onDelete: () => _deleteExpense(expense),
                onMarkPaid: _markSharePaid,
                onOpenProof: () => _openProofs(expense),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildActiveFilters(List<ExpenseRecord> expenses) {
    String? categoryName;
    if (_categoryFilter != null) {
      for (final expense in expenses) {
        if (expense.categoryId == _categoryFilter) {
          categoryName = expense.categoryName;
          break;
        }
      }
    }
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        if (_expenseSearchController.text.trim().isNotEmpty)
          InputChip(
            label: Text('“${_expenseSearchController.text.trim()}”'),
            avatar: const Icon(Icons.search_rounded, size: 16),
            onDeleted: () {
              _expenseSearchController.clear();
              _refreshSearch();
            },
          ),
        if (_categoryFilter != null)
          InputChip(
            label: Text(categoryName ?? 'Category'),
            avatar: const Icon(Icons.category_outlined, size: 16),
            onDeleted: () {
              setState(() => _categoryFilter = null);
              _refreshSearch();
            },
          ),
        if (_proofFilter != null)
          InputChip(
            label: Text(_proofFilter! ? 'Has proof' : 'No proof'),
            avatar: const Icon(Icons.attach_file_rounded, size: 16),
            onDeleted: () {
              setState(() => _proofFilter = null);
              _refreshSearch();
            },
          ),
        if (_merchantFilter.isNotEmpty)
          InputChip(
            label: Text(_merchantFilter),
            avatar: const Icon(Icons.storefront_outlined, size: 16),
            onDeleted: () {
              setState(() => _merchantFilter = '');
              _refreshSearch();
            },
          ),
        if (_locationFilter.isNotEmpty)
          InputChip(
            label: Text(_locationFilter),
            avatar: const Icon(Icons.place_outlined, size: 16),
            onDeleted: () {
              setState(() => _locationFilter = '');
              _refreshSearch();
            },
          ),
        if (_dateFilter != null)
          InputChip(
            label: Text(
              '${_dateFilter!.start.day}/${_dateFilter!.start.month}–'
              '${_dateFilter!.end.day}/${_dateFilter!.end.month}',
            ),
            avatar: const Icon(Icons.date_range_outlined, size: 16),
            onDeleted: () {
              setState(() => _dateFilter = null);
              _refreshSearch();
            },
          ),
      ],
    );
  }
}

class _OwnedModalTextField extends StatefulWidget {
  final String initialValue;
  final String label;
  final ValueChanged<String> onChanged;

  const _OwnedModalTextField({
    super.key,
    required this.initialValue,
    required this.label,
    required this.onChanged,
  });

  @override
  State<_OwnedModalTextField> createState() => _OwnedModalTextFieldState();
}

class _OwnedModalTextFieldState extends State<_OwnedModalTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      decoration: InputDecoration(labelText: widget.label),
    );
  }
}

class _FriendBalance {
  final String name;
  final double amount;

  const _FriendBalance({required this.name, required this.amount});
}

class _ExpenseHistoryCard extends StatelessWidget {
  final ExpenseRecord expense;
  final List<ExpenseShareRecord> shares;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<ExpenseShareRecord> onMarkPaid;
  final VoidCallback onOpenProof;

  const _ExpenseHistoryCard({
    required this.expense,
    required this.shares,
    required this.onEdit,
    required this.onDelete,
    required this.onMarkPaid,
    required this.onOpenProof,
  });

  @override
  Widget build(BuildContext context) {
    final allPaid = shares.isNotEmpty && shares.every((share) => share.paid);
    final localDate = expense.expenseDate.toLocal();
    final date =
        '${localDate.day.toString().padLeft(2, '0')}/'
        '${localDate.month.toString().padLeft(2, '0')}/${localDate.year}';
    final chargeParts = <String>[
      if (expense.taxAmount > 0)
        'RM ${expense.taxAmount.toStringAsFixed(2)} tax',
      if (expense.serviceAmount > 0)
        'RM ${expense.serviceAmount.toStringAsFixed(2)} service',
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(
          backgroundColor: allPaid
              ? AppPalette.greenContainer
              : AppPalette.blueContainer,
          child: Icon(
            allPaid ? Icons.check_rounded : Icons.receipt_long_outlined,
            color: allPaid ? AppPalette.green : AppPalette.blue,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                expense.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'RM ${expense.totalWithCharges.toStringAsFixed(2)}',
              maxLines: 1,
              style: TextStyle(
                color: allPaid ? AppPalette.secondaryLabel : AppPalette.label,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
        subtitle: Text(
          [
            date,
            if (expense.merchant.isNotEmpty) expense.merchant,
            expense.categoryName,
            '${shares.length} ${shares.length == 1 ? 'person' : 'people'}',
          ].join(' · '),
        ),
        children: [
          if (allPaid)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AppStatusPill(
                  label: 'All paid',
                  foreground: AppPalette.green,
                  background: AppPalette.greenContainer,
                  icon: Icons.check_rounded,
                ),
              ),
            ),
          if (expense.notes.isNotEmpty ||
              expense.location != null ||
              expense.attachmentCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (expense.location != null)
                      Chip(
                        avatar: const Icon(Icons.place_outlined, size: 17),
                        label: Text(expense.location!.label),
                      ),
                    if (expense.attachmentCount > 0)
                      ActionChip(
                        onPressed: onOpenProof,
                        avatar: const Icon(Icons.attach_file_rounded, size: 17),
                        label: Text(
                          '${expense.attachmentCount} '
                          '${expense.attachmentCount == 1 ? 'proof' : 'proofs'}',
                        ),
                      ),
                    if (expense.notes.isNotEmpty)
                      Chip(
                        avatar: const Icon(Icons.notes_outlined, size: 17),
                        label: Text(
                          expense.notes,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (chargeParts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Includes ${chargeParts.join(' • ')}',
                  style: const TextStyle(
                    color: AppPalette.secondaryLabel,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ...shares.map(
            (share) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Icon(
                share.paid
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: share.paid
                    ? AppPalette.green
                    : AppPalette.secondaryLabel,
              ),
              title: Text(share.friendName),
              subtitle: share.description.isEmpty
                  ? Text(share.paid ? 'Paid' : 'Outstanding')
                  : Text(share.description),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'RM ${share.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: share.paid
                          ? AppPalette.secondaryLabel
                          : AppPalette.label,
                      fontWeight: FontWeight.w600,
                      decoration: share.paid
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  if (!share.paid)
                    IconButton(
                      onPressed: () => onMarkPaid(share),
                      tooltip: 'Mark paid',
                      icon: const Icon(
                        Icons.done_rounded,
                        color: AppPalette.green,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  onPressed: onDelete,
                  tooltip: 'Delete expense',
                  color: AppPalette.red,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyExpenseState extends StatelessWidget {
  final bool hasFriends;

  const _EmptyExpenseState({required this.hasFriends});

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: hasFriends ? Icons.receipt_long_outlined : Icons.group_add_outlined,
      title: hasFriends ? 'No expenses yet' : 'Add friends first',
      message: hasFriends
          ? 'Tap Add expense to record the first one.'
          : 'Use Manage friends before recording an expense.',
    );
  }
}

class _ManageFriendsDialog extends StatefulWidget {
  final String groupId;
  final JpayRepository repository;
  final List<GroupFriendRecord> initialFriends;

  const _ManageFriendsDialog({
    required this.groupId,
    required this.repository,
    required this.initialFriends,
  });

  @override
  State<_ManageFriendsDialog> createState() => _ManageFriendsDialogState();
}

class _ManageFriendsDialogState extends State<_ManageFriendsDialog> {
  final _nameController = TextEditingController();
  late List<GroupFriendRecord> _friends;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _friends = [...widget.initialFriends]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (_friends.any(
      (friend) => friend.name.toLowerCase() == name.toLowerCase(),
    )) {
      _showMessage('That friend is already in this group.');
      return;
    }
    setState(() => _saving = true);
    try {
      final friend = await widget.repository.addFriend(widget.groupId, name);
      if (!mounted) return;
      setState(() {
        _friends.add(friend);
        _friends.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        _nameController.clear();
      });
    } catch (error) {
      _showMessage(networkAwareErrorMessage(error, action: 'add this friend'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(GroupFriendRecord friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text(
          'Remove ${friend.name} from future participant selection? '
          'Existing expense history is preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppPalette.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.removeFriend(friend.id);
      if (!mounted) return;
      setState(() => _friends.removeWhere((item) => item.id == friend.id));
    } catch (error) {
      _showMessage(
        networkAwareErrorMessage(error, action: 'remove this friend'),
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage friends'),
          actions: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppPalette.blueContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_friends.length}',
                  style: const TextStyle(
                    color: AppPalette.blue,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        autofocus: _friends.isEmpty,
                        maxLength: 80,
                        textCapitalization: TextCapitalization.words,
                        onSubmitted: (_) => _saving ? null : _add(),
                        decoration: const InputDecoration(
                          labelText: 'Friend name',
                          counterText: '',
                          prefixIcon: Icon(Icons.person_add_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      onPressed: _saving ? null : _add,
                      icon: const Icon(Icons.add_rounded),
                      tooltip: 'Add friend',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_friends.isNotEmpty)
                  const Text(
                    'GROUP FRIENDS',
                    style: TextStyle(
                      color: AppPalette.secondaryLabel,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                    ),
                  ),
                if (_friends.isNotEmpty) const SizedBox(height: 8),
                Expanded(
                  child: _friends.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.group_add_outlined,
                                size: 42,
                                color: AppPalette.secondaryLabel,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'No friends yet',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Add someone above to include them in expenses.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppPalette.secondaryLabel,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: _friends.length,
                          separatorBuilder: (_, _) => const Divider(),
                          itemBuilder: (context, index) {
                            final friend = _friends[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: AppPalette.surfaceElevated,
                                child: Text(friend.name[0].toUpperCase()),
                              ),
                              title: Text(friend.name),
                              trailing: IconButton(
                                onPressed: () => _remove(friend),
                                color: AppPalette.red,
                                tooltip: 'Remove ${friend.name}',
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpenseParticipantDraft {
  final String key;
  final GroupFriendRecord friend;
  final String? shareId;
  final bool paid;
  final TextEditingController amountController;
  final TextEditingController noteController;
  bool noteExpanded;

  _ExpenseParticipantDraft({
    required this.key,
    required this.friend,
    this.shareId,
    this.paid = false,
    String amount = '',
    String note = '',
  }) : amountController = TextEditingController(text: amount),
       noteController = TextEditingController(text: note),
       noteExpanded = note.trim().isNotEmpty;

  void dispose() {
    amountController.dispose();
    noteController.dispose();
  }
}

class _PendingProof {
  final String id;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final XFile? localFile;
  final String? storagePath;
  ReceiptExtraction? extraction;

  _PendingProof({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    this.localFile,
    this.storagePath,
    this.extraction,
  });

  bool get isNew => localFile != null;
}

String _formatProofSize(int sizeBytes) {
  if (sizeBytes < 1024) return '$sizeBytes B';
  final kilobytes = sizeBytes / 1024;
  if (kilobytes < 1024) return '${kilobytes.ceil()} KB';
  return '${(kilobytes / 1024).toStringAsFixed(1)} MB';
}

class _ProofViewerItem {
  final String filename;
  final int sizeBytes;
  final String? localPath;
  final String? remoteUrl;
  final bool scanReviewed;

  const _ProofViewerItem({
    required this.filename,
    required this.sizeBytes,
    required this.scanReviewed,
    this.localPath,
    this.remoteUrl,
  });
}

class _ProofThumbnailCard extends StatelessWidget {
  final int index;
  final int totalCount;
  final _PendingProof proof;
  final VoidCallback onView;
  final ValueChanged<String> onAction;

  const _ProofThumbnailCard({
    required this.index,
    required this.totalCount,
    required this.proof,
    required this.onView,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'View proof ${index + 1} of $totalCount, ${proof.filename}',
      child: SizedBox(
        width: 142,
        child: Material(
          color: AppPalette.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            side: const BorderSide(color: AppPalette.separator),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onView,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (proof.localFile == null)
                        const _ProofPlaceholder()
                      else
                        Image.file(
                          File(proof.localFile!.path),
                          fit: BoxFit.cover,
                          cacheWidth: 420,
                          errorBuilder: (_, _, _) =>
                              const _ProofPlaceholder(hasError: true),
                        ),
                      Positioned(
                        top: AppSpacing.xs,
                        left: AppSpacing.xs,
                        child: _ProofNumberBadge(number: index + 1),
                      ),
                      if (proof.extraction != null)
                        Positioned(
                          top: AppSpacing.xs,
                          right: AppSpacing.xs,
                          child: Semantics(
                            label: 'Receipt scan reviewed',
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppPalette.greenContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(5),
                                child: Icon(
                                  Icons.document_scanner_outlined,
                                  color: AppPalette.green,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 54,
                  child: Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                proof.filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatProofSize(proof.sizeBytes),
                                style: const TextStyle(
                                  color: AppPalette.secondaryLabel,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Actions for proof ${index + 1}',
                          icon: const Icon(Icons.more_vert_rounded, size: 20),
                          onSelected: onAction,
                          itemBuilder: (_) => [
                            if (proof.isNew)
                              const PopupMenuItem(
                                value: 'scan',
                                child: _ProofMenuLabel(
                                  icon: Icons.document_scanner_outlined,
                                  label: 'Scan receipt',
                                ),
                              ),
                            if (index > 0)
                              const PopupMenuItem(
                                value: 'up',
                                child: _ProofMenuLabel(
                                  icon: Icons.arrow_back_rounded,
                                  label: 'Move earlier',
                                ),
                              ),
                            if (index < totalCount - 1)
                              const PopupMenuItem(
                                value: 'down',
                                child: _ProofMenuLabel(
                                  icon: Icons.arrow_forward_rounded,
                                  label: 'Move later',
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'remove',
                              child: _ProofMenuLabel(
                                icon: Icons.delete_outline_rounded,
                                label: 'Remove',
                                color: AppPalette.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProofMenuLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _ProofMenuLabel({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

class _ProofNumberBadge extends StatelessWidget {
  final int number;

  const _ProofNumberBadge({required this.number});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppPalette.background.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '$number',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _ProofPlaceholder extends StatelessWidget {
  final bool hasError;

  const _ProofPlaceholder({this.hasError = false});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppPalette.surfaceMuted,
      child: Center(
        child: Icon(
          hasError ? Icons.broken_image_outlined : Icons.image_outlined,
          color: AppPalette.secondaryLabel,
          size: 32,
        ),
      ),
    );
  }
}

class _ProofViewer extends StatefulWidget {
  final String expenseTitle;
  final List<_ProofViewerItem> items;
  final int initialIndex;

  const _ProofViewer({
    required this.expenseTitle,
    required this.items,
    this.initialIndex = 0,
  });

  @override
  State<_ProofViewer> createState() => _ProofViewerState();
}

class _ProofViewerState extends State<_ProofViewer> {
  late final PageController _pageController;
  final _thumbnailController = ScrollController();
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex
        .clamp(0, widget.items.length - 1)
        .toInt();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _thumbnailController.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    _pageController.animateToPage(
      index,
      duration: AppMotion.standard,
      curve: AppMotion.curve,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_thumbnailController.hasClients) return;
      final target = (index * 68.0 - 96).clamp(
        0.0,
        _thumbnailController.position.maxScrollExtent,
      );
      _thumbnailController.animateTo(
        target,
        duration: AppMotion.standard,
        curve: AppMotion.curve,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_currentIndex];
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          tooltip: 'Close proof viewer',
          icon: const Icon(Icons.close_rounded),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Proof ${_currentIndex + 1} of ${widget.items.length}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              widget.expenseTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppPalette.secondaryLabel,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.items.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) => _ZoomableProofPage(
                  key: ValueKey('${widget.items[index].filename}-$index'),
                  item: widget.items[index],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              decoration: const BoxDecoration(
                color: AppPalette.surface,
                border: Border(top: BorderSide(color: AppPalette.separator)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.filename,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_formatProofSize(item.sizeBytes)} · '
                              'Pinch or double-tap to zoom',
                              style: const TextStyle(
                                color: AppPalette.secondaryLabel,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (item.scanReviewed) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const AppStatusPill(
                          label: 'Scanned',
                          foreground: AppPalette.green,
                          background: AppPalette.greenContainer,
                          icon: Icons.document_scanner_outlined,
                        ),
                      ],
                    ],
                  ),
                  if (widget.items.length > 1) ...[
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: 58,
                      child: ListView.separated(
                        controller: _thumbnailController,
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.items.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppSpacing.xs),
                        itemBuilder: (context, index) {
                          final selected = index == _currentIndex;
                          return Semantics(
                            button: true,
                            selected: selected,
                            label:
                                'View proof ${index + 1} of ${widget.items.length}',
                            child: GestureDetector(
                              onTap: () => _selectPage(index),
                              child: AnimatedContainer(
                                duration: AppMotion.fast,
                                width: 58,
                                padding: EdgeInsets.all(selected ? 2 : 0),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.small,
                                  ),
                                  border: selected
                                      ? Border.all(
                                          color: AppPalette.blue,
                                          width: 2,
                                        )
                                      : Border.all(color: AppPalette.separator),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _ProofViewerImage(
                                  item: widget.items[index],
                                  fit: BoxFit.cover,
                                  thumbnail: true,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomableProofPage extends StatefulWidget {
  final _ProofViewerItem item;

  const _ZoomableProofPage({super.key, required this.item});

  @override
  State<_ZoomableProofPage> createState() => _ZoomableProofPageState();
}

class _ZoomableProofPageState extends State<_ZoomableProofPage> {
  final _transformationController = TransformationController();
  Offset _doubleTapPosition = Offset.zero;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_transformationController.value.getMaxScaleOnAxis() > 1.01) {
      _transformationController.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    final matrix = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, -_doubleTapPosition.dx * (scale - 1))
      ..setEntry(1, 3, -_doubleTapPosition.dy * (scale - 1));
    _transformationController.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: widget.item.filename,
      child: GestureDetector(
        onDoubleTapDown: (details) =>
            _doubleTapPosition = details.localPosition,
        onDoubleTap: _handleDoubleTap,
        child: InteractiveViewer(
          transformationController: _transformationController,
          minScale: 1,
          maxScale: 6,
          child: SizedBox.expand(child: _ProofViewerImage(item: widget.item)),
        ),
      ),
    );
  }
}

class _ProofViewerImage extends StatelessWidget {
  final _ProofViewerItem item;
  final BoxFit fit;
  final bool thumbnail;

  const _ProofViewerImage({
    required this.item,
    this.fit = BoxFit.contain,
    this.thumbnail = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget errorBuilder(
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
    ) {
      if (thumbnail) return const _ProofPlaceholder(hasError: true);
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: 42,
                color: AppPalette.secondaryLabel,
              ),
              SizedBox(height: AppSpacing.sm),
              Text('Could not load this proof image.'),
            ],
          ),
        ),
      );
    }

    if (item.localPath != null) {
      return Image.file(
        File(item.localPath!),
        fit: fit,
        cacheWidth: thumbnail ? 180 : null,
        errorBuilder: errorBuilder,
      );
    }
    if (item.remoteUrl == null) return const _ProofPlaceholder(hasError: true);
    return Image.network(
      item.remoteUrl!,
      fit: fit,
      cacheWidth: thumbnail ? 180 : null,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        if (thumbnail) return const _ProofPlaceholder();
        final expected = progress.expectedTotalBytes;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                value: expected == null
                    ? null
                    : progress.cumulativeBytesLoaded / expected,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Loading proof…',
                style: TextStyle(color: AppPalette.secondaryLabel),
              ),
            ],
          ),
        );
      },
      errorBuilder: errorBuilder,
    );
  }
}

IconData _expenseCategoryIcon(String iconName) => switch (iconName) {
  'restaurant' => Icons.restaurant_rounded,
  'shopping_basket' => Icons.shopping_basket_outlined,
  'directions_car' => Icons.directions_car_outlined,
  'shopping_bag' => Icons.shopping_bag_outlined,
  'receipt' => Icons.receipt_long_outlined,
  'movie' => Icons.movie_outlined,
  'flight' => Icons.flight_rounded,
  'health_and_safety' => Icons.health_and_safety_outlined,
  _ => Icons.category_outlined,
};

class _CategoryPickerResult {
  final String? categoryId;
  final bool createNew;

  const _CategoryPickerResult.selected(this.categoryId) : createNew = false;

  const _CategoryPickerResult.create() : categoryId = null, createNew = true;
}

class _CategoryPickerField extends StatelessWidget {
  final ExpenseCategoryRecord? category;
  final String? errorText;
  final VoidCallback onTap;

  const _CategoryPickerField({
    super.key,
    required this.category,
    required this.errorText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = category;
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: selected == null
              ? 'Category. Choose a category.'
              : 'Category, ${selected.name}. Tap to change.',
          child: Material(
            color: AppPalette.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium),
              side: BorderSide(
                color: hasError ? AppPalette.red : Colors.transparent,
                width: hasError ? 1.2 : 0,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 70),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: selected == null
                              ? AppPalette.surfaceMuted
                              : AppPalette.blueContainer,
                          borderRadius: BorderRadius.circular(AppRadius.small),
                        ),
                        child: Icon(
                          _expenseCategoryIcon(
                            selected?.iconName ?? 'category',
                          ),
                          color: selected == null
                              ? AppPalette.secondaryLabel
                              : AppPalette.blue,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Category',
                              style: TextStyle(
                                color: hasError
                                    ? AppPalette.red
                                    : AppPalette.secondaryLabel,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              selected?.name ?? 'Choose category',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected == null
                                    ? AppPalette.secondaryLabel
                                    : AppPalette.label,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppPalette.secondaryLabel,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              errorText!,
              style: const TextStyle(color: AppPalette.red, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}

class _ExpenseCategoryPickerSheet extends StatefulWidget {
  final List<ExpenseCategoryRecord> categories;
  final Set<String> frequentCategoryIds;
  final String? selectedCategoryId;

  const _ExpenseCategoryPickerSheet({
    required this.categories,
    required this.frequentCategoryIds,
    required this.selectedCategoryId,
  });

  @override
  State<_ExpenseCategoryPickerSheet> createState() =>
      _ExpenseCategoryPickerSheetState();
}

class _ExpenseCategoryPickerSheetState
    extends State<_ExpenseCategoryPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _select(ExpenseCategoryRecord category) {
    Navigator.pop(context, _CategoryPickerResult.selected(category.id));
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    final visibleCategories = normalizedQuery.isEmpty
        ? widget.categories
        : widget.categories
              .where(
                (category) =>
                    category.name.toLowerCase().contains(normalizedQuery),
              )
              .toList();
    final frequentCategories = normalizedQuery.isEmpty
        ? widget.categories
              .where(
                (category) => widget.frequentCategoryIds.contains(category.id),
              )
              .take(3)
              .toList()
        : const <ExpenseCategoryRecord>[];

    return FractionallySizedBox(
      heightFactor: 0.82,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: AppSectionHeader(
                      title: 'Choose category',
                      subtitle: 'Used for organizing and finding expenses.',
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close category picker',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search categories',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          tooltip: 'Clear category search',
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
            Expanded(
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  if (frequentCategories.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.xs,
                        ),
                        child: Text(
                          'FREQUENTLY USED',
                          style: TextStyle(
                            color: AppPalette.secondaryLabel,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: Row(
                          children: [
                            for (final category in frequentCategories)
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: AppSpacing.xs,
                                ),
                                child: ChoiceChip(
                                  selected:
                                      category.id == widget.selectedCategoryId,
                                  onSelected: (_) => _select(category),
                                  avatar: Icon(
                                    _expenseCategoryIcon(category.iconName),
                                    size: 18,
                                  ),
                                  label: Text(category.name),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        frequentCategories.isEmpty
                            ? AppSpacing.md
                            : AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.xs,
                      ),
                      child: Text(
                        normalizedQuery.isEmpty
                            ? 'ALL CATEGORIES'
                            : '${visibleCategories.length} '
                                  '${visibleCategories.length == 1 ? 'RESULT' : 'RESULTS'}',
                        style: const TextStyle(
                          color: AppPalette.secondaryLabel,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                  ),
                  if (visibleCategories.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                color: AppPalette.secondaryLabel,
                                size: 36,
                              ),
                              SizedBox(height: AppSpacing.sm),
                              Text('No matching categories'),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList.separated(
                      itemCount: visibleCategories.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.xxs),
                      itemBuilder: (context, index) {
                        final category = visibleCategories[index];
                        final selected =
                            category.id == widget.selectedCategoryId;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          child: Material(
                            color: selected
                                ? AppPalette.blueContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              AppRadius.medium,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              onTap: () => _select(category),
                              minTileHeight: 56,
                              leading: Icon(
                                _expenseCategoryIcon(category.iconName),
                                color: selected
                                    ? AppPalette.blue
                                    : AppPalette.secondaryLabel,
                              ),
                              title: Text(
                                category.name,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                              trailing: selected
                                  ? const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppPalette.blue,
                                    )
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.sm),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppPalette.separator)),
              ),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  const _CategoryPickerResult.create(),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create new category'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseEditorDialog extends StatefulWidget {
  final String groupId;
  final JpayRepository repository;
  final List<GroupFriendRecord> friends;
  final ExpenseRecord? expense;
  final List<ExpenseShareRecord> existingShares;

  const _ExpenseEditorDialog({
    required this.groupId,
    required this.repository,
    required this.friends,
    this.expense,
    this.existingShares = const [],
  });

  bool get isEditing => expense != null;

  @override
  State<_ExpenseEditorDialog> createState() => _ExpenseEditorDialogState();
}

class _ExpenseEditorDialogState extends State<_ExpenseEditorDialog> {
  final _titleController = TextEditingController();
  final _merchantController = TextEditingController();
  final _notesController = TextEditingController();
  final _taxController = TextEditingController();
  final _serviceController = TextEditingController();
  final List<_ExpenseParticipantDraft> _rows = [];
  final List<_PendingProof> _proofs = [];
  final Set<String> _initialProofPaths = {};
  final Map<String, ExpenseCategoryRecord> _locallyCreatedCategories = {};
  final _picker = ImagePicker();
  final _scanner = const ReceiptScanner();
  String? _categoryId;
  DateTime _expenseDate = DateTime.now();
  double? _receiptTotal;
  ExpenseLocation? _location;
  List<String?> _usedCategoryIds = const [];
  bool _loadingMetadata = true;
  bool _optionalDetailsExpanded = false;
  bool _proofsExpanded = false;
  bool _chargesExpanded = false;
  bool _saving = false;
  bool _discardApproved = false;
  int _newRowSequence = 0;
  String _initialDraftSignature = '';
  String? _titleError;
  String? _categoryError;
  String? _participantsError;
  final Map<String, String> _amountErrors = {};
  final _scrollController = ScrollController();
  final _essentialsKey = GlobalKey();
  final _participantsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    if (expense != null) {
      _titleController.text = expense.title;
      _merchantController.text = expense.merchant;
      _notesController.text = expense.notes;
      _optionalDetailsExpanded =
          expense.merchant.trim().isNotEmpty || expense.notes.trim().isNotEmpty;
      _categoryId = expense.categoryId;
      _expenseDate = expense.expenseDate.toLocal();
      _receiptTotal = expense.receiptTotal;
      _location = expense.location;
      if (expense.taxPercent != 0) {
        _taxController.text = _compactNumber(expense.taxPercent);
      }
      if (expense.servicePercent != 0) {
        _serviceController.text = _compactNumber(expense.servicePercent);
      }
      _chargesExpanded = expense.taxPercent != 0 || expense.servicePercent != 0;
      for (final share in widget.existingShares) {
        final friend = _friendForShare(share);
        _rows.add(
          _ExpenseParticipantDraft(
            key: share.id,
            friend: friend,
            shareId: share.id,
            paid: share.paid,
            amount: share.baseAmount.toStringAsFixed(2),
            note: share.description,
          ),
        );
      }
    }
    _loadMetadata();
  }

  Future<List<ExpenseRecord>> _readExpenseUsage() async {
    try {
      return await widget.repository.watchExpenses(widget.groupId).first;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _loadMetadata() async {
    try {
      final categoriesFuture = widget.repository.watchExpenseCategories().first;
      final attachmentsFuture = widget.expense == null
          ? Future<List<ExpenseAttachmentRecord>>.value(const [])
          : widget.repository.watchExpenseAttachments(widget.expense!.id).first;
      final expensesFuture = _readExpenseUsage();
      final values = await Future.wait<dynamic>([
        categoriesFuture,
        attachmentsFuture,
        expensesFuture,
      ]);
      if (!mounted) return;
      final categories = values[0] as List<ExpenseCategoryRecord>;
      final attachments = values[1] as List<ExpenseAttachmentRecord>;
      final expenses = values[2] as List<ExpenseRecord>;
      setState(() {
        _usedCategoryIds = expenses
            .map((expense) => expense.categoryId)
            .toList();
        _categoryId ??= categories
            .where((category) => category.name == 'Other')
            .map((category) => category.id)
            .firstOrNull;
        _proofs.addAll(
          attachments.map(
            (attachment) => _PendingProof(
              id: attachment.id,
              filename: attachment.originalFilename,
              mimeType: attachment.mimeType,
              sizeBytes: attachment.sizeBytes,
              storagePath: attachment.storagePath,
              extraction: attachment.extraction,
            ),
          ),
        );
        _initialProofPaths.addAll(
          attachments.map((attachment) => attachment.storagePath),
        );
        _proofsExpanded = attachments.isNotEmpty;
        _loadingMetadata = false;
        _initialDraftSignature = _draftSignature();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadingMetadata = false;
          _initialDraftSignature = _draftSignature();
        });
        _message(
          networkAwareErrorMessage(error, action: 'load expense details'),
        );
      }
    }
  }

  GroupFriendRecord _friendForShare(ExpenseShareRecord share) {
    for (final friend in widget.friends) {
      if (friend.id == share.friendId) return friend;
    }
    for (final friend in widget.friends) {
      if (friend.name.toLowerCase() == share.friendName.toLowerCase()) {
        return friend;
      }
    }
    return GroupFriendRecord(
      id: share.friendId ?? 'legacy-${share.id}',
      groupId: widget.groupId,
      name: share.friendName,
    );
  }

  String _compactNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _titleController.dispose();
    _merchantController.dispose();
    _notesController.dispose();
    _taxController.dispose();
    _serviceController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  String _draftSignature() {
    final location = _location;
    return [
      _titleController.text.trim(),
      _merchantController.text.trim(),
      _notesController.text.trim(),
      _taxController.text.trim(),
      _serviceController.text.trim(),
      _categoryId ?? '',
      _expenseDate.toIso8601String(),
      _receiptTotal?.toString() ?? '',
      if (location != null)
        '${location.label}|${location.latitude}|${location.longitude}',
      ..._proofs.map(
        (proof) =>
            '${proof.id}|${proof.storagePath}|${proof.extraction?.rawText}',
      ),
      ..._rows.map(
        (row) =>
            '${row.key}|${row.friend.id}|${row.amountController.text.trim()}|'
            '${row.noteController.text.trim()}|${row.paid}',
      ),
    ].join('¦');
  }

  bool get _isDirty =>
      !_loadingMetadata && _draftSignature() != _initialDraftSignature;

  Set<String> get _selectedFriendIds =>
      _rows.map((row) => row.friend.id).toSet();

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  double get _subtotal =>
      _rows.fold(0, (total, row) => total + _number(row.amountController));

  double get _tax => _subtotal * _number(_taxController) / 100;

  double get _service => _subtotal * _number(_serviceController) / 100;

  String get _optionalDetailsSummary {
    final details = <String>[];
    final merchant = _merchantController.text.trim();
    if (merchant.isNotEmpty) details.add(merchant);
    if (_notesController.text.trim().isNotEmpty) details.add('Notes added');
    return details.isEmpty ? 'Optional' : details.join(' · ');
  }

  Future<void> _selectFriends() async {
    final selected = {..._selectedFriendIds};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final allSelected =
              widget.friends.isNotEmpty &&
              widget.friends.every((friend) => selected.contains(friend.id));
          final someSelected = selected.isNotEmpty && !allSelected;
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  tooltip: 'Cancel',
                  icon: const Icon(Icons.close_rounded),
                ),
                title: const Text('Select friends'),
              ),
              body: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Text(
                        widget.friends.isEmpty
                            ? 'No friends are available.'
                            : 'Choose everyone involved in this expense.',
                        style: const TextStyle(
                          color: AppPalette.secondaryLabel,
                        ),
                      ),
                    ),
                    if (widget.friends.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: CheckboxListTile(
                          value: someSelected ? null : allSelected,
                          tristate: true,
                          title: Text(allSelected ? 'Clear all' : 'Select all'),
                          subtitle: Text(
                            '${selected.length} of ${widget.friends.length} selected',
                          ),
                          secondary: const Icon(Icons.select_all_rounded),
                          controlAffinity: ListTileControlAffinity.trailing,
                          onChanged: (_) => setDialogState(() {
                            if (allSelected) {
                              selected.clear();
                            } else {
                              selected.addAll(
                                widget.friends.map((friend) => friend.id),
                              );
                            }
                          }),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                    Expanded(
                      child: widget.friends.isEmpty
                          ? const Center(
                              child: Text(
                                'Add a friend from the group screen first.',
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                              itemCount: widget.friends.length,
                              separatorBuilder: (_, _) => const Divider(),
                              itemBuilder: (context, index) {
                                final friend = widget.friends[index];
                                return CheckboxListTile(
                                  value: selected.contains(friend.id),
                                  title: Text(friend.name),
                                  secondary: CircleAvatar(
                                    backgroundColor: AppPalette.surfaceElevated,
                                    child: Text(friend.name[0].toUpperCase()),
                                  ),
                                  controlAffinity:
                                      ListTileControlAffinity.trailing,
                                  onChanged: (checked) => setDialogState(() {
                                    if (checked == true) {
                                      selected.add(friend.id);
                                    } else {
                                      selected.remove(friend.id);
                                    }
                                  }),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: widget.friends.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, selected),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    'Use ${selected.length} '
                    '${selected.length == 1 ? 'friend' : 'friends'}',
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    if (result == null || !mounted) return;

    final removed = _selectedFriendIds.difference(result);
    if (removed.isNotEmpty) {
      final affected = _rows.where((row) => removed.contains(row.friend.id));
      final hasContent = affected.any(
        (row) =>
            row.amountController.text.trim().isNotEmpty ||
            row.noteController.text.trim().isNotEmpty ||
            row.paid,
      );
      if (hasContent) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove selected friend?'),
            content: const Text(
              'Their amount, note, and payment state will be removed from '
              'this expense.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep friend'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
    }

    final removedRows = _rows
        .where((row) => !result.contains(row.friend.id))
        .toList();
    setState(() {
      _participantsError = null;
      _rows.removeWhere((row) => !result.contains(row.friend.id));
      final existing = _selectedFriendIds;
      for (final friend in widget.friends) {
        if (result.contains(friend.id) && !existing.contains(friend.id)) {
          _rows.add(
            _ExpenseParticipantDraft(
              key: 'new-${_newRowSequence++}',
              friend: friend,
            ),
          );
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in removedRows) {
        row.dispose();
      }
    });
  }

  Future<void> _splitEqually() async {
    if (_rows.isEmpty) {
      _message('Select friends before splitting.');
      return;
    }
    final total = await showDialog<double>(
      context: context,
      builder: (_) => const _SplitExpenseTotalDialog(),
    );
    if (total == null || !mounted) return;
    final shares = splitCurrencyTotal(total, _rows.length);
    setState(() {
      for (var index = 0; index < _rows.length; index++) {
        _rows[index].amountController.text = shares[index].toStringAsFixed(2);
      }
    });
  }

  Future<void> _removeRow(_ExpenseParticipantDraft row) async {
    final hasContent =
        row.amountController.text.trim().isNotEmpty ||
        row.noteController.text.trim().isNotEmpty ||
        row.paid;
    if (hasContent) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove participant?'),
          content: const Text(
            'Their amount, note, and payment state will be discarded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _rows.remove(row));
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  Future<void> _pickProofs(ImageSource source) async {
    if (_proofs.length >= 5) {
      _message('An expense can have at most five proof images.');
      return;
    }
    final remainingSlots = 5 - _proofs.length;
    final useSinglePicker = source == ImageSource.camera || remainingSlots == 1;
    final picked = useSinglePicker
        ? [if (await _picker.pickImage(source: source) case final file?) file]
        : await _picker.pickMultiImage(limit: remainingSlots);
    if (!mounted || picked.isEmpty) return;
    final accepted = <_PendingProof>[];
    for (final file in picked.take(remainingSlots)) {
      final length = await file.length();
      final extension = file.name.split('.').last.toLowerCase();
      final mimeType = switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => '',
      };
      if (mimeType.isEmpty) {
        _message('${file.name} is not a JPEG, PNG, or WebP image.');
        continue;
      }
      if (length > 10 * 1024 * 1024) {
        _message('${file.name} is larger than 10 MB.');
        continue;
      }
      accepted.add(
        _PendingProof(
          id: const Uuid().v4(),
          filename: file.name,
          mimeType: mimeType,
          sizeBytes: length,
          localFile: file,
        ),
      );
    }
    if (accepted.isNotEmpty) {
      setState(() {
        _proofs.addAll(accepted);
        _proofsExpanded = true;
      });
    }
  }

  Future<void> _openProofPreview(int initialIndex) async {
    FocusScope.of(context).unfocus();
    try {
      final items = await Future.wait(
        _proofs.map((proof) async {
          String? remoteUrl;
          if (proof.localFile == null && proof.storagePath != null) {
            remoteUrl = await widget.repository.createExpenseProofUrl(
              proof.storagePath!,
            );
          }
          return _ProofViewerItem(
            filename: proof.filename,
            sizeBytes: proof.sizeBytes,
            localPath: proof.localFile?.path,
            remoteUrl: remoteUrl,
            scanReviewed: proof.extraction != null,
          );
        }),
      );
      if (!mounted || items.isEmpty) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: _ProofViewer(
            expenseTitle: _titleController.text.trim().isEmpty
                ? 'Expense proof'
                : _titleController.text.trim(),
            items: items,
            initialIndex: initialIndex,
          ),
        ),
      );
    } catch (error) {
      _message(networkAwareErrorMessage(error, action: 'open this proof'));
    }
  }

  Future<void> _handleProofAction(
    String action,
    _PendingProof proof,
    int index,
  ) async {
    if (action == 'scan') {
      await _scanProof(proof);
      return;
    }
    if (!mounted) return;
    setState(() {
      if (action == 'up' && index > 0) {
        final item = _proofs.removeAt(index);
        _proofs.insert(index - 1, item);
      } else if (action == 'down' && index < _proofs.length - 1) {
        final item = _proofs.removeAt(index);
        _proofs.insert(index + 1, item);
      } else if (action == 'remove') {
        _proofs.removeAt(index);
      }
    });
  }

  Future<void> _scanReceiptShortcut() async {
    if (_proofs.length >= 5) {
      _message('An expense can have at most five proof images.');
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppSectionHeader(
                title: 'Scan a receipt',
                subtitle:
                    'Jpay will attach the image and let you review the detected merchant, date, and total.',
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.pop(context, ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take a photo'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose from gallery'),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    final previousIds = _proofs.map((proof) => proof.id).toSet();
    await _pickProofs(source);
    if (!mounted) return;
    final added = _proofs
        .where((proof) => !previousIds.contains(proof.id))
        .firstOrNull;
    if (added != null) await _scanProof(added);
  }

  Future<void> _scanProof(_PendingProof proof) async {
    if (proof.localFile == null) {
      _message('Replace this saved proof to scan it again on this device.');
      return;
    }
    setState(() => _saving = true);
    try {
      final extraction = await _scanner.scan(proof.localFile!.path);
      if (!mounted) return;
      final reviewed = await _reviewExtraction(extraction);
      if (reviewed == null || !mounted) return;
      setState(() {
        proof.extraction = reviewed;
        if (reviewed.merchant.isNotEmpty) {
          _merchantController.text = reviewed.merchant;
          _optionalDetailsExpanded = true;
        }
        if (reviewed.total != null) _receiptTotal = reviewed.total;
        if (reviewed.date != null) _expenseDate = reviewed.date!;
      });
    } catch (error) {
      _message('Could not scan this receipt: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<ReceiptExtraction?> _reviewExtraction(ReceiptExtraction extraction) {
    return showDialog<ReceiptExtraction>(
      context: context,
      builder: (_) => _ReceiptReviewDialog(extraction: extraction),
    );
  }

  Future<void> _chooseLocation() async {
    final result = await Navigator.push<ExpenseLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseLocationPickerScreen(initialLocation: _location),
      ),
    );
    if (result != null && mounted) setState(() => _location = result);
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: _expenseDate,
    );
    if (picked != null && mounted) setState(() => _expenseDate = picked);
  }

  Future<void> _chooseCategory(List<ExpenseCategoryRecord> categories) async {
    FocusScope.of(context).unfocus();
    final usedIds = _usedCategoryIds.whereType<String>().toSet();
    final result = await showModalBottomSheet<_CategoryPickerResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExpenseCategoryPickerSheet(
        categories: categories,
        frequentCategoryIds: usedIds,
        selectedCategoryId: _categoryId,
      ),
    );
    if (result == null || !mounted) return;
    if (result.createNew) {
      await _createCategory(categories);
      return;
    }
    setState(() {
      _categoryId = result.categoryId;
      _categoryError = null;
    });
  }

  Future<void> _createCategory(
    List<ExpenseCategoryRecord> availableCategories,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _CreateExpenseCategoryDialog(
        existingNames: availableCategories
            .map((category) => category.name)
            .toList(),
      ),
    );
    if (name == null || !mounted) return;
    try {
      final category = await widget.repository.createExpenseCategory(name);
      if (mounted) {
        setState(() {
          _locallyCreatedCategories[category.id] = category;
          _categoryId = category.id;
        });
      }
    } catch (error) {
      if (_isDuplicateCategoryError(error)) {
        try {
          final categories = await widget.repository
              .watchExpenseCategories()
              .first;
          final normalizedName = name.trim().toLowerCase();
          final existing = categories
              .where(
                (category) =>
                    category.name.trim().toLowerCase() == normalizedName,
              )
              .firstOrNull;
          if (existing != null && mounted) {
            setState(() {
              _locallyCreatedCategories[existing.id] = existing;
              _categoryId = existing.id;
            });
            _message(
              'The category "${existing.name}" already exists and has '
              'been selected.',
            );
            return;
          }
        } catch (_) {
          // Fall through to the specific duplicate message.
        }
        _message(
          'A category named "$name" already exists. Choose it from the list.',
        );
        return;
      }
      _message(networkAwareErrorMessage(error, action: 'create this category'));
    }
  }

  bool _isDuplicateCategoryError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('23505') ||
        message.contains('expense_categories_owner_name_unique') ||
        (message.contains('duplicate key') &&
            message.contains('expense_categories'));
  }

  Future<void> _splitReceiptTotal() async {
    final total = _receiptTotal;
    if (total == null) return;
    if (_rows.isEmpty) {
      _message('Select friends before splitting the receipt total.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Split receipt total?'),
        content: Text(
          'Split RM ${total.toStringAsFixed(2)} equally across '
          '${_rows.length} participants? Existing amounts will be replaced.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Split total'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final shares = splitCurrencyTotal(total, _rows.length);
    setState(() {
      _taxController.clear();
      _serviceController.clear();
      for (var index = 0; index < _rows.length; index++) {
        _rows[index].amountController.text = shares[index].toStringAsFixed(2);
      }
    });
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final targetContext = key.currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: AppMotion.standard,
      curve: AppMotion.curve,
      alignment: 0.08,
    );
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    setState(() {
      _titleError = null;
      _categoryError = null;
      _participantsError = null;
      _amountErrors.clear();
    });
    if (title.isEmpty) {
      setState(() => _titleError = 'Enter what the expense was for.');
      await _scrollTo(_essentialsKey);
      return;
    }
    if (_categoryId == null) {
      setState(() => _categoryError = 'Choose an expense category.');
      await _scrollTo(_essentialsKey);
      return;
    }
    if (_rows.isEmpty) {
      setState(() => _participantsError = 'Select at least one friend.');
      await _scrollTo(_participantsKey);
      return;
    }

    final drafts = <ExpenseShareDraft>[];
    for (final row in _rows) {
      final amountText = row.amountController.text.trim();
      final amount = double.tryParse(amountText);
      if (amountText.isEmpty) {
        setState(() {
          _amountErrors[row.key] = 'Enter an amount for ${row.friend.name}.';
        });
        await _scrollTo(_participantsKey);
        return;
      }
      if (amount == null || !amount.isFinite || amount <= 0) {
        setState(() {
          _amountErrors[row.key] =
              'Enter a positive amount for ${row.friend.name}.';
        });
        await _scrollTo(_participantsKey);
        return;
      }
      drafts.add(
        ExpenseShareDraft(
          shareId: row.shareId,
          friendId: row.friend.id.startsWith('legacy-') ? null : row.friend.id,
          friendName: row.friend.name,
          description: row.noteController.text.trim(),
          baseAmount: roundCurrency(amount),
        ),
      );
    }

    final tax = _number(_taxController);
    final service = _number(_serviceController);
    if (!tax.isFinite || tax < 0 || !service.isFinite || service < 0) {
      _message('Tax and service percentages cannot be negative.');
      return;
    }

    setState(() => _saving = true);
    final expenseId = widget.expense?.id ?? const Uuid().v4();
    final uploadedPaths = <String>[];
    try {
      final attachments = <ExpenseAttachmentDraft>[];
      for (var index = 0; index < _proofs.length; index++) {
        final proof = _proofs[index];
        var storagePath = proof.storagePath;
        if (proof.localFile != null) {
          final extension = switch (proof.mimeType) {
            'image/jpeg' => 'jpg',
            'image/png' => 'png',
            'image/webp' => 'webp',
            _ => throw StateError('Unsupported proof image type.'),
          };
          storagePath = await widget.repository.uploadExpenseProof(
            expenseId: expenseId,
            attachmentId: proof.id,
            extension: extension,
            mimeType: proof.mimeType,
            bytes: await proof.localFile!.readAsBytes(),
          );
          uploadedPaths.add(storagePath);
        }
        if (storagePath == null) {
          throw StateError('A proof image is missing its storage path.');
        }
        attachments.add(
          ExpenseAttachmentDraft(
            id: proof.id,
            storagePath: storagePath,
            originalFilename: proof.filename,
            mimeType: proof.mimeType,
            sizeBytes: proof.sizeBytes,
            sortOrder: index,
            extraction: proof.extraction,
          ),
        );
      }
      final draft = ExpenseDraft(
        id: expenseId,
        title: title,
        merchant: _merchantController.text.trim(),
        notes: _notesController.text.trim(),
        categoryId: _categoryId,
        receiptTotal: _receiptTotal,
        location: _location,
        attachments: attachments,
        taxPercent: tax,
        servicePercent: service,
        expenseDate: _expenseDate,
        shares: drafts,
      );
      if (widget.expense == null) {
        await widget.repository.createExpense(widget.groupId, draft);
      } else {
        await widget.repository.updateExpense(widget.expense!.id, draft);
      }
      final retainedPaths = attachments
          .map((attachment) => attachment.storagePath)
          .toSet();
      final removedPaths = _initialProofPaths
          .difference(retainedPaths)
          .toList();
      if (removedPaths.isNotEmpty) {
        try {
          await widget.repository.deleteExpenseProofs(removedPaths);
        } catch (_) {
          // The database is authoritative; stale private objects can be
          // cleaned during later authenticated maintenance.
        }
      }
      if (mounted) {
        _discardApproved = true;
        Navigator.pop(context);
      }
    } catch (error) {
      try {
        await widget.repository.deleteExpenseProofs(uploadedPaths);
      } catch (_) {
        // Preserve the original save error.
      }
      _message(
        networkAwareErrorMessage(
          error,
          action: widget.isEditing
              ? 'update this expense'
              : 'save this expense',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDiscard() async {
    if (_saving) return;
    if (!_isDirty) {
      setState(() => _discardApproved = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.edit_note_rounded, color: AppPalette.orange),
        title: const Text('Discard this expense?'),
        content: const Text(
          'Your unsaved details, amounts, and proof changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppPalette.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    setState(() => _discardApproved = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Widget _buildScanShortcut() {
    return AppSectionCard(
      color: AppPalette.blueContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionHeader(
            title: 'Have a receipt?',
            subtitle:
                'Scan it to prefill the merchant, date, and receipt total.',
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.tonalIcon(
            onPressed: _saving ? null : _scanReceiptShortcut,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan receipt'),
          ),
        ],
      ),
    );
  }

  Widget _buildEssentialsSection() {
    return AppSectionCard(
      key: _essentialsKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionHeader(
            title: 'Expense details',
            subtitle: 'Start with the essentials.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_titleError != null) setState(() => _titleError = null);
            },
            decoration: InputDecoration(
              labelText: 'What was it for?',
              hintText: 'Dinner, groceries, tickets…',
              errorText: _titleError,
              prefixIcon: const Icon(Icons.edit_note_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          StreamBuilder<List<ExpenseCategoryRecord>>(
            stream: widget.repository.watchExpenseCategories(),
            builder: (context, snapshot) {
              final categoriesById = <String, ExpenseCategoryRecord>{};
              for (final category
                  in snapshot.data ?? const <ExpenseCategoryRecord>[]) {
                categoriesById[category.id] = category;
              }
              categoriesById.addAll(_locallyCreatedCategories);
              final categories = orderExpenseCategoriesByUsage(
                categoriesById.values,
                _usedCategoryIds,
              );
              return _CategoryPickerField(
                key: const ValueKey('expense-category-picker'),
                category: categoriesById[_categoryId],
                errorText: _categoryError,
                onTap: () => _chooseCategory(categories),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _chooseDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(
              '${_expenseDate.day}/${_expenseDate.month}/${_expenseDate.year}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsSection() {
    return AppSectionCard(
      key: _participantsKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(
            title: 'Who owes you?',
            subtitle:
                'Choose people, then enter custom amounts or split explicitly.',
            trailing: FilledButton.tonalIcon(
              onPressed: _selectFriends,
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: Text(_rows.isEmpty ? 'Select' : 'Change'),
            ),
          ),
          if (_participantsError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                _participantsError!,
                style: const TextStyle(color: AppPalette.red, fontSize: 13),
              ),
            ),
          ],
          if (_rows.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppPalette.surfaceElevated,
                borderRadius: BorderRadius.circular(AppRadius.medium),
              ),
              child: const Column(
                children: [
                  Icon(Icons.group_outlined, color: AppPalette.secondaryLabel),
                  SizedBox(height: AppSpacing.xs),
                  Text('No participants selected'),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selectedFriendIds.length} selected',
                    style: const TextStyle(
                      color: AppPalette.secondaryLabel,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _splitEqually,
                  icon: const Icon(Icons.balance_outlined, size: 18),
                  label: const Text('Split equally'),
                ),
              ],
            ),
            ..._rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ParticipantCard(
                  row: row,
                  errorText: _amountErrors[row.key],
                  onChanged: () => setState(() {
                    _amountErrors.remove(row.key);
                  }),
                  onRemove: () => _removeRow(row),
                  onToggleNote: () =>
                      setState(() => row.noteExpanded = !row.noteExpanded),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProofSection() {
    return AppSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _proofsExpanded = !_proofsExpanded),
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text(
              'Receipt & proof',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              _proofs.isEmpty
                  ? 'Optional · Add up to five images'
                  : '${_proofs.length}/5 attached · Tap to view',
            ),
            trailing: Icon(
              _proofsExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
            ),
          ),
          if (_proofsExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _proofs.length >= 5
                              ? null
                              : () => _pickProofs(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Camera'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _proofs.length >= 5
                              ? null
                              : () => _pickProofs(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Gallery'),
                        ),
                      ),
                    ],
                  ),
                  if (_proofs.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: 164,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _proofs.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final proof = _proofs[index];
                          return _ProofThumbnailCard(
                            index: index,
                            totalCount: _proofs.length,
                            proof: proof,
                            onView: () => _openProofPreview(index),
                            onAction: (action) => unawaited(
                              _handleProofAction(action, proof, index),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  if (_receiptTotal != null)
                    Card(
                      color: AppPalette.blueContainer,
                      child: ListTile(
                        leading: const Icon(
                          Icons.receipt_long_outlined,
                          color: AppPalette.blue,
                        ),
                        title: Text(
                          'Receipt total · RM ${_receiptTotal!.toStringAsFixed(2)}',
                        ),
                        subtitle: const Text(
                          'Split it only when you are ready to replace custom amounts.',
                        ),
                        trailing: TextButton(
                          onPressed: _splitReceiptTotal,
                          child: const Text('Split'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOptionalDetailsSection() {
    return AppSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(
              () => _optionalDetailsExpanded = !_optionalDetailsExpanded,
            ),
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text(
              'Merchant & notes',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(_optionalDetailsSummary),
            trailing: Icon(
              _optionalDetailsExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
            ),
          ),
          if (_optionalDetailsExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _merchantController,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 120,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Merchant (optional)',
                      counterText: '',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _notesController,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    onChanged: (_) => setState(() {}),
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Expense notes (optional)',
                      counterText: '',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _chooseLocation,
                    icon: const Icon(Icons.place_outlined),
                    label: Text(
                      _location?.label ?? 'Add location',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_location != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_location!.label),
                      subtitle: Text(
                        _location!.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        onPressed: () => setState(() => _location = null),
                        tooltip: 'Remove location',
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChargesSection() {
    final total = _subtotal + _tax + _service;
    return AppSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _chargesExpanded = !_chargesExpanded),
            leading: const Icon(Icons.percent_outlined),
            title: const Text(
              'Tax & service',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              _tax == 0 && _service == 0
                  ? 'Optional'
                  : 'RM ${(_tax + _service).toStringAsFixed(2)} added',
            ),
            trailing: Icon(
              _chargesExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
            ),
          ),
          if (_chargesExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _taxController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Tax',
                            suffixText: '%',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _serviceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Service',
                            suffixText: '%',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppPalette.blueContainer,
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                    ),
                    child: Column(
                      children: [
                        _SummaryLine(label: 'Subtotal', value: _subtotal),
                        if (_tax != 0) _SummaryLine(label: 'Tax', value: _tax),
                        if (_service != 0)
                          _SummaryLine(label: 'Service', value: _service),
                        const Divider(height: AppSpacing.md),
                        _SummaryLine(
                          label: 'Total owed',
                          value: total,
                          bold: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSaveBar(double total) {
    return Container(
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        border: Border(top: BorderSide(color: AppPalette.separator)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Builder(
          builder: (context) {
            final totalLabel = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TOTAL OWED',
                  style: TextStyle(
                    color: AppPalette.secondaryLabel,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                Text(
                  'RM ${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            );
            final saveButton = FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size(160, 52)),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text(widget.isEditing ? 'Save changes' : 'Add expense'),
            );
            if (MediaQuery.sizeOf(context).width < 340) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  totalLabel,
                  const SizedBox(height: AppSpacing.xs),
                  saveButton,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: totalLabel),
                const SizedBox(width: AppSpacing.md),
                Flexible(child: saveButton),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _subtotal + _tax + _service;
    return PopScope(
      canPop: _discardApproved || (!_isDirty && !_saving),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _saving ? null : _confirmDiscard,
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(widget.isEditing ? 'Edit expense' : 'Add expense'),
        ),
        body: _loadingMetadata
            ? const AppLoadingList(itemCount: 4)
            : SafeArea(
                bottom: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.xl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildScanShortcut(),
                          const SizedBox(height: AppSpacing.md),
                          _buildEssentialsSection(),
                          const SizedBox(height: AppSpacing.md),
                          _buildParticipantsSection(),
                          const SizedBox(height: AppSpacing.md),
                          _buildProofSection(),
                          const SizedBox(height: AppSpacing.sm),
                          _buildOptionalDetailsSection(),
                          const SizedBox(height: AppSpacing.sm),
                          _buildChargesSection(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        bottomNavigationBar: _loadingMetadata ? null : _buildSaveBar(total),
      ),
    );
  }

  // Retained temporarily as a rollback reference during the UI refresh.
  // ignore: unused_element
  Widget _buildLegacyEditor(BuildContext context) {
    final total = _subtotal + _tax + _service;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit expense' : 'Add expense'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(widget.isEditing ? 'Save' : 'Add'),
          ),
        ],
      ),
      body: _loadingMetadata
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'What was it for?',
                        hintText: 'Dinner, groceries, tickets…',
                        prefixIcon: Icon(Icons.edit_note_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    StreamBuilder<List<ExpenseCategoryRecord>>(
                      stream: widget.repository.watchExpenseCategories(),
                      builder: (context, snapshot) {
                        final categoriesById =
                            <String, ExpenseCategoryRecord>{};
                        for (final category
                            in snapshot.data ??
                                const <ExpenseCategoryRecord>[]) {
                          categoriesById[category.id] = category;
                        }
                        categoriesById.addAll(_locallyCreatedCategories);
                        final categories = orderExpenseCategoriesByUsage(
                          categoriesById.values,
                          _usedCategoryIds,
                        );
                        final value = categoriesById.containsKey(_categoryId)
                            ? _categoryId
                            : null;
                        return Row(
                          children: [
                            Expanded(
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Category',
                                  prefixIcon: Icon(Icons.category_outlined),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: value,
                                    isExpanded: true,
                                    hint: const Text('Choose category'),
                                    onTap: () =>
                                        FocusScope.of(context).unfocus(),
                                    items: categories
                                        .map(
                                          (category) => DropdownMenuItem(
                                            value: category.id,
                                            child: Text(category.name),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) =>
                                        setState(() => _categoryId = value),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.outlined(
                              onPressed: () => _createCategory(categories),
                              tooltip: 'Create category',
                              icon: const Icon(Icons.add_rounded),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _chooseDate,
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: Text(
                              '${_expenseDate.day}/${_expenseDate.month}/'
                              '${_expenseDate.year}',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _chooseLocation,
                            icon: const Icon(Icons.place_outlined),
                            label: Text(
                              _location?.label ?? 'Add location',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_location != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_location!.label),
                        subtitle: Text(
                          _location!.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          onPressed: () => setState(() => _location = null),
                          tooltip: 'Remove location',
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Material(
                      color: AppPalette.surfaceElevated,
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        onTap: () => setState(
                          () => _optionalDetailsExpanded =
                              !_optionalDetailsExpanded,
                        ),
                        leading: const Icon(Icons.info_outline_rounded),
                        title: const Text(
                          'Merchant & notes',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          _optionalDetailsSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          _optionalDetailsExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                        ),
                      ),
                    ),
                    if (_optionalDetailsExpanded) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _merchantController,
                        textCapitalization: TextCapitalization.words,
                        maxLength: 120,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Merchant (optional)',
                          counterText: '',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _notesController,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        onChanged: (_) => setState(() {}),
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Expense notes (optional)',
                          counterText: '',
                          alignLabelWithHint: true,
                          prefixIcon: Icon(Icons.notes_outlined),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Proof & receipt scan',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text('${_proofs.length}/5'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _proofs.length >= 5
                                ? null
                                : () => _pickProofs(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Camera'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _proofs.length >= 5
                                ? null
                                : () => _pickProofs(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Gallery'),
                          ),
                        ),
                      ],
                    ),
                    if (_proofs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ..._proofs.asMap().entries.map((entry) {
                        final index = entry.key;
                        final proof = entry.value;
                        return Card(
                          child: ListTile(
                            leading: proof.localFile == null
                                ? const Icon(Icons.image_outlined)
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.file(
                                      File(proof.localFile!.path),
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                            title: Text(
                              proof.filename,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              proof.extraction == null
                                  ? '${(proof.sizeBytes / 1024).ceil()} KB'
                                  : 'Receipt scan reviewed',
                            ),
                            trailing: Wrap(
                              spacing: 0,
                              children: [
                                IconButton(
                                  onPressed: proof.isNew
                                      ? () => _scanProof(proof)
                                      : null,
                                  tooltip: 'Scan receipt',
                                  icon: const Icon(
                                    Icons.document_scanner_outlined,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) => setState(() {
                                    if (value == 'up' && index > 0) {
                                      final item = _proofs.removeAt(index);
                                      _proofs.insert(index - 1, item);
                                    } else if (value == 'down' &&
                                        index < _proofs.length - 1) {
                                      final item = _proofs.removeAt(index);
                                      _proofs.insert(index + 1, item);
                                    } else if (value == 'remove') {
                                      _proofs.removeAt(index);
                                    }
                                  }),
                                  itemBuilder: (_) => [
                                    if (index > 0)
                                      const PopupMenuItem(
                                        value: 'up',
                                        child: Text('Move up'),
                                      ),
                                    if (index < _proofs.length - 1)
                                      const PopupMenuItem(
                                        value: 'down',
                                        child: Text('Move down'),
                                      ),
                                    const PopupMenuItem(
                                      value: 'remove',
                                      child: Text('Remove'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                    if (_receiptTotal != null)
                      Card(
                        color: AppPalette.blueContainer,
                        child: ListTile(
                          leading: const Icon(
                            Icons.receipt_long_outlined,
                            color: AppPalette.blue,
                          ),
                          title: Text(
                            'Receipt total · RM ${_receiptTotal!.toStringAsFixed(2)}',
                          ),
                          subtitle: const Text(
                            'This will not change what anyone owes until you split it.',
                          ),
                          trailing: TextButton(
                            onPressed: _splitReceiptTotal,
                            child: const Text('Split'),
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Who owes you?',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Amounts stay custom unless you split explicitly.',
                                style: TextStyle(
                                  color: AppPalette.secondaryLabel,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _selectFriends,
                          icon: const Icon(Icons.group_add_outlined, size: 18),
                          label: Text(_rows.isEmpty ? 'Select' : 'Change'),
                        ),
                      ],
                    ),
                    if (_rows.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_selectedFriendIds.length} selected',
                              style: const TextStyle(
                                color: AppPalette.secondaryLabel,
                              ),
                            ),
                          ),
                          Flexible(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _splitEqually,
                                icon: const Icon(
                                  Icons.balance_outlined,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Split equally',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (_rows.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        decoration: BoxDecoration(
                          color: AppPalette.surfaceElevated,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.group_outlined),
                            SizedBox(height: 8),
                            Text('Select friends for this expense'),
                          ],
                        ),
                      )
                    else
                      ..._rows.map(
                        (row) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ParticipantCard(
                            row: row,
                            onChanged: () => setState(() {}),
                            onRemove: () => _removeRow(row),
                            onToggleNote: () => setState(
                              () => row.noteExpanded = !row.noteExpanded,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () =>
                          setState(() => _chargesExpanded = !_chargesExpanded),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppPalette.surfaceElevated,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.percent_outlined),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Additional charges',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Icon(
                              _chargesExpanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_chargesExpanded) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _taxController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Tax',
                                suffixText: '%',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _serviceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Service',
                                suffixText: '%',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppPalette.blueContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _SummaryLine(label: 'Subtotal', value: _subtotal),
                          if (_tax != 0)
                            _SummaryLine(label: 'Tax', value: _tax),
                          if (_service != 0)
                            _SummaryLine(label: 'Service', value: _service),
                          const Divider(height: 18),
                          _SummaryLine(
                            label: 'Total owed',
                            value: total,
                            bold: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Text(widget.isEditing ? 'Save changes' : 'Add expense'),
          ),
        ),
      ),
    );
  }
}

class _ReceiptReviewDialog extends StatefulWidget {
  final ReceiptExtraction extraction;

  const _ReceiptReviewDialog({required this.extraction});

  @override
  State<_ReceiptReviewDialog> createState() => _ReceiptReviewDialogState();
}

class _ReceiptReviewDialogState extends State<_ReceiptReviewDialog> {
  late final TextEditingController _merchantController;
  late final TextEditingController _totalController;
  late final TextEditingController _dateController;
  late final TextEditingController _rawTextController;

  @override
  void initState() {
    super.initState();
    final extraction = widget.extraction;
    _merchantController = TextEditingController(text: extraction.merchant);
    _totalController = TextEditingController(
      text: extraction.total?.toStringAsFixed(2) ?? '',
    );
    _dateController = TextEditingController(
      text: extraction.date?.toIso8601String().split('T').first ?? '',
    );
    _rawTextController = TextEditingController(text: extraction.rawText);
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _totalController.dispose();
    _dateController.dispose();
    _rawTextController.dispose();
    super.dispose();
  }

  void _submit() {
    final parsedTotal = _totalController.text.trim().isEmpty
        ? null
        : double.tryParse(_totalController.text.trim());
    final parsedDate = _dateController.text.trim().isEmpty
        ? null
        : DateTime.tryParse(_dateController.text.trim());
    FocusScope.of(context).unfocus();
    Navigator.pop(
      context,
      ReceiptExtraction(
        rawText: _rawTextController.text.trim(),
        merchant: _merchantController.text.trim(),
        total: parsedTotal,
        date: parsedDate,
        items: widget.extraction.items,
        script: widget.extraction.script,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final extraction = widget.extraction;
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Cancel',
            icon: const Icon(Icons.close_rounded),
          ),
          title: const Text('Review receipt scan'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _merchantController,
                  decoration: const InputDecoration(labelText: 'Merchant'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _totalController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Receipt total (RM)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _dateController,
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    hintText: 'YYYY-MM-DD',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _rawTextController,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Recognized receipt text',
                    alignLabelWithHint: true,
                  ),
                ),
                if (extraction.items.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    '${extraction.items.length} purchased items detected',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  ...extraction.items
                      .take(12)
                      .map(
                        (item) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.description),
                          trailing: item.amount == null
                              ? null
                              : Text('RM ${item.amount!.toStringAsFixed(2)}'),
                        ),
                      ),
                ],
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('Apply reviewed data'),
          ),
        ),
      ),
    );
  }
}

class _SplitExpenseTotalDialog extends StatefulWidget {
  const _SplitExpenseTotalDialog();

  @override
  State<_SplitExpenseTotalDialog> createState() =>
      _SplitExpenseTotalDialogState();
}

class _SplitExpenseTotalDialogState extends State<_SplitExpenseTotalDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      setState(() => _errorText = 'Enter an amount greater than zero.');
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.pop(context, parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      scrollable: true,
      title: const Text('Split equally'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the subtotal before tax and service charges.',
            style: TextStyle(color: AppPalette.secondaryLabel),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
            decoration: InputDecoration(
              labelText: 'Total to split (RM)',
              hintText: '0.00',
              errorText: _errorText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Apply split')),
      ],
    );
  }
}

class _CreateExpenseCategoryDialog extends StatefulWidget {
  final List<String> existingNames;

  const _CreateExpenseCategoryDialog({required this.existingNames});

  @override
  State<_CreateExpenseCategoryDialog> createState() =>
      _CreateExpenseCategoryDialogState();
}

class _CreateExpenseCategoryDialogState
    extends State<_CreateExpenseCategoryDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _errorText = 'Enter a category name.');
      return;
    }
    final normalizedValue = value.toLowerCase();
    final existingName = widget.existingNames
        .where((name) => name.trim().toLowerCase() == normalizedValue)
        .firstOrNull;
    if (existingName != null) {
      setState(
        () => _errorText =
            'The category "$existingName" already exists. Choose it from '
            'the list.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New category'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
        decoration: InputDecoration(
          labelText: 'Category name',
          errorText: _errorText,
          helperText: 'Names are not case-sensitive.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

class _ParticipantCard extends StatelessWidget {
  final _ExpenseParticipantDraft row;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback onToggleNote;
  final String? errorText;

  const _ParticipantCard({
    required this.row,
    required this.onChanged,
    required this.onRemove,
    required this.onToggleNote,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: AppPalette.blueContainer,
                child: Text(row.friend.name[0].toUpperCase()),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  row.friend.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (row.paid)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Text(
                    'Paid',
                    style: TextStyle(
                      color: AppPalette.green,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Remove ${row.friend.name}',
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: row.amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: 'Amount owed (RM)',
              hintText: '0.00',
              errorText: errorText,
            ),
          ),
          if (row.noteExpanded) ...[
            const SizedBox(height: 10),
            TextField(
              controller: row.noteController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                prefixIcon: const Icon(Icons.notes_outlined),
                suffixIcon: IconButton(
                  onPressed: onToggleNote,
                  icon: const Icon(Icons.expand_less_rounded),
                ),
              ),
            ),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onToggleNote,
                icon: const Icon(Icons.add_comment_outlined, size: 17),
                label: Text(
                  row.noteController.text.trim().isEmpty
                      ? 'Add note'
                      : 'Edit note',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text('RM ${value.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  final String message;

  const _LoadError({required this.message});

  @override
  Widget build(BuildContext context) {
    return AppErrorState(message: message);
  }
}

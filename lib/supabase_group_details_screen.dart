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
import 'widgets/expense_maps.dart';

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
    final controller = TextEditingController(text: currentName);
    String? errorText;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rename group'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: 'Group name',
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(() => errorText = 'Enter a group name.');
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
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
    final categories = await widget.repository.watchExpenseCategories().first;
    if (!mounted) return;
    var category = _categoryFilter;
    var proof = _proofFilter;
    final merchant = TextEditingController(text: _merchantFilter);
    final location = TextEditingController(text: _locationFilter);
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
                TextField(
                  controller: merchant,
                  decoration: const InputDecoration(labelText: 'Merchant'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: location,
                  decoration: const InputDecoration(labelText: 'Location'),
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
                          merchant.clear();
                          location.clear();
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
        _merchantFilter = merchant.text.trim();
        _locationFilter = location.text.trim();
        _dateFilter = dates;
      });
      await _refreshSearch();
    }
    merchant.dispose();
    location.dispose();
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
      final urls = await Future.wait(
        attachments.map(
          (attachment) =>
              widget.repository.createExpenseProofUrl(attachment.storagePath),
        ),
      );
      if (!mounted) return;
      if (urls.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No proof images are attached.')),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(title: Text('${expense.title} · Proof')),
            body: PageView.builder(
              itemCount: urls.length,
              itemBuilder: (context, index) => InteractiveViewer(
                child: Center(
                  child: Image.network(
                    urls[index],
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : const CircularProgressIndicator(),
                    errorBuilder: (_, _, _) =>
                        const Text('Could not load this proof image.'),
                  ),
                ),
              ),
            ),
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
                return const Center(child: CircularProgressIndicator());
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
                    return const Center(child: CircularProgressIndicator());
                  }
                  final expenses = expenseSnapshot.data!;
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
                        return const Center(child: CircularProgressIndicator());
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
            title: const Text(
              'Outstanding balances',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              balanceList.isEmpty
                  ? 'Everyone is settled'
                  : 'RM ${outstandingTotal.toStringAsFixed(2)} • '
                        '${balanceList.length} ${balanceList.length == 1 ? 'friend owes' : 'friends owe'}',
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
            FilterChip(
              selected: _hasDiscoveryFilter,
              avatar: const Icon(Icons.tune_rounded, size: 18),
              label: Text(_hasDiscoveryFilter ? 'Filters active' : 'Filters'),
              onSelected: (_) => _showFilters(),
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
        else if (_showMap)
          ExpenseHistoryMap(
            expenses: visibleExpenses,
            onSelected: (expense) {
              final expenseShares = sharesByExpense[expense.id] ?? const [];
              showModalBottomSheet<void>(
                context: context,
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
            if (allPaid) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppPalette.greenContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'All Paid',
                  style: TextStyle(
                    color: AppPalette.green,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
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
        trailing: SizedBox(
          width: 88,
          child: Text(
            'RM ${expense.totalWithCharges.toStringAsFixed(2)}',
            maxLines: 1,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        children: [
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
    return Padding(
      padding: const EdgeInsets.only(top: 54),
      child: Column(
        children: [
          Icon(
            hasFriends ? Icons.receipt_long_outlined : Icons.group_add_outlined,
            size: 52,
            color: AppPalette.blue,
          ),
          const SizedBox(height: 14),
          Text(
            hasFriends ? 'No expenses yet' : 'Add friends first',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            hasFriends
                ? 'Tap Add expense to record the first one.'
                : 'Use Manage friends before recording an expense.',
            style: const TextStyle(color: AppPalette.secondaryLabel),
          ),
        ],
      ),
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
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Row(
        children: [
          const Expanded(child: Text('Manage friends')),
          Container(
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
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.58,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 16),
            if (_friends.isNotEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'GROUP FRIENDS',
                  style: TextStyle(
                    color: AppPalette.secondaryLabel,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            if (_friends.isNotEmpty) const SizedBox(height: 6),
            Flexible(
              child: _friends.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.group_add_outlined,
                            size: 36,
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
                      shrinkWrap: true,
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
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
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
  bool _loadingMetadata = true;
  bool _chargesExpanded = false;
  bool _saving = false;
  int _newRowSequence = 0;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    if (expense != null) {
      _titleController.text = expense.title;
      _merchantController.text = expense.merchant;
      _notesController.text = expense.notes;
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

  Future<void> _loadMetadata() async {
    try {
      final categoriesFuture = widget.repository.watchExpenseCategories().first;
      final attachmentsFuture = widget.expense == null
          ? Future<List<ExpenseAttachmentRecord>>.value(const [])
          : widget.repository.watchExpenseAttachments(widget.expense!.id).first;
      final values = await Future.wait<dynamic>([
        categoriesFuture,
        attachmentsFuture,
      ]);
      if (!mounted) return;
      final categories = values[0] as List<ExpenseCategoryRecord>;
      final attachments = values[1] as List<ExpenseAttachmentRecord>;
      setState(() {
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
        _loadingMetadata = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loadingMetadata = false);
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

  Set<String> get _selectedFriendIds =>
      _rows.map((row) => row.friend.id).toSet();

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  double get _subtotal =>
      _rows.fold(0, (total, row) => total + _number(row.amountController));

  double get _tax => _subtotal * _number(_taxController) / 100;

  double get _service => _subtotal * _number(_serviceController) / 100;

  Future<void> _selectFriends() async {
    final selected = {..._selectedFriendIds};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select friends'),
          content: SizedBox(
            width: 430,
            child: ListView(
              shrinkWrap: true,
              children: widget.friends
                  .map(
                    (friend) => CheckboxListTile(
                      value: selected.contains(friend.id),
                      title: Text(friend.name),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (checked) => setDialogState(() {
                        if (checked == true) {
                          selected.add(friend.id);
                        } else {
                          selected.remove(friend.id);
                        }
                      }),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: Text(
                'Use ${selected.length} '
                '${selected.length == 1 ? 'friend' : 'friends'}',
              ),
            ),
          ],
        ),
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

    setState(() {
      final removedRows = _rows
          .where((row) => !result.contains(row.friend.id))
          .toList();
      _rows.removeWhere((row) => !result.contains(row.friend.id));
      for (final row in removedRows) {
        row.dispose();
      }
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
  }

  Future<void> _splitEqually() async {
    if (_rows.isEmpty) {
      _message('Select friends before splitting.');
      return;
    }
    final controller = TextEditingController();
    String? errorText;
    final total = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Split equally'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Subtotal before tax & service',
              prefixText: 'RM ',
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(controller.text.trim());
                if (parsed == null || !parsed.isFinite || parsed <= 0) {
                  setDialogState(
                    () => errorText = 'Enter an amount greater than zero.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, parsed);
              },
              child: const Text('Apply split'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
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
    row.dispose();
  }

  Future<void> _pickProofs(ImageSource source) async {
    if (_proofs.length >= 5) {
      _message('An expense can have at most five proof images.');
      return;
    }
    final picked = source == ImageSource.camera
        ? [if (await _picker.pickImage(source: source) case final file?) file]
        : await _picker.pickMultiImage(limit: 5 - _proofs.length);
    if (!mounted || picked.isEmpty) return;
    final accepted = <_PendingProof>[];
    for (final file in picked.take(5 - _proofs.length)) {
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
    if (accepted.isNotEmpty) setState(() => _proofs.addAll(accepted));
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

  Future<ReceiptExtraction?> _reviewExtraction(
    ReceiptExtraction extraction,
  ) async {
    final merchant = TextEditingController(text: extraction.merchant);
    final total = TextEditingController(
      text: extraction.total?.toStringAsFixed(2) ?? '',
    );
    final date = TextEditingController(
      text: extraction.date?.toIso8601String().split('T').first ?? '',
    );
    final rawText = TextEditingController(text: extraction.rawText);
    final result = await showDialog<ReceiptExtraction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Review receipt scan'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: merchant,
                  decoration: const InputDecoration(labelText: 'Merchant'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: total,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Receipt total',
                    prefixText: 'RM ',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: date,
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    hintText: 'YYYY-MM-DD',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: rawText,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Recognized receipt text',
                    alignLabelWithHint: true,
                  ),
                ),
                if (extraction.items.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${extraction.items.length} purchased items detected',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsedTotal = total.text.trim().isEmpty
                  ? null
                  : double.tryParse(total.text.trim());
              final parsedDate = date.text.trim().isEmpty
                  ? null
                  : DateTime.tryParse(date.text.trim());
              Navigator.pop(
                dialogContext,
                ReceiptExtraction(
                  rawText: rawText.text.trim(),
                  merchant: merchant.text.trim(),
                  total: parsedTotal,
                  date: parsedDate,
                  items: extraction.items,
                  script: extraction.script,
                ),
              );
            },
            child: const Text('Apply reviewed data'),
          ),
        ],
      ),
    );
    merchant.dispose();
    total.dispose();
    date.dispose();
    rawText.dispose();
    return result;
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

  Future<void> _createCategory() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateExpenseCategoryDialog(),
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
      _message(networkAwareErrorMessage(error, action: 'create this category'));
    }
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

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _message('Enter what the expense was for.');
      return;
    }
    if (_rows.isEmpty) {
      _message('Select at least one friend.');
      return;
    }
    if (_categoryId == null) {
      _message('Choose an expense category.');
      return;
    }

    final drafts = <ExpenseShareDraft>[];
    for (final row in _rows) {
      final amountText = row.amountController.text.trim();
      final amount = double.tryParse(amountText);
      if (amountText.isEmpty) {
        _message('Enter an amount for ${row.friend.name}.');
        return;
      }
      if (amount == null || !amount.isFinite || amount <= 0) {
        _message('Enter a positive amount for ${row.friend.name}.');
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
      if (mounted) Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: _merchantController,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Merchant (optional)',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                    ),
                    const SizedBox(height: 2),
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
                        final categories = categoriesById.values.toList()
                          ..sort(
                            (a, b) => a.name.toLowerCase().compareTo(
                              b.name.toLowerCase(),
                            ),
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
                              onPressed: _createCategory,
                              tooltip: 'Create category',
                              icon: const Icon(Icons.add_rounded),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      minLines: 2,
                      maxLines: 5,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Expense notes (optional)',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
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
                          Text(
                            '${_selectedFriendIds.length} selected',
                            style: const TextStyle(
                              color: AppPalette.secondaryLabel,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _splitEqually,
                            icon: const Icon(Icons.balance_outlined, size: 18),
                            label: const Text('Split equally'),
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

class _CreateExpenseCategoryDialog extends StatefulWidget {
  const _CreateExpenseCategoryDialog();

  @override
  State<_CreateExpenseCategoryDialog> createState() =>
      _CreateExpenseCategoryDialogState();
}

class _CreateExpenseCategoryDialogState
    extends State<_CreateExpenseCategoryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
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
        decoration: const InputDecoration(labelText: 'Category name'),
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

  const _ParticipantCard({
    required this.row,
    required this.onChanged,
    required this.onRemove,
    required this.onToggleNote,
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
            decoration: const InputDecoration(
              labelText: 'Amount owed',
              prefixText: 'RM ',
              hintText: '0.00',
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

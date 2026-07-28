import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'backend/backend_models.dart';
import 'backend/supabase_jpay_repository.dart';
import 'debt_calculations.dart';
import 'network_status.dart';

class SupabaseGroupDetailsScreen extends StatefulWidget {
  final String groupId;
  final String initialName;
  final SupabaseJpayRepository repository;

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
    await showDialog<void>(
      context: context,
      builder: (_) => _ExpenseEditorDialog(
        groupId: widget.groupId,
        repository: widget.repository,
        friends: friends,
      ),
    );
  }

  Future<void> _editExpense(
    ExpenseRecord expense,
    List<ExpenseShareRecord> shares,
    List<GroupFriendRecord> friends,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ExpenseEditorDialog(
        groupId: widget.groupId,
        repository: widget.repository,
        friends: friends,
        expense: expense,
        existingShares: shares,
      ),
    );
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
        if (expenses.isEmpty)
          _EmptyExpenseState(hasFriends: friends.isNotEmpty)
        else
          ...expenses.map((expense) {
            final expenseShares = sharesByExpense[expense.id] ?? const [];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ExpenseHistoryCard(
                expense: expense,
                shares: expenseShares,
                onEdit: () => _editExpense(expense, expenseShares, friends),
                onDelete: () => _deleteExpense(expense),
                onMarkPaid: _markSharePaid,
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

  const _ExpenseHistoryCard({
    required this.expense,
    required this.shares,
    required this.onEdit,
    required this.onDelete,
    required this.onMarkPaid,
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
          '$date • ${shares.length} ${shares.length == 1 ? 'person' : 'people'}',
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
  final SupabaseJpayRepository repository;
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

class _ExpenseEditorDialog extends StatefulWidget {
  final String groupId;
  final SupabaseJpayRepository repository;
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
  final _taxController = TextEditingController();
  final _serviceController = TextEditingController();
  final List<_ExpenseParticipantDraft> _rows = [];
  bool _chargesExpanded = false;
  bool _saving = false;
  int _newRowSequence = 0;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    if (expense != null) {
      _titleController.text = expense.title;
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
    try {
      final draft = ExpenseDraft(
        title: title,
        taxPercent: tax,
        servicePercent: service,
        expenseDate: widget.isEditing ? null : DateTime.now(),
        shares: drafts,
      );
      if (widget.expense == null) {
        await widget.repository.createExpense(widget.groupId, draft);
      } else {
        await widget.repository.updateExpense(widget.expense!.id, draft);
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
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
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppPalette.blueContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              widget.isEditing
                  ? Icons.edit_note_rounded
                  : Icons.receipt_long_outlined,
              color: AppPalette.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.isEditing ? 'Edit expense' : 'Add expense'),
                const SizedBox(height: 2),
                Text(
                  widget.isEditing
                      ? 'Update participants and amounts'
                      : 'Record a shared cost',
                  style: const TextStyle(
                    color: AppPalette.secondaryLabel,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.64,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What was it for?',
                  hintText: 'Dinner, groceries, tickets…',
                  prefixIcon: Icon(Icons.edit_note_outlined),
                ),
              ),
              const SizedBox(height: 20),
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
                      style: const TextStyle(color: AppPalette.secondaryLabel),
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
                      onToggleNote: () =>
                          setState(() => row.noteExpanded = !row.noteExpanded),
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
                    const SizedBox(width: 10),
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
                    if (_tax != 0) _SummaryLine(label: 'Tax', value: _tax),
                    if (_service != 0)
                      _SummaryLine(label: 'Service', value: _service),
                    const Divider(height: 18),
                    _SummaryLine(label: 'Total owed', value: total, bold: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : Text(widget.isEditing ? 'Save changes' : 'Add expense'),
        ),
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

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'debt_calculations.dart';

class GroupDetailsScreen extends StatelessWidget {
  final String groupId;
  final String groupName;

  const GroupDetailsScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  Widget build(BuildContext context) {
    // 1. OUTER STREAM: Listens to the Group Document (to get Members)
    // We wrap the SCAFFOLD in this stream so the FloatingActionButton
    // can access the 'members' list too.
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .snapshots(),
      builder: (context, groupSnapshot) {
        // Loading State
        if (groupSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                groupName,
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // Error or Deleted State
        if (!groupSnapshot.hasData || !groupSnapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                groupName,
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
            body: Center(
              child: Text(
                "Group not found or deleted",
                style: GoogleFonts.inter(),
              ),
            ),
          );
        }

        // 2. DATA EXTRACTION
        final groupData = groupSnapshot.data!.data() as Map<String, dynamic>;
        final List<dynamic> friends = groupData['friends'] ?? [];
        final colorScheme = Theme.of(context).colorScheme;

        return Scaffold(
          backgroundColor: AppPalette.background,
          appBar: AppBar(
            title: Text(
              groupName,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            elevation: 0,
            actions: [
              IconButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => ManageFriendsDialog(
                      groupId: groupId,
                      currentFriends: friends,
                    ),
                  );
                },
                icon: const Icon(Icons.group_outlined),
                tooltip: "Manage friends",
              ),
              const SizedBox(width: 6),
            ],
          ),

          // 3. BODY: Balances Summary + Expenses List
          body: Column(
            children: [
              // --- Balances Summary ---
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF202A33), AppPalette.surface],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppPalette.blue.withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 20,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Outstanding balances",
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            letterSpacing: -0.3,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => ManageFriendsDialog(
                                groupId: groupId,
                                currentFriends: friends,
                              ),
                            );
                          },
                          icon: const Icon(Icons.group_outlined, size: 17),
                          label: Text("${friends.length}"),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.12,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('groups')
                          .doc(groupId)
                          .collection('expenses')
                          .snapshots(),
                      builder: (context, expenseSnapshot) {
                        if (!expenseSnapshot.hasData) {
                          return const SizedBox.shrink();
                        }

                        // Calculate balances per friend (only unpaid debts)
                        final Map<String, double> balances = {};
                        for (var expenseDoc in expenseSnapshot.data!.docs) {
                          final expense =
                              expenseDoc.data() as Map<String, dynamic>;

                          // Support both old format (owedBy) and new format (debts array)
                          if (expense.containsKey('debts')) {
                            // New format: debts array
                            final debts = expense['debts'] as List? ?? [];
                            for (var debt in debts) {
                              final debtData = debt as Map<String, dynamic>;
                              final paid = debtData['paid'] as bool? ?? false;
                              if (paid) continue; // Skip paid debts

                              double amount =
                                  (debtData['amount'] as num?)?.toDouble() ??
                                  0.0;

                              // Calculate final amount with tax/service
                              final hasBaseAmount =
                                  debtData['baseAmount'] != null;
                              if (hasBaseAmount) {
                                // New format: calculate from baseAmount + per-person tax/service
                                final baseAmount =
                                    (debtData['baseAmount'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                final taxForDebt =
                                    (debtData['taxAmount'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                final serviceForDebt =
                                    (debtData['serviceAmount'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                amount =
                                    baseAmount + taxForDebt + serviceForDebt;
                              } else {
                                // Backward compatibility: for older expenses that don't
                                // have per-person tax/service, distribute expense-level
                                // tax/service proportionally by base amount.
                                final expenseBaseTotal =
                                    (expense['totalAmount'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                final expenseTaxAmount =
                                    (expense['taxAmount'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                final expenseServiceAmount =
                                    (expense['serviceAmount'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                if (expenseBaseTotal > 0 &&
                                    (expenseTaxAmount != 0 ||
                                        expenseServiceAmount != 0)) {
                                  final ratio = amount / expenseBaseTotal;
                                  amount =
                                      amount +
                                      expenseTaxAmount * ratio +
                                      expenseServiceAmount * ratio;
                                }
                              }

                              final friendName =
                                  debtData['friendName'] as String? ?? '';

                              if (friendName.isNotEmpty) {
                                balances[friendName] =
                                    (balances[friendName] ?? 0.0) + amount;
                              }
                            }
                          } else {
                            // Old format: single owedBy (for backward compatibility)
                            final paid = expense['paid'] as bool? ?? false;
                            if (paid) continue; // Skip paid expenses

                            final amount =
                                (expense['amount'] as num?)?.toDouble() ?? 0.0;
                            final owedBy = expense['owedBy'] as String? ?? '';

                            if (owedBy.isNotEmpty) {
                              balances[owedBy] =
                                  (balances[owedBy] ?? 0.0) + amount;
                            }
                          }
                        }

                        final outstandingTotal = balances.values.fold<double>(
                          0,
                          (total, amount) => total + amount,
                        );

                        if (balances.isEmpty) {
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "Everyone is settled up",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "TOTAL TO COLLECT",
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "RM ${outstandingTotal.toStringAsFixed(2)}",
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ...balances.entries.map((entry) {
                              final friendName = entry.key;
                              final amount = entry.value;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 17,
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.18,
                                      ),
                                      child: Text(
                                        friendName.isEmpty
                                            ? "?"
                                            : friendName[0].toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        friendName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      "RM ${amount.toStringAsFixed(2)}",
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.check_circle_outline,
                                        size: 21,
                                      ),
                                      color: Colors.white,
                                      tooltip: "Mark all as paid",
                                      onPressed: () =>
                                          _markAllDebtsAsPaidForFriend(
                                            context,
                                            groupId,
                                            friendName,
                                            amount,
                                          ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              // --- Expenses List (Inner Stream) ---
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: Row(
                  children: [
                    Text(
                      "Expense history",
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      "Newest first",
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('groups')
                      .doc(groupId)
                      .collection('expenses')
                      .orderBy('date', descending: true)
                      .snapshots(),
                  builder: (context, expenseSnapshot) {
                    if (expenseSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!expenseSnapshot.hasData ||
                        expenseSnapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.receipt_long_outlined,
                                  size: 32,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "No expenses yet",
                                style: GoogleFonts.inter(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Add your first shared cost to start tracking who owes you.",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final expenses = expenseSnapshot.data!.docs;

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
                      itemCount: expenses.length,
                      itemBuilder: (context, index) {
                        final expense = expenses[index];
                        final data = expense.data() as Map<String, dynamic>;
                        final title = data['title'] as String? ?? '';
                        final date = data['date'] as Timestamp?;

                        // Support both old and new format
                        final bool hasDebts = data.containsKey('debts');
                        final List<Map<String, dynamic>> debts;
                        double totalAmount = 0.0;
                        final double taxAmount =
                            (data['taxAmount'] as num?)?.toDouble() ?? 0.0;
                        final double serviceAmount =
                            (data['serviceAmount'] as num?)?.toDouble() ?? 0.0;
                        double totalWithCharges =
                            (data['totalWithCharges'] as num?)?.toDouble() ??
                            0.0;
                        bool allPaid = true;

                        if (hasDebts) {
                          // New format: debts array
                          final debtsList = data['debts'] as List? ?? [];
                          debts = debtsList
                              .map((d) => d as Map<String, dynamic>)
                              .toList();
                          for (var debt in debts) {
                            final amount =
                                (debt['amount'] as num?)?.toDouble() ?? 0.0;
                            totalAmount += amount;
                            if (!(debt['paid'] as bool? ?? false)) {
                              allPaid = false;
                            }
                          }
                        } else {
                          // Old format: single owedBy (for backward compatibility)
                          final amount =
                              (data['amount'] as num?)?.toDouble() ?? 0.0;
                          final owedBy = data['owedBy'] as String? ?? '';
                          final paid = data['paid'] as bool? ?? false;
                          totalAmount = amount;
                          allPaid = paid;
                          debts = [
                            {
                              'friendName': owedBy,
                              'amount': amount,
                              'description': '',
                              'paid': paid,
                            },
                          ];
                        }

                        if (totalWithCharges <= 0) {
                          totalWithCharges =
                              totalAmount + taxAmount + serviceAmount;
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          color: allPaid
                              ? colorScheme.surfaceContainerLow
                              : colorScheme.surface,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.fromLTRB(
                              14,
                              6,
                              10,
                              6,
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              10,
                              0,
                              10,
                              10,
                            ),
                            shape: const Border(),
                            collapsedShape: const Border(),
                            leading: CircleAvatar(
                              backgroundColor: allPaid
                                  ? colorScheme.tertiaryContainer
                                  : colorScheme.primaryContainer,
                              child: Icon(
                                allPaid
                                    ? Icons.check_rounded
                                    : Icons.receipt_long_outlined,
                                color: allPaid
                                    ? colorScheme.onTertiaryContainer
                                    : colorScheme.onPrimaryContainer,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      decoration: allPaid
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ),
                                if (allPaid)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      "All Paid",
                                      style: GoogleFonts.inter(
                                        color: Colors.green.shade700,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${debts.length} ${debts.length == 1 ? 'person' : 'people'} • ${date == null ? 'Date unavailable' : _formatDate(date)}",
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (taxAmount > 0 || serviceAmount > 0)
                                  Text(
                                    "Includes ${_formatCharges(taxAmount, serviceAmount)}",
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 19,
                                  ),
                                  color: colorScheme.onSurfaceVariant,
                                  tooltip: "Edit Expense",
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => EditExpenseDialog(
                                        groupId: groupId,
                                        expenseId: expense.id,
                                        friends: friends,
                                        initialTitle: title,
                                        initialDebts: debts,
                                        initialTaxPercent:
                                            (data['taxPercent'] as num?)
                                                ?.toDouble() ??
                                            0.0,
                                        initialServicePercent:
                                            (data['servicePercent'] as num?)
                                                ?.toDouble() ??
                                            0.0,
                                      ),
                                    );
                                  },
                                ),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      "RM ${(totalWithCharges > 0 ? totalWithCharges : totalAmount).toStringAsFixed(2)}",
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: allPaid
                                            ? colorScheme.onSurfaceVariant
                                            : colorScheme.primary,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            children: debts.map((debt) {
                              final friendName =
                                  debt['friendName'] as String? ?? '';
                              double amount =
                                  (debt['amount'] as num?)?.toDouble() ?? 0.0;

                              // Calculate final amount with tax/service if needed
                              final hasBaseAmount = debt['baseAmount'] != null;
                              if (hasBaseAmount) {
                                // New format: calculate from baseAmount + per-person tax/service
                                final baseAmount =
                                    (debt['baseAmount'] as num?)?.toDouble() ??
                                    0.0;
                                final taxForDebt =
                                    (debt['taxAmount'] as num?)?.toDouble() ??
                                    0.0;
                                final serviceForDebt =
                                    (debt['serviceAmount'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                amount =
                                    baseAmount + taxForDebt + serviceForDebt;
                              } else {
                                // Backward compatibility: distribute expense-level tax/service proportionally
                                final expenseBaseTotal = totalAmount;
                                final expenseTaxAmount = taxAmount;
                                final expenseServiceAmount = serviceAmount;
                                if (expenseBaseTotal > 0 &&
                                    (expenseTaxAmount != 0 ||
                                        expenseServiceAmount != 0)) {
                                  final ratio = amount / expenseBaseTotal;
                                  amount =
                                      amount +
                                      expenseTaxAmount * ratio +
                                      expenseServiceAmount * ratio;
                                }
                              }

                              final description =
                                  debt['description'] as String? ?? '';
                              final paid = debt['paid'] as bool? ?? false;

                              return ListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                tileColor: colorScheme.surfaceContainerLow,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 2,
                                ),
                                leading: Icon(
                                  paid
                                      ? Icons.check_circle
                                      : Icons.person_outline,
                                  color: paid
                                      ? colorScheme.tertiary
                                      : colorScheme.onSurfaceVariant,
                                  size: 20,
                                ),
                                title: Text(
                                  friendName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    decoration: paid
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                subtitle: description.isNotEmpty
                                    ? Text(description)
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "RM ${amount.toStringAsFixed(2)}",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: paid
                                            ? colorScheme.onSurfaceVariant
                                            : colorScheme.primary,
                                      ),
                                    ),
                                    if (!paid)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                          size: 18,
                                        ),
                                        color: colorScheme.tertiary,
                                        tooltip: "Mark as Paid",
                                        onPressed: () => _markDebtAsPaid(
                                          context,
                                          expense.id,
                                          groupId,
                                          debts.indexOf(debt),
                                          amount,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),

          // 4. FLOATING ACTION BUTTON
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) =>
                    AddExpenseDialog(groupId: groupId, friends: friends),
              );
            },
            label: const Text("Add Expense"),
            icon: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return "Today";
    } else if (difference.inDays == 1) {
      return "Yesterday";
    } else if (difference.inDays < 7) {
      return "${difference.inDays} days ago";
    } else {
      return "${date.day}/${date.month}/${date.year}";
    }
  }

  String _formatCharges(double taxAmount, double serviceAmount) {
    final charges = <String>[];
    if (taxAmount > 0) {
      charges.add("RM ${taxAmount.toStringAsFixed(2)} tax");
    }
    if (serviceAmount > 0) {
      charges.add("RM ${serviceAmount.toStringAsFixed(2)} service");
    }
    return charges.join(" + ");
  }

  Future<void> _markDebtAsPaid(
    BuildContext context,
    String expenseId,
    String groupId,
    int debtIndex,
    double amount,
  ) async {
    try {
      final expenseRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('expenses')
          .doc(expenseId);

      var wasUpdated = false;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final expenseDoc = await transaction.get(expenseRef);
        if (!expenseDoc.exists) return;
        final data = expenseDoc.data() as Map<String, dynamic>;

        if (data.containsKey('debts')) {
          // New format: update specific debt in array
          // Note: Cannot use FieldValue.serverTimestamp() inside arrays, so we use DateTime.now()
          final debts = List<Map<String, dynamic>>.from(data['debts'] as List);
          if (debtIndex >= 0 && debtIndex < debts.length) {
            final debt = debts[debtIndex];
            if (debt['paid'] == true) return;
            final effectiveAmount = effectiveDebtAmount(debt, expense: data);

            debts[debtIndex]['paid'] = true;
            final now = DateTime.now();
            debts[debtIndex]['paidAt'] =
                '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

            transaction.update(expenseRef, {'debts': debts});
            final groupRef = FirebaseFirestore.instance
                .collection('groups')
                .doc(groupId);
            transaction.update(groupRef, {
              'totalOwed': FieldValue.increment(-effectiveAmount),
            });
            wasUpdated = true;
            return;
          }
        } else {
          if (data['paid'] == true) return;
          // Old format: mark entire expense as paid
          transaction.update(expenseRef, {
            'paid': true,
            'paidAt': FieldValue.serverTimestamp(),
          });
          final groupRef = FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId);
          transaction.update(groupRef, {
            'totalOwed': FieldValue.increment(-amount),
          });
          wasUpdated = true;
        }
      });

      if (wasUpdated && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Payment marked as received!")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _markAllDebtsAsPaidForFriend(
    BuildContext context,
    String groupId,
    String friendName,
    double totalAmount,
  ) async {
    // Show confirmation dialog
    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Mark All as Paid"),
        content: Text(
          "Mark all unpaid debts for $friendName (total: RM ${totalAmount.toStringAsFixed(2)}) as paid?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text("Mark as Paid"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final expensesSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('expenses')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      double totalMarkedAsPaid = 0.0;

      for (var expenseDoc in expensesSnapshot.docs) {
        final data = expenseDoc.data();
        final expenseRef = expenseDoc.reference;
        bool needsUpdate = false;

        if (data.containsKey('debts')) {
          // New format: debts array
          final debts = List<Map<String, dynamic>>.from(data['debts'] as List);

          for (var debt in debts) {
            final debtFriendName = debt['friendName'] as String? ?? '';
            final paid = debt['paid'] as bool? ?? false;

            if (debtFriendName == friendName && !paid) {
              debt['paid'] = true;
              // Note: Cannot use FieldValue.serverTimestamp() inside arrays, so we use DateTime.now()
              final now = DateTime.now();
              debt['paidAt'] =
                  '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
              totalMarkedAsPaid += (debt['amount'] as num?)?.toDouble() ?? 0.0;
              needsUpdate = true;
            }
          }

          if (needsUpdate) {
            batch.update(expenseRef, {'debts': debts});
          }
        } else {
          // Old format: single owedBy
          final owedBy = data['owedBy'] as String? ?? '';
          final paid = data['paid'] as bool? ?? false;

          if (owedBy == friendName && !paid) {
            final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
            batch.update(expenseRef, {
              'paid': true,
              'paidAt':
                  FieldValue.serverTimestamp(), // This is OK at document level
            });
            totalMarkedAsPaid += amount;
          }
        }
      }

      // Update total owed
      if (totalMarkedAsPaid > 0) {
        final groupRef = FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId);
        batch.update(groupRef, {
          'totalOwed': FieldValue.increment(-totalMarkedAsPaid),
        });
      }

      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "All debts for $friendName (${totalMarkedAsPaid.toStringAsFixed(2)}) marked as paid!",
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }
}

// ==========================================
// DIALOG 1: MANAGE FRIENDS
// ==========================================

class ManageFriendsDialog extends StatefulWidget {
  final String groupId;
  final List<dynamic> currentFriends;

  const ManageFriendsDialog({
    super.key,
    required this.groupId,
    required this.currentFriends,
  });

  @override
  State<ManageFriendsDialog> createState() => _ManageFriendsDialogState();
}

class _ManageFriendsDialogState extends State<ManageFriendsDialog> {
  final _nameController = TextEditingController();
  late final List<String> _friends;
  final Set<String> _removingFriends = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _friends = widget.currentFriends
        .map((friend) => friend.toString().trim())
        .where((friend) => friend.isNotEmpty)
        .toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addFriend() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    if (_friends.any((friend) => friend.toLowerCase() == name.toLowerCase())) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Friend already exists!")));
      return;
    }

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .update({
            'friends': FieldValue.arrayUnion([name]),
          });
      if (!mounted) return;
      setState(() => _friends.add(name));
      _nameController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _removeFriend(String friendName) async {
    if (_removingFriends.contains(friendName)) return;
    setState(() => _removingFriends.add(friendName));

    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .update({
            'friends': FieldValue.arrayRemove([friendName]),
          });
      if (!mounted) return;
      setState(() => _friends.remove(friendName));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _removingFriends.remove(friendName));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom;
    final listHeight = (availableHeight * 0.36).clamp(120.0, 280.0);
    final compactLayout = availableHeight < 560;

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compactLayout ? 8 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.group_outlined,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Manage friends",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2),
                Text(
                  "Add or remove people",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: _friends.isEmpty,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_isSaving) _addFriend();
              },
              decoration: InputDecoration(
                labelText: "Friend's name",
                hintText: "e.g. Alex",
                prefixIcon: const Icon(Icons.person_add_alt_1),
                border: const OutlineInputBorder(),
                suffixIcon: _isSaving
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        onPressed: _addFriend,
                        icon: const Icon(Icons.arrow_forward),
                        tooltip: "Add friend",
                      ),
              ),
            ),
            SizedBox(height: compactLayout ? 10 : 18),
            Row(
              children: [
                const Text(
                  "Friends",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${_friends.length}",
                    style: TextStyle(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: listHeight,
              width: double.maxFinite,
              child: _friends.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.group_add_outlined,
                            size: 36,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 10),
                          const Text("No friends added yet"),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _friends.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final friend = _friends[index];
                        return ListTile(
                          tileColor: colorScheme.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: colorScheme.primaryContainer,
                            foregroundColor: colorScheme.onPrimaryContainer,
                            child: Text(friend[0].toUpperCase()),
                          ),
                          title: Text(
                            friend,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: _removingFriends.contains(friend)
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: colorScheme.error,
                                  ),
                                  tooltip: "Remove $friend",
                                  onPressed: () => _removeFriend(friend),
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Done"),
        ),
      ],
    );
  }
}

// ==========================================
// DIALOG 2: ADD EXPENSE (Ledger Style - You paid, friend owes)
// ==========================================

class AddExpenseDialog extends StatefulWidget {
  final String groupId;
  final List<dynamic> friends;

  const AddExpenseDialog({
    super.key,
    required this.groupId,
    required this.friends,
  });

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class DebtEntry {
  String friendName;
  String amount;
  String description;
  bool paid;

  DebtEntry({
    required this.friendName,
    this.amount = '',
    this.description = '',
    this.paid = false,
  });
}

List<String> _expenseFriendNames(
  Iterable<dynamic> friends, {
  Iterable<String> include = const [],
}) {
  final names = <String>[];
  final seen = <String>{};
  for (final value in [...friends, ...include]) {
    final name = value.toString().trim();
    if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
    names.add(name);
  }
  return names;
}

Future<Set<String>?> _showParticipantPicker(
  BuildContext context, {
  required List<String> friends,
  required Set<String> selected,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final draftSelection = Set<String>.from(selected);
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.68,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Select friends",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text("Choose everyone involved in this expense"),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: draftSelection.isEmpty
                              ? null
                              : () => setSheetState(draftSelection.clear),
                          child: const Text("Clear"),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: friends.length,
                      itemBuilder: (context, index) {
                        final friend = friends[index];
                        final isSelected = draftSelection.contains(friend);
                        return CheckboxListTile(
                          value: isSelected,
                          title: Text(friend),
                          secondary: CircleAvatar(
                            child: Text(friend[0].toUpperCase()),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          onChanged: (value) {
                            setSheetState(() {
                              if (value == true) {
                                draftSelection.add(friend);
                              } else {
                                draftSelection.remove(friend);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        Set<String>.from(draftSelection),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: Text(
                        draftSelection.isEmpty
                            ? "Use no friends"
                            : "Use ${draftSelection.length} friend${draftSelection.length == 1 ? '' : 's'}",
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<double?> _showEqualSplitPrompt(BuildContext context) async {
  final controller = TextEditingController();
  String? errorText;
  final result = await showDialog<double>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text("Split equally"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: "Subtotal before tax & service",
            prefixText: "RM ",
            hintText: "0.00",
            helperText: "Additional charges are added afterward",
            errorText: errorText,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            final amount = double.tryParse(controller.text.trim());
            if (amount == null || !amount.isFinite || amount <= 0) {
              setDialogState(
                () => errorText = "Enter an amount greater than zero",
              );
              return;
            }
            Navigator.pop(context, amount);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(controller.text.trim());
              if (amount == null || !amount.isFinite || amount <= 0) {
                setDialogState(
                  () => errorText = "Enter an amount greater than zero",
                );
                return;
              }
              Navigator.pop(context, amount);
            },
            child: const Text("Apply split"),
          ),
        ],
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  return result;
}

class _AdditionalChargesSection extends StatelessWidget {
  final bool expanded;
  final TextEditingController taxController;
  final TextEditingController serviceController;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;

  const _AdditionalChargesSection({
    required this.expanded,
    required this.taxController,
    required this.serviceController,
    required this.onToggle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                const Icon(Icons.percent_outlined, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Additional charges",
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Tax and service (optional)",
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 12),
          Text(
            "Applied proportionally to every person's share.",
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: taxController,
                  decoration: const InputDecoration(
                    labelText: "Tax",
                    hintText: "0",
                    suffixText: "%",
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: serviceController,
                  decoration: const InputDecoration(
                    labelText: "Service",
                    hintText: "0",
                    suffixText: "%",
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ParticipantAmountCard extends StatelessWidget {
  final DebtEntry debt;
  final TextEditingController amountController;
  final TextEditingController descriptionController;
  final bool noteExpanded;
  final VoidCallback onRemove;
  final VoidCallback onToggleNote;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onDescriptionChanged;

  const _ParticipantAmountCard({
    required this.debt,
    required this.amountController,
    required this.descriptionController,
    required this.noteExpanded,
    required this.onRemove,
    required this.onToggleNote,
    required this.onAmountChanged,
    required this.onDescriptionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: colorScheme.secondaryContainer,
                  foregroundColor: colorScheme.onSecondaryContainer,
                  child: Text(debt.friendName[0].toUpperCase()),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    debt.friendName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  tooltip: "Remove ${debt.friendName}",
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: "Amount owed",
                prefixText: "RM ",
                hintText: "0.00",
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: onAmountChanged,
            ),
            if (noteExpanded) ...[
              const SizedBox(height: 10),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: "Note (optional)",
                  hintText: "Their share of dinner",
                  prefixIcon: const Icon(Icons.notes_outlined),
                  suffixIcon: IconButton(
                    onPressed: onToggleNote,
                    icon: const Icon(Icons.expand_less),
                    tooltip: "Hide note",
                  ),
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.sentences,
                onChanged: onDescriptionChanged,
              ),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onToggleNote,
                  icon: const Icon(Icons.add_comment_outlined, size: 17),
                  label: Text(
                    descriptionController.text.trim().isEmpty
                        ? "Add note"
                        : "Edit note",
                  ),
                ),
              ),
            if (debt.paid)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "Paid",
                    style: TextStyle(
                      color: colorScheme.onTertiaryContainer,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _titleController = TextEditingController();
  final List<DebtEntry> _debts = [];
  final Map<int, TextEditingController> _amountControllers = {};
  final Map<int, TextEditingController> _descriptionControllers = {};
  final _taxPercentController = TextEditingController();
  final _servicePercentController = TextEditingController();
  bool _isLoading = false;
  bool _chargesExpanded = false;
  final Set<String> _expandedNotes = {};

  List<String> get _availableFriends => _expenseFriendNames(widget.friends);

  double _numberFrom(TextEditingController? controller) {
    return double.tryParse(controller?.text.trim() ?? '') ?? 0;
  }

  double get _previewSubtotal => _amountControllers.values.fold(
    0,
    (total, controller) => total + _numberFrom(controller),
  );

  double get _previewTax =>
      _previewSubtotal * _numberFrom(_taxPercentController) / 100;

  double get _previewService =>
      _previewSubtotal * _numberFrom(_servicePercentController) / 100;

  String _currency(double value) => 'RM ${value.toStringAsFixed(2)}';

  @override
  void dispose() {
    _titleController.dispose();
    _taxPercentController.dispose();
    _servicePercentController.dispose();
    for (var controller in _amountControllers.values) {
      controller.dispose();
    }
    for (var controller in _descriptionControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncParticipantSelection(Set<String> selected) {
    final existingDebts = <String, DebtEntry>{};
    final amountValues = <String, String>{};
    final descriptionValues = <String, String>{};
    for (var index = 0; index < _debts.length; index++) {
      final friendName = _debts[index].friendName;
      existingDebts[friendName] = _debts[index];
      amountValues[friendName] =
          _amountControllers[index]?.text ?? _debts[index].amount;
      descriptionValues[friendName] =
          _descriptionControllers[index]?.text ?? _debts[index].description;
    }

    final oldAmountControllers = _amountControllers.values.toList();
    final oldDescriptionControllers = _descriptionControllers.values.toList();

    setState(() {
      _debts.clear();
      _amountControllers.clear();
      _descriptionControllers.clear();
      for (final friendName in _availableFriends) {
        if (!selected.contains(friendName)) continue;
        final debt =
            existingDebts[friendName] ?? DebtEntry(friendName: friendName);
        final index = _debts.length;
        _debts.add(debt);
        _amountControllers[index] = TextEditingController(
          text: amountValues[friendName] ?? debt.amount,
        );
        _descriptionControllers[index] = TextEditingController(
          text: descriptionValues[friendName] ?? debt.description,
        );
      }
      _expandedNotes.removeWhere((name) => !selected.contains(name));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in oldAmountControllers) {
        controller.dispose();
      }
      for (final controller in oldDescriptionControllers) {
        controller.dispose();
      }
    });
  }

  bool _hasDraftContent(String friendName) {
    final index = _debts.indexWhere((debt) => debt.friendName == friendName);
    if (index < 0) return false;
    return (_amountControllers[index]?.text.trim().isNotEmpty ?? false) ||
        (_descriptionControllers[index]?.text.trim().isNotEmpty ?? false);
  }

  Future<bool> _confirmParticipantRemoval(Set<String> removed) async {
    final hasDraftContent = removed.any(_hasDraftContent);
    if (!hasDraftContent) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Remove selected friend?"),
            content: const Text(
              "The amount or note entered for this friend will be discarded.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Keep friend"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Remove"),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _selectParticipants() async {
    final current = _debts.map((debt) => debt.friendName).toSet();
    final selected = await _showParticipantPicker(
      context,
      friends: _availableFriends,
      selected: current,
    );
    if (selected == null || !mounted) return;
    final removed = current.difference(selected);
    if (removed.isNotEmpty && !await _confirmParticipantRemoval(removed)) {
      return;
    }
    _syncParticipantSelection(selected);
  }

  Future<void> _removeParticipant(int index) async {
    final friendName = _debts[index].friendName;
    if (!await _confirmParticipantRemoval({friendName}) || !mounted) return;
    final selected = _debts.map((debt) => debt.friendName).toSet()
      ..remove(friendName);
    _syncParticipantSelection(selected);
  }

  Future<void> _splitEqually() async {
    if (_debts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select friends before splitting.")),
      );
      return;
    }
    final total = await _showEqualSplitPrompt(context);
    if (total == null || !mounted) return;
    final shares = splitCurrencyTotal(total, _debts.length);
    setState(() {
      for (var index = 0; index < _debts.length; index++) {
        final value = shares[index].toStringAsFixed(2);
        _debts[index].amount = value;
        _amountControllers[index]?.text = value;
      }
    });
  }

  Future<void> _saveExpense() async {
    final title = _titleController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a description.")),
      );
      return;
    }

    if (_debts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Select at least one friend who owes you."),
        ),
      );
      return;
    }

    // Validate all debts (base amounts before tax/service)
    double baseTotal = 0.0;
    final List<Map<String, dynamic>> debtsData = [];
    final Set<String> friendsToAdd = {};

    for (int i = 0; i < _debts.length; i++) {
      final debt = _debts[i];
      final amountText = _amountControllers[i]?.text.trim() ?? debt.amount;
      final description =
          _descriptionControllers[i]?.text.trim() ?? debt.description;

      if (debt.friendName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please select a friend for all entries."),
          ),
        );
        return;
      }

      if (amountText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Please enter an amount for ${debt.friendName}."),
          ),
        );
        return;
      }

      try {
        final baseAmount = double.parse(amountText);
        if (!baseAmount.isFinite || baseAmount <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Amount must be greater than 0.")),
          );
          return;
        }

        baseTotal += baseAmount;
        // We will apply tax/service after parsing the percentages below.
        debtsData.add({
          'friendName': debt.friendName,
          'baseAmount': baseAmount,
          'description': description,
          'paid': false,
        });
        friendsToAdd.add(debt.friendName);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Invalid amount for ${debt.friendName}.")),
        );
        return;
      }
    }

    // Parse tax and service percentages
    double taxPercent = 0.0;
    double servicePercent = 0.0;
    if (_taxPercentController.text.trim().isNotEmpty) {
      taxPercent = double.tryParse(_taxPercentController.text.trim()) ?? 0.0;
    }
    if (_servicePercentController.text.trim().isNotEmpty) {
      servicePercent =
          double.tryParse(_servicePercentController.text.trim()) ?? 0.0;
    }

    // Apply tax/service per person
    double totalTax = 0.0;
    double totalService = 0.0;
    double totalWithCharges = 0.0;

    for (var debt in debtsData) {
      final baseAmount = (debt['baseAmount'] as num).toDouble();
      final taxForDebt = baseAmount * taxPercent / 100;
      final serviceForDebt = baseAmount * servicePercent / 100;
      final finalAmount = baseAmount + taxForDebt + serviceForDebt;

      debt['amount'] = finalAmount;
      debt['taxAmount'] = taxForDebt;
      debt['serviceAmount'] = serviceForDebt;

      totalTax += taxForDebt;
      totalService += serviceForDebt;
      totalWithCharges += finalAmount;
    }

    final double taxAmount = totalTax;
    final double serviceAmount = totalService;
    final double totalAmount = baseTotal;

    setState(() => _isLoading = true);

    try {
      final groupRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId);

      final expenseRef = groupRef.collection('expenses').doc();
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        transaction.set(expenseRef, {
          'title': title,
          'debts': debtsData,
          'totalAmount': totalAmount,
          'taxPercent': taxPercent,
          'servicePercent': servicePercent,
          'taxAmount': taxAmount,
          'serviceAmount': serviceAmount,
          'totalWithCharges': totalWithCharges,
          'date': FieldValue.serverTimestamp(),
        });
        final groupUpdates = <String, dynamic>{
          'totalOwed': FieldValue.increment(roundCurrency(totalWithCharges)),
        };
        if (friendsToAdd.isNotEmpty) {
          groupUpdates['friends'] = FieldValue.arrayUnion(
            friendsToAdd.toList(),
          );
        }
        transaction.update(groupRef, groupUpdates);
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_availableFriends.isEmpty) {
      return AlertDialog(
        icon: Icon(Icons.group_add_outlined, color: colorScheme.primary),
        title: const Text("Add a friend first"),
        content: const Text(
          "Add someone in Manage Friends before creating an expense.",
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          FilledButton.icon(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await showDialog<void>(
                context: context,
                builder: (context) => ManageFriendsDialog(
                  groupId: widget.groupId,
                  currentFriends: widget.friends,
                ),
              );
              if (mounted) navigator.pop();
            },
            icon: const Icon(Icons.group_add_outlined),
            label: const Text("Manage friends"),
          ),
        ],
      );
    }

    final previewTotal = _previewSubtotal + _previewTax + _previewService;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Add expense",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2),
                Text(
                  "Record a shared cost",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            tooltip: "Close",
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.68,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: "What was it for?",
                  hintText: "Dinner, movie tickets, groceries...",
                  prefixIcon: Icon(Icons.edit_note_outlined),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Who owes you?",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          "Select friends once, then enter custom amounts",
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _selectParticipants,
                    icon: const Icon(Icons.group_add_outlined, size: 18),
                    label: Text(_debts.isEmpty ? "Select" : "Change"),
                  ),
                ],
              ),
              if (_debts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      "${_debts.length} selected",
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _splitEqually,
                      icon: const Icon(Icons.balance_outlined, size: 18),
                      label: const Text("Split equally"),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              if (_debts.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 28,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.group_outlined),
                      SizedBox(height: 8),
                      Text("Select the friends involved in this expense"),
                    ],
                  ),
                )
              else
                ...List.generate(_debts.length, (index) {
                  final debt = _debts[index];
                  return _ParticipantAmountCard(
                    debt: debt,
                    amountController: _amountControllers[index]!,
                    descriptionController: _descriptionControllers[index]!,
                    noteExpanded: _expandedNotes.contains(debt.friendName),
                    onRemove: () => _removeParticipant(index),
                    onToggleNote: () => setState(() {
                      if (!_expandedNotes.add(debt.friendName)) {
                        _expandedNotes.remove(debt.friendName);
                      }
                    }),
                    onAmountChanged: (value) {
                      debt.amount = value;
                      setState(() {});
                    },
                    onDescriptionChanged: (value) {
                      debt.description = value;
                    },
                  );
                }),
              const SizedBox(height: 12),
              _AdditionalChargesSection(
                expanded: _chargesExpanded,
                taxController: _taxPercentController,
                serviceController: _servicePercentController,
                onToggle: () =>
                    setState(() => _chargesExpanded = !_chargesExpanded),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    _ExpensePreviewRow(
                      label: "Subtotal",
                      value: _currency(_previewSubtotal),
                    ),
                    const SizedBox(height: 8),
                    _ExpensePreviewRow(
                      label: "Tax & service",
                      value: _currency(_previewTax + _previewService),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1),
                    ),
                    _ExpensePreviewRow(
                      label: "Total to collect",
                      value: _currency(previewTotal),
                      emphasized: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton.icon(
          onPressed: _isLoading ? null : _saveExpense,
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: Text(_isLoading ? "Saving..." : "Save expense"),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ],
    );
  }
}

class _ExpensePreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _ExpensePreviewRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: emphasized ? 16 : 14,
      fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
    );

    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}

// ==========================================
// DIALOG 3: EDIT EXPENSE
// ==========================================

class EditExpenseDialog extends StatefulWidget {
  final String groupId;
  final String expenseId;
  final List<dynamic> friends;
  final String initialTitle;
  final List<Map<String, dynamic>> initialDebts;
  final double initialTaxPercent;
  final double initialServicePercent;

  const EditExpenseDialog({
    super.key,
    required this.groupId,
    required this.expenseId,
    required this.friends,
    required this.initialTitle,
    required this.initialDebts,
    required this.initialTaxPercent,
    required this.initialServicePercent,
  });

  @override
  State<EditExpenseDialog> createState() => _EditExpenseDialogState();
}

class _EditExpenseDialogState extends State<EditExpenseDialog> {
  final _titleController = TextEditingController();
  final List<DebtEntry> _debts = [];
  final Map<int, TextEditingController> _amountControllers = {};
  final Map<int, TextEditingController> _descriptionControllers = {};
  final _taxPercentController = TextEditingController();
  final _servicePercentController = TextEditingController();
  bool _isLoading = false;
  bool _chargesExpanded = false;
  final Set<String> _expandedNotes = {};

  List<String> get _availableFriends => _expenseFriendNames(
    widget.friends,
    include: widget.initialDebts.map(
      (debt) => debt['friendName']?.toString() ?? '',
    ),
  );

  double _numberFrom(TextEditingController? controller) {
    return double.tryParse(controller?.text.trim() ?? '') ?? 0;
  }

  double get _previewSubtotal => _amountControllers.values.fold(
    0,
    (total, controller) => total + _numberFrom(controller),
  );

  double get _previewCharges =>
      _previewSubtotal *
      (_numberFrom(_taxPercentController) +
          _numberFrom(_servicePercentController)) /
      100;

  int get _selectedFriendCount =>
      _debts.map((debt) => debt.friendName).toSet().length;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.initialTitle;
    _taxPercentController.text = widget.initialTaxPercent == 0.0
        ? ''
        : widget.initialTaxPercent.toString();
    _servicePercentController.text = widget.initialServicePercent == 0.0
        ? ''
        : widget.initialServicePercent.toString();
    _chargesExpanded =
        widget.initialTaxPercent != 0 || widget.initialServicePercent != 0;

    // Convert initial debts to DebtEntry objects
    for (var debt in widget.initialDebts) {
      final friendName = debt['friendName'] as String? ?? '';
      if (friendName.trim().isEmpty) continue;
      final amountWithCharges = (debt['amount'] as num?)?.toDouble() ?? 0.0;
      final baseAmount =
          (debt['baseAmount'] as num?)?.toDouble() ?? amountWithCharges;
      final description = debt['description'] as String? ?? '';
      final paid = debt['paid'] as bool? ?? false;

      final index = _debts.length;
      _debts.add(
        DebtEntry(
          friendName: friendName,
          amount: baseAmount.toStringAsFixed(2),
          description: description,
          paid: paid,
        ),
      );

      _amountControllers[index] = TextEditingController(
        text: baseAmount.toStringAsFixed(2),
      );
      _descriptionControllers[index] = TextEditingController(text: description);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _taxPercentController.dispose();
    _servicePercentController.dispose();
    for (var controller in _amountControllers.values) {
      controller.dispose();
    }
    for (var controller in _descriptionControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncParticipantSelection(Set<String> selected) {
    final existingDebts = <String, List<DebtEntry>>{};
    final amountValues = <DebtEntry, String>{};
    final descriptionValues = <DebtEntry, String>{};
    for (var index = 0; index < _debts.length; index++) {
      final debt = _debts[index];
      existingDebts.putIfAbsent(debt.friendName, () => []).add(debt);
      amountValues[debt] = _amountControllers[index]?.text ?? debt.amount;
      descriptionValues[debt] =
          _descriptionControllers[index]?.text ?? debt.description;
    }

    final oldAmountControllers = _amountControllers.values.toList();
    final oldDescriptionControllers = _descriptionControllers.values.toList();

    setState(() {
      _debts.clear();
      _amountControllers.clear();
      _descriptionControllers.clear();
      for (final friendName in _availableFriends) {
        if (!selected.contains(friendName)) continue;
        final debtsForFriend =
            existingDebts[friendName] ?? [DebtEntry(friendName: friendName)];
        for (final debt in debtsForFriend) {
          final index = _debts.length;
          _debts.add(debt);
          _amountControllers[index] = TextEditingController(
            text: amountValues[debt] ?? debt.amount,
          );
          _descriptionControllers[index] = TextEditingController(
            text: descriptionValues[debt] ?? debt.description,
          );
        }
      }
      _expandedNotes.removeWhere((name) => !selected.contains(name));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in oldAmountControllers) {
        controller.dispose();
      }
      for (final controller in oldDescriptionControllers) {
        controller.dispose();
      }
    });
  }

  bool _hasDraftContent(String friendName) {
    for (var index = 0; index < _debts.length; index++) {
      if (_debts[index].friendName != friendName) continue;
      if ((_amountControllers[index]?.text.trim().isNotEmpty ?? false) ||
          (_descriptionControllers[index]?.text.trim().isNotEmpty ?? false)) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _confirmParticipantRemoval(Set<String> removed) async {
    final hasDraftContent = removed.any(_hasDraftContent);
    if (!hasDraftContent) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Remove selected friend?"),
            content: const Text(
              "Their amount, note, and payment status will be removed from this expense.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Keep friend"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Remove"),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _selectParticipants() async {
    final current = _debts.map((debt) => debt.friendName).toSet();
    final selected = await _showParticipantPicker(
      context,
      friends: _availableFriends,
      selected: current,
    );
    if (selected == null || !mounted) return;
    final removed = current.difference(selected);
    if (removed.isNotEmpty && !await _confirmParticipantRemoval(removed)) {
      return;
    }
    _syncParticipantSelection(selected);
  }

  Future<void> _removeParticipant(int index) async {
    final friendName = _debts[index].friendName;
    if (!await _confirmParticipantRemoval({friendName}) || !mounted) return;
    final selected = _debts.map((debt) => debt.friendName).toSet()
      ..remove(friendName);
    _syncParticipantSelection(selected);
  }

  Future<void> _splitEqually() async {
    if (_debts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select friends before splitting.")),
      );
      return;
    }
    final total = await _showEqualSplitPrompt(context);
    if (total == null || !mounted) return;
    final friendNames = _debts.map((debt) => debt.friendName).toSet().toList();
    final friendShares = splitCurrencyTotal(total, friendNames.length);
    setState(() {
      for (
        var friendIndex = 0;
        friendIndex < friendNames.length;
        friendIndex++
      ) {
        final rowIndexes = <int>[
          for (var index = 0; index < _debts.length; index++)
            if (_debts[index].friendName == friendNames[friendIndex]) index,
        ];
        final rowShares = splitCurrencyTotal(
          friendShares[friendIndex],
          rowIndexes.length,
        );
        for (var rowIndex = 0; rowIndex < rowIndexes.length; rowIndex++) {
          final debtIndex = rowIndexes[rowIndex];
          final value = rowShares[rowIndex].toStringAsFixed(2);
          _debts[debtIndex].amount = value;
          _amountControllers[debtIndex]?.text = value;
        }
      }
    });
  }

  Future<void> _updateExpense() async {
    final title = _titleController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a description.")),
      );
      return;
    }

    if (_debts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Select at least one friend who owes you."),
        ),
      );
      return;
    }

    // Validate all debts (base amounts before tax/service)
    double newBaseTotal = 0.0;
    final List<Map<String, dynamic>> debtsData = [];
    final Set<String> friendsToAdd = {};

    for (int i = 0; i < _debts.length; i++) {
      final debt = _debts[i];
      final amountText = _amountControllers[i]?.text.trim() ?? debt.amount;
      final description =
          _descriptionControllers[i]?.text.trim() ?? debt.description;

      if (debt.friendName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please select a friend for all entries."),
          ),
        );
        return;
      }

      if (amountText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Please enter an amount for ${debt.friendName}."),
          ),
        );
        return;
      }

      try {
        final baseAmount = double.parse(amountText);
        if (!baseAmount.isFinite || baseAmount <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Amount must be greater than 0.")),
          );
          return;
        }

        newBaseTotal += baseAmount;
        debtsData.add({
          'friendName': debt.friendName,
          'baseAmount': baseAmount,
          'description': description,
          'paid': debt.paid, // Preserve paid status
        });
        friendsToAdd.add(debt.friendName);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Invalid amount for ${debt.friendName}.")),
        );
        return;
      }
    }

    // Parse tax and service percentages
    double taxPercent = 0.0;
    double servicePercent = 0.0;
    if (_taxPercentController.text.trim().isNotEmpty) {
      taxPercent = double.tryParse(_taxPercentController.text.trim()) ?? 0.0;
    }
    if (_servicePercentController.text.trim().isNotEmpty) {
      servicePercent =
          double.tryParse(_servicePercentController.text.trim()) ?? 0.0;
    }

    // Apply tax/service per person
    double totalTax = 0.0;
    double totalService = 0.0;
    double totalWithCharges = 0.0;

    for (var debt in debtsData) {
      final baseAmount = (debt['baseAmount'] as num).toDouble();
      final taxForDebt = baseAmount * taxPercent / 100;
      final serviceForDebt = baseAmount * servicePercent / 100;
      final finalAmount = baseAmount + taxForDebt + serviceForDebt;

      debt['amount'] = finalAmount;
      debt['taxAmount'] = taxForDebt;
      debt['serviceAmount'] = serviceForDebt;

      totalTax += taxForDebt;
      totalService += serviceForDebt;
      totalWithCharges += finalAmount;
    }

    final double taxAmount = totalTax;
    final double serviceAmount = totalService;
    final double totalAmount = newBaseTotal;

    setState(() => _isLoading = true);

    try {
      final groupRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId);
      final expenseRef = groupRef.collection('expenses').doc(widget.expenseId);

      final updatedExpense = <String, dynamic>{
        'title': title,
        'debts': debtsData,
        'totalAmount': totalAmount,
        'taxPercent': taxPercent,
        'servicePercent': servicePercent,
        'taxAmount': taxAmount,
        'serviceAmount': serviceAmount,
        'totalWithCharges': totalWithCharges,
      };
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final currentSnapshot = await transaction.get(expenseRef);
        if (!currentSnapshot.exists) {
          throw StateError('Expense no longer exists.');
        }
        final currentExpense = currentSnapshot.data() as Map<String, dynamic>;
        final difference = roundCurrency(
          outstandingExpenseTotal(updatedExpense) -
              outstandingExpenseTotal(currentExpense),
        );
        transaction.update(expenseRef, updatedExpense);
        final groupUpdates = <String, dynamic>{};
        if (difference != 0) {
          groupUpdates['totalOwed'] = FieldValue.increment(difference);
        }
        if (friendsToAdd.isNotEmpty) {
          groupUpdates['friends'] = FieldValue.arrayUnion(
            friendsToAdd.toList(),
          );
        }
        if (groupUpdates.isNotEmpty) {
          transaction.update(groupRef, groupUpdates);
        }
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_availableFriends.isEmpty) {
      return AlertDialog(
        title: const Text("Edit Expense"),
        content: const Text(
          "Please add at least one friend first in the Manage Friends section.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          FilledButton.icon(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await showDialog<void>(
                context: context,
                builder: (context) => ManageFriendsDialog(
                  groupId: widget.groupId,
                  currentFriends: widget.friends,
                ),
              );
              if (mounted) navigator.pop();
            },
            icon: const Icon(Icons.group_add_outlined),
            label: const Text("Manage friends"),
          ),
        ],
      );
    }

    final previewTotal = _previewSubtotal + _previewCharges;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.edit_note_outlined,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Edit expense",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2),
                Text(
                  "Update the expense and its shares",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.68,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: "What was it for?",
                  hintText: "Dinner, movie tickets, groceries...",
                  prefixIcon: Icon(Icons.edit_note_outlined),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Who owes you?",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          "Select friends once; paid shares keep their status",
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _selectParticipants,
                    icon: const Icon(Icons.group_add_outlined, size: 18),
                    label: Text(_debts.isEmpty ? "Select" : "Change"),
                  ),
                ],
              ),
              if (_debts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      "$_selectedFriendCount selected",
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _splitEqually,
                      icon: const Icon(Icons.balance_outlined, size: 18),
                      label: const Text("Split equally"),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              if (_debts.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 28,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.group_outlined),
                      SizedBox(height: 8),
                      Text("Select the friends involved in this expense"),
                    ],
                  ),
                )
              else
                ...List.generate(_debts.length, (index) {
                  final debt = _debts[index];
                  return _ParticipantAmountCard(
                    debt: debt,
                    amountController: _amountControllers[index]!,
                    descriptionController: _descriptionControllers[index]!,
                    noteExpanded: _expandedNotes.contains(debt.friendName),
                    onRemove: () => _removeParticipant(index),
                    onToggleNote: () => setState(() {
                      if (!_expandedNotes.add(debt.friendName)) {
                        _expandedNotes.remove(debt.friendName);
                      }
                    }),
                    onAmountChanged: (value) {
                      debt.amount = value;
                      setState(() {});
                    },
                    onDescriptionChanged: (value) {
                      debt.description = value;
                    },
                  );
                }),
              const SizedBox(height: 12),
              _AdditionalChargesSection(
                expanded: _chargesExpanded,
                taxController: _taxPercentController,
                serviceController: _servicePercentController,
                onToggle: () =>
                    setState(() => _chargesExpanded = !_chargesExpanded),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    _ExpensePreviewRow(
                      label: "Subtotal",
                      value: "RM ${_previewSubtotal.toStringAsFixed(2)}",
                    ),
                    const SizedBox(height: 8),
                    _ExpensePreviewRow(
                      label: "Tax & service",
                      value: "RM ${_previewCharges.toStringAsFixed(2)}",
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1),
                    ),
                    _ExpensePreviewRow(
                      label: "Updated total",
                      value: "RM ${previewTotal.toStringAsFixed(2)}",
                      emphasized: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton.icon(
          onPressed: _isLoading ? null : _updateExpense,
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isLoading ? "Updating..." : "Update expense"),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ],
    );
  }
}

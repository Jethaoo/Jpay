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

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _titleController = TextEditingController();
  final List<DebtEntry> _debts = [];
  final Map<int, TextEditingController> _amountControllers = {};
  final Map<int, TextEditingController> _descriptionControllers = {};
  final _taxPercentController = TextEditingController();
  final _servicePercentController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.friends.isNotEmpty) {
      _debts.add(DebtEntry(friendName: ''));
      _amountControllers[0] = TextEditingController();
      _descriptionControllers[0] = TextEditingController();
    }
  }

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

  void _addDebtEntry() {
    setState(() {
      final newIndex = _debts.length;
      _debts.add(DebtEntry(friendName: ''));
      _amountControllers[newIndex] = TextEditingController();
      _descriptionControllers[newIndex] = TextEditingController();
    });
  }

  void _removeDebtEntry(int index) {
    setState(() {
      _amountControllers[index]?.dispose();
      _descriptionControllers[index]?.dispose();
      _amountControllers.remove(index);
      _descriptionControllers.remove(index);
      _debts.removeAt(index);

      // Reindex controllers
      final newAmountControllers = <int, TextEditingController>{};
      final newDescriptionControllers = <int, TextEditingController>{};
      for (int i = 0; i < _debts.length; i++) {
        if (_amountControllers.containsKey(i + 1)) {
          newAmountControllers[i] = _amountControllers[i + 1]!;
        } else {
          newAmountControllers[i] = TextEditingController(
            text: _debts[i].amount,
          );
        }
        if (_descriptionControllers.containsKey(i + 1)) {
          newDescriptionControllers[i] = _descriptionControllers[i + 1]!;
        } else {
          newDescriptionControllers[i] = TextEditingController(
            text: _debts[i].description,
          );
        }
      }
      _amountControllers.clear();
      _descriptionControllers.clear();
      _amountControllers.addAll(newAmountControllers);
      _descriptionControllers.addAll(newDescriptionControllers);
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
          content: Text("Please add at least one friend who owes you."),
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
        if (baseAmount <= 0) {
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

    if (widget.friends.isEmpty) {
      return AlertDialog(
        icon: Icon(Icons.group_add_outlined, color: colorScheme.primary),
        title: const Text("Add a friend first"),
        content: const Text(
          "Add someone in Manage Friends before creating an expense.",
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Got it"),
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
              const SizedBox(height: 24),
              const Text(
                "Additional charges",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                "Applied proportionally to every person's share.",
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _taxPercentController,
                      decoration: const InputDecoration(
                        labelText: "Tax",
                        hintText: "0",
                        suffixText: "%",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _servicePercentController,
                      decoration: const InputDecoration(
                        labelText: "Service",
                        hintText: "0",
                        suffixText: "%",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
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
                          "Add each person's individual share",
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _addDebtEntry,
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text("Add"),
                  ),
                ],
              ),
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
                      Text("No shares added yet"),
                    ],
                  ),
                )
              else
                ...List.generate(_debts.length, (index) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    color: colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  "${index + 1}",
                                  style: TextStyle(
                                    color: colorScheme.onSecondaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Share ${index + 1}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: colorScheme.error,
                                ),
                                onPressed: () => _removeDebtEntry(index),
                                tooltip: "Remove share",
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    "friend-$index-${_debts[index].friendName}",
                                  ),
                                  initialValue: _debts[index].friendName.isEmpty
                                      ? null
                                      : _debts[index].friendName,
                                  decoration: const InputDecoration(
                                    labelText: "Friend",
                                    prefixIcon: Icon(Icons.person_outline),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 16,
                                    ),
                                  ),
                                  items: widget.friends
                                      .map<DropdownMenuItem<String>>((
                                        dynamic value,
                                      ) {
                                        return DropdownMenuItem<String>(
                                          value: value.toString(),
                                          child: Text(value.toString()),
                                        );
                                      })
                                      .toList(),
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      _debts[index].friendName = newValue ?? '';
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _amountControllers[index] ??=
                                TextEditingController(
                                  text: _debts[index].amount,
                                ),
                            decoration: const InputDecoration(
                              labelText: "Base amount",
                              prefixText: "RM ",
                              hintText: "0.00",
                              helperText: "Before tax and service",
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (value) {
                              _debts[index].amount = value;
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _descriptionControllers[index] ??=
                                TextEditingController(
                                  text: _debts[index].description,
                                ),
                            decoration: const InputDecoration(
                              labelText: "Note (optional)",
                              hintText: "Their share of dinner",
                              prefixIcon: Icon(Icons.notes_outlined),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (value) {
                              _debts[index].description = value;
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 4),
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

    // Convert initial debts to DebtEntry objects
    for (var debt in widget.initialDebts) {
      final friendName = debt['friendName'] as String? ?? '';
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

  void _addDebtEntry() {
    setState(() {
      final newIndex = _debts.length;
      _debts.add(DebtEntry(friendName: ''));
      _amountControllers[newIndex] = TextEditingController();
      _descriptionControllers[newIndex] = TextEditingController();
    });
  }

  void _removeDebtEntry(int index) {
    setState(() {
      _amountControllers[index]?.dispose();
      _descriptionControllers[index]?.dispose();
      _amountControllers.remove(index);
      _descriptionControllers.remove(index);
      _debts.removeAt(index);

      // Reindex controllers
      final newAmountControllers = <int, TextEditingController>{};
      final newDescriptionControllers = <int, TextEditingController>{};
      for (int i = 0; i < _debts.length; i++) {
        if (_amountControllers.containsKey(i + 1)) {
          newAmountControllers[i] = _amountControllers[i + 1]!;
        } else {
          newAmountControllers[i] = TextEditingController(
            text: _debts[i].amount,
          );
        }
        if (_descriptionControllers.containsKey(i + 1)) {
          newDescriptionControllers[i] = _descriptionControllers[i + 1]!;
        } else {
          newDescriptionControllers[i] = TextEditingController(
            text: _debts[i].description,
          );
        }
      }
      _amountControllers.clear();
      _descriptionControllers.clear();
      _amountControllers.addAll(newAmountControllers);
      _descriptionControllers.addAll(newDescriptionControllers);
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
          content: Text("Please add at least one friend who owes you."),
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
        if (baseAmount <= 0) {
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

    if (widget.friends.isEmpty) {
      return AlertDialog(
        title: const Text("Edit Expense"),
        content: const Text(
          "Please add at least one friend first in the Manage Friends section.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
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
              const Text(
                "Additional charges",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _taxPercentController,
                      decoration: const InputDecoration(
                        labelText: "Tax",
                        hintText: "0",
                        suffixText: "%",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _servicePercentController,
                      decoration: const InputDecoration(
                        labelText: "Service",
                        hintText: "0",
                        suffixText: "%",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
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
                          "Paid shares keep their current status",
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _addDebtEntry,
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text("Add"),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_debts.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppPalette.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      "Tap 'Add Friend' to add someone who owes you",
                      style: TextStyle(color: AppPalette.secondaryLabel),
                    ),
                  ),
                )
              else
                ...List.generate(_debts.length, (index) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    "edit-friend-$index-${_debts[index].friendName}",
                                  ),
                                  initialValue: _debts[index].friendName.isEmpty
                                      ? null
                                      : _debts[index].friendName,
                                  decoration: const InputDecoration(
                                    labelText: "Friend",
                                    prefixIcon: Icon(Icons.person_outline),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 16,
                                    ),
                                  ),
                                  items: widget.friends
                                      .map<DropdownMenuItem<String>>((
                                        dynamic value,
                                      ) {
                                        return DropdownMenuItem<String>(
                                          value: value.toString(),
                                          child: Text(value.toString()),
                                        );
                                      })
                                      .toList(),
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      _debts[index].friendName = newValue ?? '';
                                    });
                                  },
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: colorScheme.error,
                                ),
                                onPressed: () => _removeDebtEntry(index),
                                tooltip: "Remove",
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _amountControllers[index] ??=
                                TextEditingController(
                                  text: _debts[index].amount,
                                ),
                            decoration: const InputDecoration(
                              labelText: "Base amount (before tax/service)",
                              prefixText: "RM ",
                              hintText: "0.00",
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (value) {
                              _debts[index].amount = value;
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _descriptionControllers[index] ??=
                                TextEditingController(
                                  text: _debts[index].description,
                                ),
                            decoration: const InputDecoration(
                              labelText: "Note (optional)",
                              hintText: "Their share of dinner",
                              prefixIcon: Icon(Icons.notes_outlined),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (value) {
                              _debts[index].description = value;
                            },
                          ),
                          if (_debts[index].paid)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      color: colorScheme.onTertiaryContainer,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "This debt is marked as paid",
                                      style: TextStyle(
                                        color: colorScheme.onTertiaryContainer,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
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

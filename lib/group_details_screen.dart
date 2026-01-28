import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

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
      stream: FirebaseFirestore.instance.collection('groups').doc(groupId).snapshots(),
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

        return Scaffold(
          appBar: AppBar(
            title: Text(
              groupName,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            elevation: 0,
          ),
          
          // 3. BODY: Balances Summary + Expenses List
          body: Column(
            children: [
              // --- Balances Summary ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.indigo.shade50,
                      Colors.indigo.shade100,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet, size: 20, color: Colors.indigo),
                    const SizedBox(width: 8),
                        Text(
                          "Who Owes You",
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const Spacer(),
                    TextButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                              builder: (context) => ManageFriendsDialog(
                            groupId: groupId,
                                currentFriends: friends,
                          ),
                        );
                      },
                          child: const Text("Manage Friends"),
                        )
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
                          final expense = expenseDoc.data() as Map<String, dynamic>;
                          
                          // Support both old format (owedBy) and new format (debts array)
                          if (expense.containsKey('debts')) {
                            // New format: debts array
                            final debts = expense['debts'] as List? ?? [];
                            for (var debt in debts) {
                              final debtData = debt as Map<String, dynamic>;
                              final paid = debtData['paid'] as bool? ?? false;
                              if (paid) continue; // Skip paid debts
                              
                              double amount = (debtData['amount'] as num?)?.toDouble() ?? 0.0;

                              // Calculate final amount with tax/service
                              final hasBaseAmount = debtData['baseAmount'] != null;
                              if (hasBaseAmount) {
                                // New format: calculate from baseAmount + per-person tax/service
                                final baseAmount = (debtData['baseAmount'] as num?)?.toDouble() ?? 0.0;
                                final taxForDebt = (debtData['taxAmount'] as num?)?.toDouble() ?? 0.0;
                                final serviceForDebt = (debtData['serviceAmount'] as num?)?.toDouble() ?? 0.0;
                                amount = baseAmount + taxForDebt + serviceForDebt;
                              } else {
                                // Backward compatibility: for older expenses that don't
                                // have per-person tax/service, distribute expense-level
                                // tax/service proportionally by base amount.
                                final expenseBaseTotal =
                                    (expense['totalAmount'] as num?)?.toDouble() ?? 0.0;
                                final expenseTaxAmount =
                                    (expense['taxAmount'] as num?)?.toDouble() ?? 0.0;
                                final expenseServiceAmount =
                                    (expense['serviceAmount'] as num?)?.toDouble() ?? 0.0;
                                if (expenseBaseTotal > 0 &&
                                    (expenseTaxAmount != 0 || expenseServiceAmount != 0)) {
                                  final ratio = amount / expenseBaseTotal;
                                  amount = amount +
                                      expenseTaxAmount * ratio +
                                      expenseServiceAmount * ratio;
                                }
                              }

                              final friendName = debtData['friendName'] as String? ?? '';
                              
                              if (friendName.isNotEmpty) {
                                balances[friendName] = (balances[friendName] ?? 0.0) + amount;
                              }
                            }
                          } else {
                            // Old format: single owedBy (for backward compatibility)
                            final paid = expense['paid'] as bool? ?? false;
                            if (paid) continue; // Skip paid expenses
                            
                            final amount = (expense['amount'] as num?)?.toDouble() ?? 0.0;
                            final owedBy = expense['owedBy'] as String? ?? '';
                            
                            if (owedBy.isNotEmpty) {
                              balances[owedBy] = (balances[owedBy] ?? 0.0) + amount;
                            }
                          }
                        }
                        
                        if (balances.isEmpty) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  "No outstanding balances",
                                  style: GoogleFonts.inter(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }
                        
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...balances.entries.map((entry) {
                              final friendName = entry.key;
                              final amount = entry.value;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        friendName,
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        "RM ${amount.toStringAsFixed(2)}",
                                        style: GoogleFonts.inter(
                                          color: Colors.red.shade700,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.check_circle, size: 20),
                                      color: Colors.green,
                                      tooltip: "Mark all as paid",
                                      onPressed: () => _markAllDebtsAsPaidForFriend(
                                        context,
                                        groupId,
                                        friendName,
                                        amount,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              // --- Expenses List (Inner Stream) ---
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('groups')
                      .doc(groupId)
                      .collection('expenses')
                      .orderBy('date', descending: true)
                      .snapshots(),
                  builder: (context, expenseSnapshot) {
                    if (expenseSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!expenseSnapshot.hasData || expenseSnapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text("No expenses yet. Tap + to add one."),
                      );
                    }

                    final expenses = expenseSnapshot.data!.docs;

                    return ListView.builder(
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
                        final double totalWithCharges =
                            (data['totalWithCharges'] as num?)?.toDouble() ??
                            (totalAmount + taxAmount + serviceAmount);
                        bool allPaid = true;
                        
                        if (hasDebts) {
                          // New format: debts array
                          final debtsList = data['debts'] as List? ?? [];
                          debts = debtsList.map((d) => d as Map<String, dynamic>).toList();
                          for (var debt in debts) {
                            final amount = (debt['amount'] as num?)?.toDouble() ?? 0.0;
                            totalAmount += amount;
                            if (!(debt['paid'] as bool? ?? false)) {
                              allPaid = false;
                            }
                          }
                        } else {
                          // Old format: single owedBy (for backward compatibility)
                          final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                          final owedBy = data['owedBy'] as String? ?? '';
                          final paid = data['paid'] as bool? ?? false;
                          totalAmount = amount;
                          allPaid = paid;
                          debts = [{
                            'friendName': owedBy,
                            'amount': amount,
                            'description': '',
                            'paid': paid,
                          }];
                        }

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          elevation: 2,
                          color: allPaid ? Colors.grey.shade100 : null,
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: allPaid ? Colors.green.shade100 : Colors.indigo.shade100,
                              child: Icon(
                                allPaid ? Icons.check_circle : Icons.receipt,
                                color: allPaid ? Colors.green : Colors.indigo,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      decoration: allPaid ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                ),
                                if (allPaid)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                                  "${debts.length} friend${debts.length != 1 ? 's' : ''} • Subtotal: RM ${totalAmount.toStringAsFixed(2)}",
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                if (taxAmount > 0 || serviceAmount > 0)
                                  Text(
                                    "Tax: RM ${taxAmount.toStringAsFixed(2)} • Service: RM ${serviceAmount.toStringAsFixed(2)} • Total: RM ${totalWithCharges.toStringAsFixed(2)}",
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                if (date != null)
                                  Text(
                                    _formatDate(date),
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  color: Colors.blue,
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
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: allPaid ? Colors.grey : Colors.red.shade700,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                  ],
                                ),
                              ],
                            ),
                            children: debts.map((debt) {
                              final friendName = debt['friendName'] as String? ?? '';
                              double amount = (debt['amount'] as num?)?.toDouble() ?? 0.0;
                              
                              // Calculate final amount with tax/service if needed
                              final hasBaseAmount = debt['baseAmount'] != null;
                              if (hasBaseAmount) {
                                // New format: calculate from baseAmount + per-person tax/service
                                final baseAmount = (debt['baseAmount'] as num?)?.toDouble() ?? 0.0;
                                final taxForDebt = (debt['taxAmount'] as num?)?.toDouble() ?? 0.0;
                                final serviceForDebt = (debt['serviceAmount'] as num?)?.toDouble() ?? 0.0;
                                amount = baseAmount + taxForDebt + serviceForDebt;
                              } else {
                                // Backward compatibility: distribute expense-level tax/service proportionally
                                final expenseBaseTotal = totalAmount;
                                final expenseTaxAmount = taxAmount;
                                final expenseServiceAmount = serviceAmount;
                                if (expenseBaseTotal > 0 && (expenseTaxAmount != 0 || expenseServiceAmount != 0)) {
                                  final ratio = amount / expenseBaseTotal;
                                  amount = amount + expenseTaxAmount * ratio + expenseServiceAmount * ratio;
                                }
                              }
                              
                              final description = debt['description'] as String? ?? '';
                              final paid = debt['paid'] as bool? ?? false;
                              
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  paid ? Icons.check_circle : Icons.person_outline,
                                  color: paid ? Colors.green : Colors.grey,
                                  size: 20,
                                ),
                                title: Text(
                                  friendName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    decoration: paid ? TextDecoration.lineThrough : null,
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
                                        color: paid ? Colors.grey : Colors.red.shade700,
                                      ),
                                    ),
                                    if (!paid)
                                      IconButton(
                                        icon: const Icon(Icons.check_circle_outline, size: 18),
                                        color: Colors.green,
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
                builder: (context) => AddExpenseDialog(
                  groupId: groupId,
                  friends: friends,
                ),
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

  Future<void> _markDebtAsPaid(BuildContext context, String expenseId, String groupId, int debtIndex, double amount) async {
    try {
      final expenseRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('expenses')
          .doc(expenseId);

      // Get current expense data
      final expenseDoc = await expenseRef.get();
      if (!expenseDoc.exists) return;

      final data = expenseDoc.data() as Map<String, dynamic>;
      
      if (data.containsKey('debts')) {
        // New format: update specific debt in array
        // Note: Cannot use FieldValue.serverTimestamp() inside arrays, so we use DateTime.now()
        final debts = List<Map<String, dynamic>>.from(data['debts'] as List);
        if (debtIndex >= 0 && debtIndex < debts.length) {
          final debt = debts[debtIndex];
          // Recompute effective amount (including tax/service) for safety
          double effectiveAmount =
              (debt['amount'] as num?)?.toDouble() ?? amount;
          final baseAmount =
              (debt['baseAmount'] as num?)?.toDouble();
          if (baseAmount == null) {
            final expenseBaseTotal =
                (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
            final expenseTaxAmount =
                (data['taxAmount'] as num?)?.toDouble() ?? 0.0;
            final expenseServiceAmount =
                (data['serviceAmount'] as num?)?.toDouble() ?? 0.0;
            if (expenseBaseTotal > 0 &&
                (expenseTaxAmount != 0 || expenseServiceAmount != 0)) {
              final ratio = effectiveAmount / expenseBaseTotal;
              effectiveAmount = effectiveAmount +
                  expenseTaxAmount * ratio +
                  expenseServiceAmount * ratio;
            }
          }

          debts[debtIndex]['paid'] = true;
          final now = DateTime.now();
          debts[debtIndex]['paidAt'] =
              '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

          await expenseRef.update({'debts': debts});

          // Decrease total owed with effective amount
          final groupRef = FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId);
          await groupRef.update({
            'totalOwed': FieldValue.increment(-effectiveAmount),
          });

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Payment marked as received!")),
            );
          }
          return;
        }
      } else {
        // Old format: mark entire expense as paid
        await expenseRef.update({
          'paid': true,
          'paidAt': FieldValue.serverTimestamp(),
        });
      }

      // Old-format expense: decrease total owed using original amount
      final groupRef = FirebaseFirestore.instance.collection('groups').doc(groupId);
      await groupRef.update({
        'totalOwed': FieldValue.increment(-amount),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Payment marked as received!")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
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
              debt['paidAt'] = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
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
              'paidAt': FieldValue.serverTimestamp(), // This is OK at document level
            });
            totalMarkedAsPaid += amount;
          }
        }
      }

      // Update total owed
      if (totalMarkedAsPaid > 0) {
        final groupRef = FirebaseFirestore.instance.collection('groups').doc(groupId);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
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

  Future<void> _addFriend() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    // Check strict duplicates
    if (widget.currentFriends.contains(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Friend already exists!")),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
        'friends': FieldValue.arrayUnion([name]),
      });
      _nameController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _removeFriend(String friendName) async {
    try {
      await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
        'friends': FieldValue.arrayRemove([friendName]),
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Manage Friends"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: "Friend Name (e.g. John)"),
                  textCapitalization: TextCapitalization.words,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.indigo),
                onPressed: _addFriend,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(),
          SizedBox(
            height: 200,
            width: double.maxFinite,
            child: widget.currentFriends.isEmpty
                ? const Center(child: Text("No friends added yet"))
                : ListView.builder(
              shrinkWrap: true,
                    itemCount: widget.currentFriends.length,
              itemBuilder: (context, index) {
                      final friend = widget.currentFriends[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.person),
                        title: Text(friend.toString()),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                          onPressed: () => _removeFriend(friend.toString()),
                        ),
                );
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Done")),
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
          newAmountControllers[i] = TextEditingController(text: _debts[i].amount);
        }
        if (_descriptionControllers.containsKey(i + 1)) {
          newDescriptionControllers[i] = _descriptionControllers[i + 1]!;
        } else {
          newDescriptionControllers[i] = TextEditingController(text: _debts[i].description);
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
        const SnackBar(content: Text("Please add at least one friend who owes you.")),
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
      final description = _descriptionControllers[i]?.text.trim() ?? debt.description;
      
      if (debt.friendName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select a friend for all entries.")),
        );
        return;
      }

      if (amountText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Please enter an amount for ${debt.friendName}.")),
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
      final groupRef = FirebaseFirestore.instance.collection('groups').doc(widget.groupId);

      // Add expense with multiple debts
      await groupRef.collection('expenses').add({
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

      // Update total owed
      await groupRef.update({
        'totalOwed': FieldValue.increment(totalWithCharges),
      });

      // Add any new friends to the friends list
      if (friendsToAdd.isNotEmpty) {
        await groupRef.update({
          'friends': FieldValue.arrayUnion(friendsToAdd.toList()),
        });
      }

      if (mounted) Navigator.pop(context); 
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.friends.isEmpty) {
      return AlertDialog(
        title: const Text("Add Expense"),
        content: const Text("Please add at least one friend first in the Manage Friends section."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text("Add Expense"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: "Expense Description",
                hintText: "e.g. Dinner, Movie tickets",
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _taxPercentController,
                    decoration: const InputDecoration(
                      labelText: "Tax % (optional)",
                      hintText: "e.g. 6",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _servicePercentController,
                    decoration: const InputDecoration(
                      labelText: "Service % (optional)",
                      hintText: "e.g. 10",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Who Owes You?",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                TextButton.icon(
                  onPressed: _addDebtEntry,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("Add Friend"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_debts.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    "Tap 'Add Friend' to add someone who owes you",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ...List.generate(_debts.length, (index) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _debts[index].friendName.isEmpty
                                    ? null
                                    : _debts[index].friendName,
                                decoration: const InputDecoration(
                                  labelText: "Friend",
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                ),
                                items: widget.friends.map<DropdownMenuItem<String>>((dynamic value) {
                                  return DropdownMenuItem<String>(
                                    value: value.toString(),
                                    child: Text(value.toString()),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  setState(() {
                                    _debts[index].friendName = newValue ?? '';
                                  });
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _removeDebtEntry(index),
                              tooltip: "Remove",
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
            TextField(
                          controller: _amountControllers[index] ??= TextEditingController(text: _debts[index].amount),
                          decoration: const InputDecoration(
                            labelText: "Base amount (before tax/service)",
                            prefixText: "RM ",
                            hintText: "0.00",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (value) {
                            _debts[index].amount = value;
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _descriptionControllers[index] ??= TextEditingController(text: _debts[index].description),
                          decoration: const InputDecoration(
                            labelText: "Description (optional)",
                            hintText: "e.g. Their share of dinner",
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        if (_isLoading)
          const CircularProgressIndicator()
        else
          ElevatedButton(
            onPressed: _saveExpense,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            child: const Text("Save"),
          ),
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
  double _originalTotalAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.initialTitle;
    _taxPercentController.text =
        widget.initialTaxPercent == 0.0 ? '' : widget.initialTaxPercent.toString();
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
      
      _originalTotalAmount += amountWithCharges;
      
      final index = _debts.length;
      _debts.add(DebtEntry(
        friendName: friendName,
        amount: baseAmount.toStringAsFixed(2),
        description: description,
        paid: paid,
      ));
      
      _amountControllers[index] =
          TextEditingController(text: baseAmount.toStringAsFixed(2));
      _descriptionControllers[index] =
          TextEditingController(text: description);
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
          newAmountControllers[i] = TextEditingController(text: _debts[i].amount);
        }
        if (_descriptionControllers.containsKey(i + 1)) {
          newDescriptionControllers[i] = _descriptionControllers[i + 1]!;
        } else {
          newDescriptionControllers[i] = TextEditingController(text: _debts[i].description);
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
        const SnackBar(content: Text("Please add at least one friend who owes you.")),
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
      final description = _descriptionControllers[i]?.text.trim() ?? debt.description;
      
      if (debt.friendName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select a friend for all entries.")),
        );
        return;
      }

      if (amountText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Please enter an amount for ${debt.friendName}.")),
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
      final groupRef = FirebaseFirestore.instance.collection('groups').doc(widget.groupId);
      final expenseRef = groupRef.collection('expenses').doc(widget.expenseId);

      // Update expense
      await expenseRef.update({
        'title': title,
        'debts': debtsData,
        'totalAmount': totalAmount,
        'taxPercent': taxPercent,
        'servicePercent': servicePercent,
        'taxAmount': taxAmount,
        'serviceAmount': serviceAmount,
        'totalWithCharges': totalWithCharges,
      });

      // Update total owed (adjust for difference)
      final difference = totalWithCharges - _originalTotalAmount;
      if (difference != 0) {
        await groupRef.update({
          'totalOwed': FieldValue.increment(difference),
        });
      }

      // Add any new friends to the friends list
      if (friendsToAdd.isNotEmpty) {
        await groupRef.update({
          'friends': FieldValue.arrayUnion(friendsToAdd.toList()),
        });
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.friends.isEmpty) {
      return AlertDialog(
        title: const Text("Edit Expense"),
        content: const Text("Please add at least one friend first in the Manage Friends section."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text("Edit Expense"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: "Expense Description",
                hintText: "e.g. Dinner, Movie tickets",
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Who Owes You?",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                TextButton.icon(
                  onPressed: _addDebtEntry,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("Add Friend"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_debts.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    "Tap 'Add Friend' to add someone who owes you",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ...List.generate(_debts.length, (index) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _debts[index].friendName.isEmpty
                                    ? null
                                    : _debts[index].friendName,
                                decoration: const InputDecoration(
                                  labelText: "Friend",
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                ),
                                items: widget.friends.map<DropdownMenuItem<String>>((dynamic value) {
                return DropdownMenuItem<String>(
                  value: value.toString(),
                  child: Text(value.toString()),
                );
              }).toList(),
              onChanged: (String? newValue) {
                                  setState(() {
                                    _debts[index].friendName = newValue ?? '';
                                  });
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _removeDebtEntry(index),
                              tooltip: "Remove",
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _amountControllers[index] ??= TextEditingController(text: _debts[index].amount),
                          decoration: const InputDecoration(
                            labelText: "Base amount (before tax/service)",
                            prefixText: "RM ",
                            hintText: "0.00",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (value) {
                            _debts[index].amount = value;
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _descriptionControllers[index] ??= TextEditingController(text: _debts[index].description),
                          decoration: const InputDecoration(
                            labelText: "Description (optional)",
                            hintText: "e.g. Their share of dinner",
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
                            child: Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.green, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  "This debt is marked as paid",
                                  style: TextStyle(color: Colors.green.shade700, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        if (_isLoading)
          const CircularProgressIndicator()
        else
          ElevatedButton(
            onPressed: _updateExpense,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            child: const Text("Update"),
          ),
      ],
    );
  }
}
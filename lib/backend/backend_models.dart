class GroupRecord {
  final String id;
  final String name;
  final double totalOwed;
  final DateTime createdAt;

  const GroupRecord({
    required this.id,
    required this.name,
    required this.totalOwed,
    required this.createdAt,
  });

  factory GroupRecord.fromSupabase(Map<String, dynamic> json) {
    return GroupRecord(
      id: json['id'] as String,
      name: json['name'] as String,
      totalOwed: (json['total_owed'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class GroupFriendRecord {
  final String id;
  final String groupId;
  final String name;

  const GroupFriendRecord({
    required this.id,
    required this.groupId,
    required this.name,
  });

  factory GroupFriendRecord.fromSupabase(Map<String, dynamic> json) {
    return GroupFriendRecord(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      name: json['name'] as String,
    );
  }
}

class ExpenseRecord {
  final String id;
  final String groupId;
  final String title;
  final double baseTotal;
  final double taxPercent;
  final double servicePercent;
  final double taxAmount;
  final double serviceAmount;
  final double totalWithCharges;
  final DateTime expenseDate;

  const ExpenseRecord({
    required this.id,
    required this.groupId,
    required this.title,
    required this.baseTotal,
    required this.taxPercent,
    required this.servicePercent,
    required this.taxAmount,
    required this.serviceAmount,
    required this.totalWithCharges,
    required this.expenseDate,
  });

  factory ExpenseRecord.fromSupabase(Map<String, dynamic> json) {
    return ExpenseRecord(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      title: json['title'] as String,
      baseTotal: (json['base_total'] as num?)?.toDouble() ?? 0,
      taxPercent: (json['tax_percent'] as num?)?.toDouble() ?? 0,
      servicePercent: (json['service_percent'] as num?)?.toDouble() ?? 0,
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0,
      serviceAmount: (json['service_amount'] as num?)?.toDouble() ?? 0,
      totalWithCharges: (json['total_with_charges'] as num?)?.toDouble() ?? 0,
      expenseDate: DateTime.parse(json['expense_date'] as String),
    );
  }
}

class ExpenseShareRecord {
  final String id;
  final String expenseId;
  final String? friendId;
  final String friendName;
  final String description;
  final double baseAmount;
  final double taxAmount;
  final double serviceAmount;
  final double amount;
  final bool paid;
  final DateTime? paidAt;

  const ExpenseShareRecord({
    required this.id,
    required this.expenseId,
    required this.friendId,
    required this.friendName,
    required this.description,
    required this.baseAmount,
    required this.taxAmount,
    required this.serviceAmount,
    required this.amount,
    required this.paid,
    required this.paidAt,
  });

  factory ExpenseShareRecord.fromSupabase(Map<String, dynamic> json) {
    final paidAt = json['paid_at'] as String?;
    return ExpenseShareRecord(
      id: json['id'] as String,
      expenseId: json['expense_id'] as String,
      friendId: json['friend_id'] as String?,
      friendName: json['friend_name'] as String,
      description: json['description'] as String? ?? '',
      baseAmount: (json['base_amount'] as num).toDouble(),
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0,
      serviceAmount: (json['service_amount'] as num?)?.toDouble() ?? 0,
      amount: (json['amount'] as num).toDouble(),
      paid: json['paid'] as bool? ?? false,
      paidAt: paidAt == null ? null : DateTime.parse(paidAt),
    );
  }
}

class ExpenseShareDraft {
  final String? shareId;
  final String? friendId;
  final String friendName;
  final String description;
  final double baseAmount;

  const ExpenseShareDraft({
    this.shareId,
    this.friendId,
    required this.friendName,
    this.description = '',
    required this.baseAmount,
  });

  Map<String, dynamic> toRpcJson() => {
    if (shareId != null) 'share_id': shareId,
    if (friendId != null) 'friend_id': friendId,
    'friend_name': friendName.trim(),
    'description': description.trim(),
    'base_amount': baseAmount,
  };
}

class ExpenseDraft {
  final String title;
  final double taxPercent;
  final double servicePercent;
  final DateTime? expenseDate;
  final List<ExpenseShareDraft> shares;

  const ExpenseDraft({
    required this.title,
    this.taxPercent = 0,
    this.servicePercent = 0,
    this.expenseDate,
    required this.shares,
  });
}

class ProfileRecord {
  final String id;
  final String displayName;
  final String? photoPath;

  const ProfileRecord({
    required this.id,
    required this.displayName,
    required this.photoPath,
  });

  factory ProfileRecord.fromSupabase(Map<String, dynamic> json) {
    return ProfileRecord(
      id: json['id'] as String,
      displayName: json['display_name'] as String? ?? '',
      photoPath: json['photo_path'] as String?,
    );
  }
}

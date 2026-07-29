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
  final String merchant;
  final String notes;
  final String? categoryId;
  final String categoryName;
  final double? receiptTotal;
  final ExpenseLocation? location;
  final int attachmentCount;

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
    this.merchant = '',
    this.notes = '',
    this.categoryId,
    this.categoryName = 'Other',
    this.receiptTotal,
    this.location,
    this.attachmentCount = 0,
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
      merchant: json['merchant'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      categoryId: json['category_id'] as String?,
      categoryName:
          json['category_name'] as String? ??
          (json['expense_categories'] as Map<String, dynamic>?)?['name']
              as String? ??
          'Other',
      receiptTotal: (json['receipt_total'] as num?)?.toDouble(),
      location: ExpenseLocation.fromExpenseJson(json),
      attachmentCount: (json['attachment_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ExpenseCategoryRecord {
  final String id;
  final String name;
  final String iconName;
  final bool isPreset;
  final bool isActive;

  const ExpenseCategoryRecord({
    required this.id,
    required this.name,
    required this.iconName,
    required this.isPreset,
    required this.isActive,
  });

  factory ExpenseCategoryRecord.fromSupabase(Map<String, dynamic> json) {
    return ExpenseCategoryRecord(
      id: json['id'] as String,
      name: json['name'] as String,
      iconName: json['icon_name'] as String? ?? 'category',
      isPreset: json['owner_id'] == null,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

List<ExpenseCategoryRecord> orderExpenseCategoriesByUsage(
  Iterable<ExpenseCategoryRecord> categories,
  Iterable<String?> usedCategoryIds, {
  int frequentLimit = 3,
}) {
  final categoriesById = <String, ExpenseCategoryRecord>{
    for (final category in categories) category.id: category,
  };
  final usageCounts = <String, int>{};
  for (final categoryId in usedCategoryIds) {
    if (categoryId == null || !categoriesById.containsKey(categoryId)) {
      continue;
    }
    usageCounts.update(categoryId, (count) => count + 1, ifAbsent: () => 1);
  }

  int compareAlphabetically(ExpenseCategoryRecord a, ExpenseCategoryRecord b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  final usedCategories =
      categoriesById.values
          .where((category) => (usageCounts[category.id] ?? 0) > 0)
          .toList()
        ..sort((a, b) {
          final countComparison = (usageCounts[b.id] ?? 0).compareTo(
            usageCounts[a.id] ?? 0,
          );
          return countComparison != 0
              ? countComparison
              : compareAlphabetically(a, b);
        });

  final frequentCategories = frequentLimit <= 0
      ? const <ExpenseCategoryRecord>[]
      : usedCategories.take(frequentLimit).toList();
  final frequentIds = frequentCategories.map((category) => category.id).toSet();
  final remainingCategories =
      categoriesById.values
          .where((category) => !frequentIds.contains(category.id))
          .toList()
        ..sort(compareAlphabetically);

  return [...frequentCategories, ...remainingCategories];
}

class ExpenseLocation {
  final String label;
  final String address;
  final double latitude;
  final double longitude;
  final String? osmType;
  final String? osmId;

  const ExpenseLocation({
    required this.label,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.osmType,
    this.osmId,
  });

  static ExpenseLocation? fromExpenseJson(Map<String, dynamic> json) {
    final latitude = (json['latitude'] as num?)?.toDouble();
    final longitude = (json['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return null;
    return ExpenseLocation(
      label: json['location_label'] as String? ?? '',
      address: json['location_address'] as String? ?? '',
      latitude: latitude,
      longitude: longitude,
      osmType: json['osm_type'] as String?,
      osmId: json['osm_id']?.toString(),
    );
  }

  Map<String, dynamic> toRpcJson() => {
    'label': label.trim(),
    'address': address.trim(),
    'latitude': latitude,
    'longitude': longitude,
    if (osmType != null) 'osm_type': osmType,
    if (osmId != null) 'osm_id': osmId,
  };
}

class ReceiptItem {
  final String description;
  final double? amount;

  const ReceiptItem({required this.description, this.amount});

  Map<String, dynamic> toJson() => {
    'description': description.trim(),
    if (amount != null) 'amount': amount,
  };

  factory ReceiptItem.fromJson(Map<String, dynamic> json) => ReceiptItem(
    description: json['description'] as String? ?? '',
    amount: (json['amount'] as num?)?.toDouble(),
  );
}

class ReceiptExtraction {
  final String rawText;
  final String merchant;
  final double? total;
  final DateTime? date;
  final List<ReceiptItem> items;
  final String script;

  const ReceiptExtraction({
    required this.rawText,
    this.merchant = '',
    this.total,
    this.date,
    this.items = const [],
    this.script = 'latin',
  });

  Map<String, dynamic> toJson() => {
    'merchant': merchant.trim(),
    if (total != null) 'total': total,
    if (date != null) 'date': date!.toIso8601String(),
    'items': items.map((item) => item.toJson()).toList(),
    'script': script,
  };

  factory ReceiptExtraction.fromJson(
    String rawText,
    Map<String, dynamic> json,
  ) {
    final date = json['date'] as String?;
    return ReceiptExtraction(
      rawText: rawText,
      merchant: json['merchant'] as String? ?? '',
      total: (json['total'] as num?)?.toDouble(),
      date: date == null ? null : DateTime.tryParse(date),
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ReceiptItem.fromJson)
          .toList(),
      script: json['script'] as String? ?? 'latin',
    );
  }
}

class ExpenseAttachmentRecord {
  final String id;
  final String expenseId;
  final String storagePath;
  final String originalFilename;
  final String mimeType;
  final int sizeBytes;
  final int sortOrder;
  final String ocrStatus;
  final ReceiptExtraction? extraction;

  const ExpenseAttachmentRecord({
    required this.id,
    required this.expenseId,
    required this.storagePath,
    required this.originalFilename,
    required this.mimeType,
    required this.sizeBytes,
    required this.sortOrder,
    required this.ocrStatus,
    this.extraction,
  });

  factory ExpenseAttachmentRecord.fromSupabase(Map<String, dynamic> json) {
    final extracted = json['extracted_data'];
    return ExpenseAttachmentRecord(
      id: json['id'] as String,
      expenseId: json['expense_id'] as String,
      storagePath: json['storage_path'] as String,
      originalFilename: json['original_filename'] as String? ?? 'proof',
      mimeType: json['mime_type'] as String,
      sizeBytes: (json['size_bytes'] as num).toInt(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      ocrStatus: json['ocr_status'] as String? ?? 'not_scanned',
      extraction: extracted is Map<String, dynamic>
          ? ReceiptExtraction.fromJson(
              json['ocr_text'] as String? ?? '',
              extracted,
            )
          : null,
    );
  }
}

class ExpenseAttachmentDraft {
  final String id;
  final String storagePath;
  final String originalFilename;
  final String mimeType;
  final int sizeBytes;
  final int sortOrder;
  final ReceiptExtraction? extraction;

  const ExpenseAttachmentDraft({
    required this.id,
    required this.storagePath,
    required this.originalFilename,
    required this.mimeType,
    required this.sizeBytes,
    required this.sortOrder,
    this.extraction,
  });

  Map<String, dynamic> toRpcJson() => {
    'id': id,
    'storage_path': storagePath,
    'original_filename': originalFilename,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'sort_order': sortOrder,
    'ocr_status': extraction == null ? 'not_scanned' : 'reviewed',
    'ocr_text': extraction?.rawText ?? '',
    'extracted_data': extraction?.toJson() ?? <String, dynamic>{},
  };
}

class ExpenseQuery {
  final String text;
  final String? categoryId;
  final String merchant;
  final String location;
  final DateTime? fromDate;
  final DateTime? toDate;
  final bool? hasProof;
  final int limit;
  final int offset;

  const ExpenseQuery({
    this.text = '',
    this.categoryId,
    this.merchant = '',
    this.location = '',
    this.fromDate,
    this.toDate,
    this.hasProof,
    this.limit = 100,
    this.offset = 0,
  });

  bool matches(
    ExpenseRecord expense, {
    List<ExpenseShareRecord> shares = const [],
    List<ExpenseAttachmentRecord> attachments = const [],
  }) {
    if (categoryId != null && expense.categoryId != categoryId) return false;
    if (fromDate != null && expense.expenseDate.isBefore(fromDate!)) {
      return false;
    }
    if (toDate != null && expense.expenseDate.isAfter(toDate!)) return false;
    if (hasProof != null &&
        (attachments.isNotEmpty || expense.attachmentCount > 0) != hasProof) {
      return false;
    }
    if (merchant.isNotEmpty &&
        !expense.merchant.toLowerCase().contains(merchant.toLowerCase())) {
      return false;
    }
    final place =
        '${expense.location?.label ?? ''} '
                '${expense.location?.address ?? ''}'
            .toLowerCase();
    if (location.isNotEmpty && !place.contains(location.toLowerCase().trim())) {
      return false;
    }
    final needle = text.toLowerCase().trim();
    if (needle.isEmpty) return true;
    final haystack = [
      expense.title,
      expense.merchant,
      expense.notes,
      expense.categoryName,
      place,
      ...shares.map((share) => '${share.friendName} ${share.description}'),
      ...attachments.map(
        (attachment) =>
            '${attachment.extraction?.rawText ?? ''} '
            '${attachment.extraction?.items.map((item) => item.description).join(' ') ?? ''}',
      ),
    ].join(' ').toLowerCase();
    return haystack.contains(needle);
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
  final String? id;
  final String title;
  final String merchant;
  final String notes;
  final String? categoryId;
  final double? receiptTotal;
  final ExpenseLocation? location;
  final List<ExpenseAttachmentDraft> attachments;
  final double taxPercent;
  final double servicePercent;
  final DateTime? expenseDate;
  final List<ExpenseShareDraft> shares;

  const ExpenseDraft({
    this.id,
    required this.title,
    this.merchant = '',
    this.notes = '',
    this.categoryId,
    this.receiptTotal,
    this.location,
    this.attachments = const [],
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

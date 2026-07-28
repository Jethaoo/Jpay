import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend_models.dart';
import 'jpay_repository.dart';

class SupabaseJpayRepository implements JpayRepository {
  final SupabaseClient _client;

  SupabaseJpayRepository(this._client);

  String get _userId {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('A Supabase user session is required.');
    }
    return user.id;
  }

  @override
  Stream<List<GroupRecord>> watchGroups() {
    return _client
        .from('groups')
        .stream(primaryKey: ['id'])
        .eq('owner_id', _userId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(GroupRecord.fromSupabase).toList());
  }

  @override
  Stream<List<GroupFriendRecord>> watchFriends(String groupId) {
    return _client
        .from('group_friends')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .order('name')
        .map((rows) => rows.map(GroupFriendRecord.fromSupabase).toList());
  }

  @override
  Stream<List<ExpenseRecord>> watchExpenses(String groupId) {
    return _client
        .from('expenses')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .order('expense_date', ascending: false)
        .map((rows) => rows.map(ExpenseRecord.fromSupabase).toList());
  }

  @override
  Stream<List<ExpenseShareRecord>> watchExpenseShares(String expenseId) {
    return _client
        .from('expense_shares')
        .stream(primaryKey: ['id'])
        .eq('expense_id', expenseId)
        .order('source_index')
        .map((rows) => rows.map(ExpenseShareRecord.fromSupabase).toList());
  }

  @override
  Stream<List<ExpenseShareRecord>> watchAllExpenseShares() {
    return _client
        .from('expense_shares')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(ExpenseShareRecord.fromSupabase).toList());
  }

  @override
  Future<String> createGroup(String name) async {
    final row = await _client
        .from('groups')
        .insert({'owner_id': _userId, 'name': name.trim()})
        .select('id')
        .single();
    return row['id'] as String;
  }

  @override
  Future<void> renameGroup(String groupId, String name) async {
    await _client
        .from('groups')
        .update({'name': name.trim()})
        .eq('id', groupId);
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    await _client.from('groups').delete().eq('id', groupId);
  }

  @override
  Future<GroupFriendRecord> addFriend(String groupId, String name) async {
    final row = await _client
        .from('group_friends')
        .insert({'group_id': groupId, 'name': name.trim()})
        .select()
        .single();
    return GroupFriendRecord.fromSupabase(row);
  }

  @override
  Future<void> removeFriend(String friendId) async {
    await _client.from('group_friends').delete().eq('id', friendId);
  }

  @override
  Future<String> createExpense(String groupId, ExpenseDraft expense) async {
    final result = await _client.rpc(
      'create_expense_with_shares',
      params: {
        'p_group_id': groupId,
        'p_title': expense.title.trim(),
        'p_tax_percent': expense.taxPercent,
        'p_service_percent': expense.servicePercent,
        'p_shares': expense.shares.map((share) => share.toRpcJson()).toList(),
        'p_expense_date': expense.expenseDate?.toIso8601String(),
      },
    );
    return result as String;
  }

  @override
  Future<void> updateExpense(String expenseId, ExpenseDraft expense) async {
    await _client.rpc(
      'update_expense_with_shares',
      params: {
        'p_expense_id': expenseId,
        'p_title': expense.title.trim(),
        'p_tax_percent': expense.taxPercent,
        'p_service_percent': expense.servicePercent,
        'p_shares': expense.shares.map((share) => share.toRpcJson()).toList(),
      },
    );
  }

  @override
  Future<bool> markExpenseSharePaid(String shareId) async {
    final result = await _client.rpc(
      'mark_expense_share_paid',
      params: {'p_share_id': shareId},
    );
    return result as bool;
  }

  @override
  Future<double> markFriendSharesPaid(String groupId, String friendName) async {
    final result = await _client.rpc(
      'mark_friend_shares_paid',
      params: {'p_group_id': groupId, 'p_friend_name': friendName.trim()},
    );
    return (result as num).toDouble();
  }

  @override
  Future<bool> deleteExpense(String expenseId) async {
    final result = await _client.rpc(
      'delete_expense',
      params: {'p_expense_id': expenseId},
    );
    return result as bool;
  }

  @override
  Future<ProfileRecord> getProfile() async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', _userId)
        .single();
    return ProfileRecord.fromSupabase(row);
  }

  @override
  Future<void> updateProfile({
    required String displayName,
    String? photoPath,
  }) async {
    await _client
        .from('profiles')
        .update({
          'display_name': displayName.trim(),
          if (photoPath != null) 'photo_path': photoPath,
        })
        .eq('id', _userId);
  }

  @override
  Future<String> uploadProfilePicture(Uint8List bytes) async {
    final path = '$_userId/avatar.jpg';
    await _client.storage
        .from('profile-pictures')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return path;
  }

  @override
  Future<String?> createProfilePictureUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    final signedUrl = await _client.storage
        .from('profile-pictures')
        .createSignedUrl(path, 3600);
    final separator = signedUrl.contains('?') ? '&' : '?';
    return '$signedUrl${separator}v=${DateTime.now().millisecondsSinceEpoch}';
  }
}

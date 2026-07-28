import 'dart:typed_data';

import 'backend_models.dart';

abstract interface class JpayRepository {
  Stream<List<GroupRecord>> watchGroups();

  Stream<List<GroupFriendRecord>> watchFriends(String groupId);

  Stream<List<ExpenseRecord>> watchExpenses(String groupId);

  Stream<List<ExpenseShareRecord>> watchExpenseShares(String expenseId);

  Stream<List<ExpenseShareRecord>> watchAllExpenseShares();

  Future<String> createGroup(String name);

  Future<void> renameGroup(String groupId, String name);

  Future<void> deleteGroup(String groupId);

  Future<GroupFriendRecord> addFriend(String groupId, String name);

  Future<void> removeFriend(String friendId);

  Future<String> createExpense(String groupId, ExpenseDraft expense);

  Future<void> updateExpense(String expenseId, ExpenseDraft expense);

  Future<bool> markExpenseSharePaid(String shareId);

  Future<double> markFriendSharesPaid(String groupId, String friendName);

  Future<bool> deleteExpense(String expenseId);

  Future<ProfileRecord> getProfile();

  Future<void> updateProfile({required String displayName, String? photoPath});

  Future<String> uploadProfilePicture(Uint8List bytes);

  Future<String?> createProfilePictureUrl(String? path);
}

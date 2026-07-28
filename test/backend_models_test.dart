import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/backend/backend_models.dart';
import 'package:jpay/backend/backend_config.dart';

void main() {
  test('Supabase requires compile-time public project credentials', () {
    expect(BackendConfig.hasSupabaseCredentials, isFalse);
    expect(BackendConfig.isSupabaseReady, isFalse);
  });

  test('expense share draft produces the RPC payload', () {
    const draft = ExpenseShareDraft(
      shareId: 'share-id',
      friendId: 'friend-id',
      friendName: '  Alex  ',
      description: '  Dinner  ',
      baseAmount: 12.5,
    );

    expect(draft.toRpcJson(), {
      'share_id': 'share-id',
      'friend_id': 'friend-id',
      'friend_name': 'Alex',
      'description': 'Dinner',
      'base_amount': 12.5,
    });
  });

  test('Supabase group rows map to backend models', () {
    final group = GroupRecord.fromSupabase({
      'id': 'group-id',
      'name': 'Penang trip',
      'total_owed': 42.35,
      'created_at': '2026-07-28T08:00:00.000Z',
    });

    expect(group.id, 'group-id');
    expect(group.name, 'Penang trip');
    expect(group.totalOwed, 42.35);
    expect(group.createdAt.toUtc(), DateTime.utc(2026, 7, 28, 8));
  });

  test('enriched expense rows map proof and location metadata', () {
    final expense = ExpenseRecord.fromSupabase({
      'id': 'expense-id',
      'group_id': 'group-id',
      'title': 'Dinner',
      'merchant': 'Kopitiam',
      'notes': 'Team meal',
      'category_id': 'category-id',
      'category_name': 'Food & Dining',
      'receipt_total': 42.5,
      'latitude': 3.139,
      'longitude': 101.6869,
      'location_label': 'Central Market',
      'location_address': 'Kuala Lumpur',
      'attachment_count': 2,
      'expense_date': '2026-07-28T08:00:00.000Z',
    });

    expect(expense.merchant, 'Kopitiam');
    expect(expense.categoryName, 'Food & Dining');
    expect(expense.receiptTotal, 42.5);
    expect(expense.location?.label, 'Central Market');
    expect(expense.attachmentCount, 2);
  });

  test('expense query matches metadata and proof state', () {
    final expense = ExpenseRecord.fromSupabase({
      'id': 'expense-id',
      'group_id': 'group-id',
      'title': 'Groceries',
      'merchant': 'Village Grocer',
      'notes': 'Weekly shop',
      'category_id': 'groceries',
      'category_name': 'Groceries',
      'attachment_count': 1,
      'expense_date': '2026-07-28T08:00:00.000Z',
    });

    expect(
      const ExpenseQuery(text: 'village', hasProof: true).matches(expense),
      isTrue,
    );
    expect(
      const ExpenseQuery(categoryId: 'transport').matches(expense),
      isFalse,
    );
  });
}

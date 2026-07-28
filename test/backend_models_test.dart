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
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/app_theme.dart';
import 'package:jpay/backend/backend_models.dart';
import 'package:jpay/backend/jpay_repository.dart';
import 'package:jpay/supabase_home_screen.dart';

class _HomeRepository extends Fake implements JpayRepository {
  final deleteCompleter = Completer<void>();
  bool deleteRequested = false;

  @override
  Stream<List<GroupRecord>> watchGroups() => Stream.value([
    GroupRecord(
      id: 'group-1',
      name: 'Testing',
      totalOwed: 25,
      createdAt: DateTime(2026),
    ),
  ]);

  @override
  Stream<List<GroupFriendRecord>> watchFriends(String groupId) =>
      Stream.value(const []);

  @override
  Future<ProfileRecord> getProfile() async =>
      const ProfileRecord(id: 'user-1', displayName: 'Tester', photoPath: null);

  @override
  Future<String?> createProfilePictureUrl(String? path) async => null;

  @override
  Future<void> deleteGroup(String groupId) {
    deleteRequested = true;
    return deleteCompleter.future;
  }
}

void main() {
  testWidgets('hides a deleted group before Realtime confirms the change', (
    tester,
  ) async {
    final repository = _HomeRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SupabaseHomeScreen(
          repository: repository,
          userEmail: 'tester@example.com',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Testing'), findsOneWidget);

    await tester.tap(find.byTooltip('Group actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete group'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();

    expect(repository.deleteRequested, isTrue);
    expect(find.text('Testing'), findsNothing);

    repository.deleteCompleter.complete();
    await tester.pumpAndSettle();
    expect(find.text('Testing'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home remains usable on a narrow phone with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _HomeRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: SupabaseHomeScreen(
          repository: repository,
          userEmail: 'tester@example.com',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jpay'), findsOneWidget);
    expect(find.text('Outstanding to you'), findsOneWidget);
    expect(find.text('Testing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

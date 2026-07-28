import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/app_theme.dart';
import 'package:jpay/backend/backend_models.dart';
import 'package:jpay/backend/jpay_repository.dart';
import 'package:jpay/supabase_group_details_screen.dart';

class _ExpenseEditorRepository extends Fake implements JpayRepository {
  final categories = <ExpenseCategoryRecord>[
    ExpenseCategoryRecord(
      id: 'food',
      name: 'Food & Dining',
      iconName: 'restaurant',
      isPreset: true,
      isActive: true,
    ),
    ExpenseCategoryRecord(
      id: 'other',
      name: 'Other',
      iconName: 'category',
      isPreset: true,
      isActive: true,
    ),
  ];

  @override
  Stream<List<GroupRecord>> watchGroups() => Stream.value([
    GroupRecord(
      id: 'group-1',
      name: 'Weekend',
      totalOwed: 0,
      createdAt: DateTime(2026),
    ),
  ]);

  @override
  Stream<List<GroupFriendRecord>> watchFriends(String groupId) => Stream.value(
    const [GroupFriendRecord(id: 'friend-1', groupId: 'group-1', name: 'Alex')],
  );

  @override
  Stream<List<ExpenseRecord>> watchExpenses(String groupId) =>
      Stream.value(const []);

  @override
  Stream<List<ExpenseShareRecord>> watchAllExpenseShares() =>
      Stream.value(const []);

  @override
  Stream<List<ExpenseCategoryRecord>> watchExpenseCategories() =>
      Stream.value(List.unmodifiable(categories));

  @override
  Future<ExpenseCategoryRecord> createExpenseCategory(String name) async {
    return ExpenseCategoryRecord(
      id: 'custom-${categories.length}',
      name: name,
      iconName: 'category',
      isPreset: false,
      isActive: true,
    );
  }
}

Finder _textField(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  testWidgets(
    'editor survives keyboard dismissal, category overlay, and date route',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2670);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: SupabaseGroupDetailsScreen(
            groupId: 'group-1',
            initialName: 'Weekend',
            repository: _ExpenseEditorRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(_textField('What was it for?'), 'Dinner');
      await tester.enterText(_textField('Merchant (optional)'), 'Night Market');
      await tester.enterText(
        _textField('Expense notes (optional)'),
        'Shared meal',
      );

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Other').first);
      await tester.tap(find.text('Other').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food & Dining').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Create category'));
      await tester.pumpAndSettle();
      await tester.enterText(_textField('Category name'), 'Work');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsOneWidget);

      final dateButton = find.byIcon(Icons.calendar_today_outlined);
      await tester.ensureVisible(dateButton);
      await tester.tap(dateButton);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Add expense'), findsNWidgets(2));
    },
  );
}

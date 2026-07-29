import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/app_theme.dart';
import 'package:jpay/backend/backend_models.dart';
import 'package:jpay/backend/jpay_repository.dart';
import 'package:jpay/supabase_group_details_screen.dart';

class _ExpenseEditorRepository extends Fake implements JpayRepository {
  final List<ExpenseRecord> expenses;
  final List<ExpenseAttachmentRecord> attachments;

  _ExpenseEditorRepository({
    this.expenses = const [],
    this.attachments = const [],
  });

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
      Stream.value(expenses);

  @override
  Stream<List<ExpenseShareRecord>> watchAllExpenseShares() =>
      Stream.value(const []);

  @override
  Stream<List<ExpenseAttachmentRecord>> watchExpenseAttachments(
    String expenseId,
  ) => Stream.value(attachments);

  @override
  Future<String> createExpenseProofUrl(String path) async =>
      'https://example.invalid/$path';

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

Future<void> _openActiveEditor(
  WidgetTester tester, {
  Size size = const Size(360, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
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
}

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

      await tester.tap(find.text('1 friend'));
      await tester.pumpAndSettle();
      expect(find.text('Manage friends'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Done'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(_textField('What was it for?'), 'Dinner');
      expect(_textField('Merchant (optional)'), findsNothing);

      final categoryPicker = find.byKey(
        const ValueKey('expense-category-picker'),
      );
      await tester.ensureVisible(categoryPicker);
      await tester.tap(categoryPicker);
      await tester.pumpAndSettle();
      expect(find.text('Choose category'), findsOneWidget);
      expect(find.text('Search categories'), findsOneWidget);
      expect(find.text('Create new category'), findsOneWidget);
      await tester.tap(find.text('Food & Dining').last);
      await tester.pumpAndSettle();

      await tester.tap(categoryPicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create new category'));
      await tester.pumpAndSettle();
      await tester.enterText(_textField('Category name'), ' food & dining ');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pump();
      expect(
        find.text(
          'The category "Food & Dining" already exists. Choose it from '
          'the list.',
        ),
        findsOneWidget,
      );

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

      await tester.ensureVisible(find.text('Merchant & notes'));
      await tester.tap(find.text('Merchant & notes'));
      await tester.pumpAndSettle();
      await tester.enterText(_textField('Merchant (optional)'), 'Night Market');
      await tester.enterText(
        _textField('Expense notes (optional)'),
        'Shared meal',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final selectFriends = find.widgetWithText(FilledButton, 'Select');
      await tester.ensureVisible(selectFriends);
      await tester.tap(selectFriends);
      await tester.pumpAndSettle();
      expect(find.text('Select friends'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'Alex'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);
      await tester.tap(find.text('Select all'));
      await tester.pump();
      final alexTile = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Alex'),
      );
      expect(alexTile.value, isTrue);
      expect(find.text('Clear all'), findsOneWidget);
      expect(find.text('Use 1 friend'), findsOneWidget);
      await tester.tap(find.text('Use 1 friend'));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Showing the selected participant should not overflow.',
      );

      final splitEqually = find.text('Split equally');
      await tester.ensureVisible(splitEqually);
      await tester.tap(splitEqually);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Opening the split dialog should not overflow.',
      );
      await tester.enterText(_textField('Total to split (RM)'), '12');
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Entering a split total should not overflow.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Apply split'));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Applying the split should close without a lifecycle error.',
      );
      final amountField = tester.widget<TextField>(
        _textField('Amount owed (RM)'),
      );
      expect(amountField.controller?.text, '12.00');

      expect(tester.takeException(), isNull);
      expect(find.text('Add expense'), findsNWidgets(2));
    },
  );

  testWidgets('editor presents the fast path before optional sections', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await _openActiveEditor(tester);

    expect(find.text('Scan receipt'), findsOneWidget);
    expect(_textField('What was it for?'), findsOneWidget);
    expect(find.text('Who owes you?'), findsOneWidget);
    expect(find.text('Receipt & proof'), findsOneWidget);
    expect(_textField('Merchant (optional)'), findsNothing);
    expect(_textField('Tax'), findsNothing);
    expect(find.text('TOTAL OWED'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add expense'), findsOneWidget);

    final scanTop = tester.getTopLeft(find.text('Scan receipt')).dy;
    final titleTop = tester.getTopLeft(_textField('What was it for?')).dy;
    final participantsTop = tester.getTopLeft(find.text('Who owes you?')).dy;
    expect(scanTop, lessThan(titleTop));
    expect(titleTop, lessThan(participantsTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor validates inline and protects a dirty draft', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await _openActiveEditor(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
    await tester.pumpAndSettle();
    expect(find.text('Enter what the expense was for.'), findsOneWidget);

    await tester.enterText(_textField('What was it for?'), 'Dinner');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard this expense?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Add expense'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Expense history'), findsOneWidget);
  });

  testWidgets('group hides map controls when no expense has a location', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
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

    expect(find.byTooltip('Map view'), findsNothing);
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('No expenses yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved proofs open in a navigable viewer with clear metadata', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _ExpenseEditorRepository(
      expenses: [
        ExpenseRecord(
          id: 'expense-1',
          groupId: 'group-1',
          title: 'Dinner',
          baseTotal: 24,
          taxPercent: 0,
          servicePercent: 0,
          taxAmount: 0,
          serviceAmount: 0,
          totalWithCharges: 24,
          expenseDate: DateTime(2026, 7, 29),
          attachmentCount: 2,
        ),
      ],
      attachments: const [
        ExpenseAttachmentRecord(
          id: 'proof-1',
          expenseId: 'expense-1',
          storagePath: 'proof-1.jpg',
          originalFilename: 'receipt-front.jpg',
          mimeType: 'image/jpeg',
          sizeBytes: 125000,
          sortOrder: 0,
          ocrStatus: 'reviewed',
          extraction: ReceiptExtraction(
            rawText: 'Dinner total 24.00',
            merchant: 'Dinner',
            total: 24,
          ),
        ),
        ExpenseAttachmentRecord(
          id: 'proof-2',
          expenseId: 'expense-1',
          storagePath: 'proof-2.jpg',
          originalFilename: 'payment-confirmation.jpg',
          mimeType: 'image/jpeg',
          sizeBytes: 89000,
          sortOrder: 1,
          ocrStatus: 'not_scanned',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SupabaseGroupDetailsScreen(
          groupId: 'group-1',
          initialName: 'Weekend',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dinner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 proofs'));
    await tester.pumpAndSettle();

    expect(find.text('Proof 1 of 2'), findsOneWidget);
    expect(find.text('receipt-front.jpg'), findsOneWidget);
    expect(find.text('Scanned'), findsOneWidget);
    expect(find.textContaining('Pinch or double-tap to zoom'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('View proof 2 of 2'));
    await tester.pumpAndSettle();
    expect(find.text('Proof 2 of 2'), findsOneWidget);
    expect(find.text('payment-confirmation.jpg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

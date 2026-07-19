import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/app_theme.dart';
import 'package:jpay/group_details_screen.dart';

Future<void> _openDialog(
  WidgetTester tester,
  Widget Function() dialogBuilder,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => dialogBuilder(),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder _amountFields() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.labelText == 'Amount owed',
);

Finder _fieldWithLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _selectFriends(WidgetTester tester, List<String> friends) async {
  await tester.tap(find.text('Select'));
  await tester.pumpAndSettle();
  for (final friend in friends) {
    await tester.tap(find.widgetWithText(CheckboxListTile, friend));
  }
  await tester.pump();
  await tester.tap(
    find.text('Use ${friends.length} friend${friends.length == 1 ? '' : 's'}'),
  );
  await tester.pumpAndSettle();
}

Future<void> _openPreparedAddExpense(WidgetTester tester) async {
  await _openDialog(
    tester,
    () => const AddExpenseDialog(groupId: 'group-1', friends: ['Alex']),
  );
  await tester.enterText(_fieldWithLabel('What was it for?'), 'Dinner');
  await _selectFriends(tester, ['Alex']);
}

void main() {
  testWidgets(
    'selects participants once and starts with custom blank amounts',
    (tester) async {
      await _openDialog(
        tester,
        () => const AddExpenseDialog(
          groupId: 'group-1',
          friends: ['Alex', 'Blair', 'alex'],
        ),
      );

      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(CheckboxListTile, 'Alex'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'alex'), findsNothing);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Alex'));
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Blair'));
      await tester.pump();
      await tester.tap(find.text('Use 2 friends'));
      await tester.pumpAndSettle();

      expect(_amountFields(), findsNWidgets(2));
      final fields = tester.widgetList<TextField>(_amountFields()).toList();
      expect(fields.every((field) => field.controller!.text.isEmpty), isTrue);

      await tester.enterText(_amountFields().at(0), '12.50');
      await tester.enterText(_amountFields().at(1), '7.25');
      await tester.pump();
      expect(find.text('RM 19.75'), findsWidgets);
    },
  );

  testWidgets('equal split only fills amounts after explicit action', (
    tester,
  ) async {
    await _openDialog(
      tester,
      () => const AddExpenseDialog(
        groupId: 'group-1',
        friends: ['Alex', 'Blair', 'Casey'],
      ),
    );

    await _selectFriends(tester, ['Alex', 'Blair', 'Casey']);

    var fields = tester.widgetList<TextField>(_amountFields()).toList();
    expect(fields.every((field) => field.controller!.text.isEmpty), isTrue);

    await tester.tap(find.text('Split equally'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Total friends owe',
      ),
      '10',
    );
    await tester.tap(find.text('Apply split'));
    await tester.pumpAndSettle();

    fields = tester.widgetList<TextField>(_amountFields()).toList();
    expect(fields.map((field) => field.controller!.text), [
      '3.34',
      '3.33',
      '3.33',
    ]);
  });

  testWidgets('edit mode keeps the paid state for an existing participant', (
    tester,
  ) async {
    await _openDialog(
      tester,
      () => EditExpenseDialog(
        groupId: 'group-1',
        expenseId: 'expense-1',
        friends: const ['Alex', 'Blair'],
        initialTitle: 'Dinner',
        initialDebts: const [
          {
            'friendName': 'Alex',
            'baseAmount': 12.0,
            'amount': 12.0,
            'description': '',
            'paid': true,
          },
        ],
        initialTaxPercent: 0,
        initialServicePercent: 0,
      ),
    );

    expect(find.text('Paid'), findsOneWidget);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Blair'));
    await tester.pump();
    await tester.tap(find.text('Use 2 friends'));
    await tester.pumpAndSettle();

    expect(find.text('Paid'), findsOneWidget);
    expect(_amountFields(), findsNWidgets(2));
  });

  testWidgets('rejects a blank participant amount', (tester) async {
    await _openPreparedAddExpense(tester);
    await tester.tap(find.text('Save expense'));
    await tester.pump();
    expect(find.text('Please enter an amount for Alex.'), findsOneWidget);
  });

  testWidgets('rejects a zero participant amount', (tester) async {
    await _openPreparedAddExpense(tester);
    await tester.enterText(_amountFields(), '0');
    await tester.tap(find.text('Save expense'));
    await tester.pump();
    expect(find.text('Amount must be greater than 0.'), findsOneWidget);
  });

  testWidgets('rejects a non-finite participant amount', (tester) async {
    await _openPreparedAddExpense(tester);
    await tester.enterText(_amountFields(), 'NaN');
    await tester.tap(find.text('Save expense'));
    await tester.pump();
    expect(find.text('Amount must be greater than 0.'), findsOneWidget);
  });

  testWidgets('confirms before discarding a participant draft', (tester) async {
    await _openDialog(
      tester,
      () => const AddExpenseDialog(groupId: 'group-1', friends: ['Alex']),
    );

    await _selectFriends(tester, ['Alex']);
    await tester.enterText(_amountFields(), '8.50');
    await tester.tap(find.byTooltip('Remove Alex'));
    await tester.pumpAndSettle();

    expect(find.text('Remove selected friend?'), findsOneWidget);
    await tester.tap(find.text('Keep friend'));
    await tester.pumpAndSettle();
    expect(_amountFields(), findsOneWidget);

    await tester.tap(find.byTooltip('Remove Alex'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(_amountFields(), findsNothing);
  });

  testWidgets('shows no-friends shortcut for blank friend data', (
    tester,
  ) async {
    await _openDialog(
      tester,
      () => const AddExpenseDialog(groupId: 'group-1', friends: [' ', '']),
    );

    expect(find.text('Add a friend first'), findsOneWidget);
    expect(find.text('Manage friends'), findsOneWidget);
  });

  testWidgets('charges are collapsed for add and expanded for charged edits', (
    tester,
  ) async {
    await _openDialog(
      tester,
      () => const AddExpenseDialog(groupId: 'group-1', friends: ['Alex']),
    );

    expect(_fieldWithLabel('Tax'), findsNothing);
    await tester.tap(find.text('Additional charges'));
    await tester.pumpAndSettle();
    expect(_fieldWithLabel('Tax'), findsOneWidget);
  });

  testWidgets('edit auto-expands existing tax and service charges', (
    tester,
  ) async {
    await _openDialog(
      tester,
      () => EditExpenseDialog(
        groupId: 'group-1',
        expenseId: 'expense-1',
        friends: const ['Alex'],
        initialTitle: 'Dinner',
        initialDebts: const [
          {
            'friendName': 'Alex',
            'baseAmount': 10.0,
            'amount': 11.6,
            'description': '',
            'paid': false,
          },
        ],
        initialTaxPercent: 10,
        initialServicePercent: 6,
      ),
    );

    expect(_fieldWithLabel('Tax'), findsOneWidget);
    expect(_fieldWithLabel('Service'), findsOneWidget);
  });
}

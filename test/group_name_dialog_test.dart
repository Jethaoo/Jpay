import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/app_theme.dart';
import 'package:jpay/widgets/group_name_dialog.dart';

void main() {
  testWidgets('submits a new group while the keyboard is active', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const GroupNameDialog(
                    title: 'New group',
                    actionLabel: 'Create',
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    expect(find.text('Enter a group name.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  Road trip  ');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(result, 'Road trip');
    expect(tester.takeException(), isNull);
  });
}

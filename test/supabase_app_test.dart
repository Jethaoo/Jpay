import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/app_theme.dart';
import 'package:jpay/supabase_app.dart';

void main() {
  testWidgets(
    'active login screen requests the migrated Supabase credentials',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const SupabaseLoginScreen()),
      );

      expect(find.text('Jpay'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Log In'), findsOneWidget);
      expect(find.text('Create new Account'), findsNothing);
    },
  );
}

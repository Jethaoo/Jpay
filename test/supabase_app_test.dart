import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpay/app_theme.dart';
import 'package:jpay/services/jpay_auth_service.dart';
import 'package:jpay/supabase_app.dart';

class _FakeAuthService implements JpayAuthService {
  final controller = StreamController<JpayAuthState>.broadcast();
  bool activeSession = false;
  String? signedInEmail;
  String? resetEmail;
  String? resetRedirect;
  String? updatedPassword;
  bool signedOut = false;

  @override
  bool get hasActiveSession => activeSession;

  @override
  Stream<JpayAuthState> get onAuthStateChange => controller.stream;

  @override
  Future<void> sendPasswordReset({
    required String email,
    required String redirectTo,
  }) async {
    resetEmail = email;
    resetRedirect = redirectTo;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    signedInEmail = email;
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
    activeSession = false;
    controller.add(
      const JpayAuthState(event: JpayAuthEvent.signedOut, hasSession: false),
    );
  }

  @override
  Future<void> updatePassword(String password) async {
    updatedPassword = password;
  }

  Future<void> dispose() => controller.close();
}

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
      expect(find.text('Forgot password?'), findsNothing);
    },
  );

  testWidgets('feature-gated recovery sends a generic confirmation', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SupabaseLoginScreen(
          authService: auth,
          passwordRecoveryEnabled: true,
        ),
      ),
    );

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Email').last,
      'person@example.com',
    );
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(auth.resetEmail, 'person@example.com');
    expect(auth.resetRedirect, 'com.example.jpay://reset-callback/');
    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.textContaining('If an account exists for that address'),
      findsOneWidget,
    );
  });

  testWidgets('recovery auth event opens the new-password screen', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SupabaseAuthGate(authService: auth),
      ),
    );
    expect(find.text('Log In'), findsOneWidget);

    auth.activeSession = true;
    auth.controller.add(
      const JpayAuthState(
        event: JpayAuthEvent.passwordRecovery,
        hasSession: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose a new password'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'New password'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Confirm password'), findsOneWidget);
  });

  testWidgets('new-password screen validates and updates the password', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    addTearDown(auth.dispose);
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SupabaseUpdatePasswordScreen(
          authService: auth,
          onComplete: () => completed = true,
          onCancel: auth.signOut,
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'New password'),
      'new-password',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'different',
    );
    await tester.tap(find.text('Update password'));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'new-password',
    );
    await tester.tap(find.text('Update password'));
    await tester.pump();

    expect(auth.updatedPassword, 'new-password');
    expect(completed, isTrue);
  });
}

import 'package:supabase_flutter/supabase_flutter.dart';

enum JpayAuthEvent { sessionChanged, passwordRecovery, signedOut }

class JpayAuthState {
  final JpayAuthEvent event;
  final bool hasSession;

  const JpayAuthState({required this.event, required this.hasSession});
}

abstract interface class JpayAuthService {
  Stream<JpayAuthState> get onAuthStateChange;

  bool get hasActiveSession;

  Future<void> signIn({required String email, required String password});

  Future<void> sendPasswordReset({
    required String email,
    required String redirectTo,
  });

  Future<void> updatePassword(String password);

  Future<void> signOut();
}

class SupabaseJpayAuthService implements JpayAuthService {
  final SupabaseClient _client;

  const SupabaseJpayAuthService(this._client);

  @override
  Stream<JpayAuthState> get onAuthStateChange =>
      _client.auth.onAuthStateChange.map((state) {
        final event = state.event == AuthChangeEvent.passwordRecovery
            ? JpayAuthEvent.passwordRecovery
            : state.event == AuthChangeEvent.signedOut
            ? JpayAuthEvent.signedOut
            : JpayAuthEvent.sessionChanged;
        return JpayAuthState(event: event, hasSession: state.session != null);
      });

  @override
  bool get hasActiveSession => _client.auth.currentSession != null;

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> sendPasswordReset({
    required String email,
    required String redirectTo,
  }) async {
    await _client.auth.resetPasswordForEmail(email, redirectTo: redirectTo);
  }

  @override
  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}

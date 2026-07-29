import 'package:supabase_flutter/supabase_flutter.dart';

/// Compile-time configuration for the Supabase backend.
///
/// Supply the public project values at build or run time with:
///
/// --dart-define=SUPABASE_URL=https://PROJECT.supabase.co
/// --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
abstract final class BackendConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get hasSupabaseCredentials =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;

  static bool get isSupabaseReady => hasSupabaseCredentials;

  static Future<void> initializeSupabase() async {
    if (!hasSupabaseCredentials) {
      throw StateError(
        'Jpay requires SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.',
      );
    }

    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  }
}

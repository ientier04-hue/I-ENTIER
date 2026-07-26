import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static bool isInitialized = false;

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://dktjnxbtyhxvapyheosh.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_8dJgVAcokPBAdjY7pymzLA_OI6l7lOp',
  );
  static const oauthRedirectUrl = String.fromEnvironment(
    'SUPABASE_REDIRECT_URL',
    defaultValue: 'com.ientier.i_entier://login-callback',
  );

  static Future<void> initialize() async {
    await Supabase.initialize(url: url, publishableKey: publishableKey);
    isInitialized = true;
  }

  static SupabaseClient get client => Supabase.instance.client;
}

extension IEntierSupabaseUser on User {
  String get uid => id;

  String? get displayName {
    final metadata = userMetadata;
    return (metadata?['full_name'] ?? metadata?['name'])?.toString();
  }

  String? get photoURL {
    final metadata = userMetadata;
    return (metadata?['avatar_url'] ?? metadata?['picture'])?.toString();
  }
}

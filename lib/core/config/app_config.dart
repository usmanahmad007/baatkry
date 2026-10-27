import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration settings for Supabase and LiveKit.
/// Secrets (API keys, URLs, and Secrets) are loaded from the `.env` file at runtime
/// with fallback support for `--dart-define` compilation flags.
class AppConfig {
  AppConfig._();

  /// Initialize and load the `.env` asset file. Call this before [runApp] in `main()`.
  static Future<void> init() async {
    try {
      await dotenv.load(fileName: '.env', isOptional: true);
    } catch (e) {
      debugPrint('[AppConfig] Note: .env could not be loaded from assets: $e');
    }
  }

  /// Initialize with a custom in-memory environment string or map for testing.
  static void initForTesting({
    String? envString,
    Map<String, String>? mergeWith,
  }) {
    dotenv.loadFromString(
      envString: envString ?? '',
      mergeWith: mergeWith ?? const {},
      isOptional: true,
    );
  }

  /// Helper to safely retrieve an environment variable from `.env` or `--dart-define`
  static String _getEnv(String key, {String fallback = ''}) {
    if (dotenv.isInitialized) {
      final val = dotenv.maybeGet(key);
      if (val != null && val.trim().isNotEmpty) {
        return val.trim();
      }
    }

    // Fallback to compile-time --dart-define flags
    const dartDefines = {
      'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL'),
      'SUPABASE_ANON_KEY': String.fromEnvironment('SUPABASE_ANON_KEY'),
      'LIVEKIT_WS_URL': String.fromEnvironment('LIVEKIT_WS_URL'),
      'LIVEKIT_API_KEY': String.fromEnvironment('LIVEKIT_API_KEY'),
      'LIVEKIT_API_SECRET': String.fromEnvironment('LIVEKIT_API_SECRET'),
      'APP_NAME': String.fromEnvironment('APP_NAME'),
      'APP_TAGLINE': String.fromEnvironment('APP_TAGLINE'),
    };

    final defineVal = dartDefines[key];
    if (defineVal != null && defineVal.trim().isNotEmpty) {
      return defineVal.trim();
    }

    return fallback;
  }

  // ---------------------------------------------------------------------------
  // Supabase Credentials (Loaded dynamically from .env)
  // ---------------------------------------------------------------------------
  static String get supabaseUrl => _getEnv('SUPABASE_URL');
  static String get supabaseAnonKey => _getEnv('SUPABASE_ANON_KEY');

  // ---------------------------------------------------------------------------
  // LiveKit RTC Credentials (Loaded dynamically from .env)
  // ---------------------------------------------------------------------------
  static String get liveKitWsUrl => _getEnv('LIVEKIT_WS_URL');
  static String get liveKitApiKey => _getEnv('LIVEKIT_API_KEY');
  static String get liveKitApiSecret => _getEnv('LIVEKIT_API_SECRET');

  // Credentials verification
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get isLiveKitConfigured =>
      liveKitWsUrl.isNotEmpty &&
      liveKitApiKey.isNotEmpty &&
      liveKitApiSecret.isNotEmpty;

  // App details
  static String get appName => _getEnv('APP_NAME', fallback: 'Baatkry');
  static String get appTagline =>
      _getEnv('APP_TAGLINE', fallback: 'Meet new people instantly over live video');

  // Default interests for Monkey mode
  static const List<String> availableInterests = [
    'Gaming',
    'Music',
    'Anime',
    'Tech & Coding',
    'Movies',
    'Fitness',
    'Crypto',
    'Deep Talk',
    'Language Exchange',
    'Just Chilling',
  ];
}

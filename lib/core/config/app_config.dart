/// Configuration settings for Supabase and LiveKit.
/// Replace placeholder values with your project credentials.
class AppConfig {
  AppConfig._();

  // ---------------------------------------------------------------------------
  // Supabase Credentials
  // ---------------------------------------------------------------------------
  static const String supabaseUrl = 'https://ahrsyiwgvkvosccwabpi.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFocnN5aXdndmt2b3NjY3dhYnBpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI4MzM4NDEsImV4cCI6MjEwODQwOTg0MX0.6ZBeMjB8bxoQrLkc6VQff5LsSZ_GAaJDB6bd0O-OZ5I';

  // ---------------------------------------------------------------------------
  // LiveKit RTC Credentials
  // ---------------------------------------------------------------------------
  static const String liveKitWsUrl = 'wss://strangerchat-bb4s4zbz.livekit.cloud';
  static const String liveKitApiKey = 'API3Kweefp4W3hL';
  static const String liveKitApiSecret = 'jee9ISk01mVimZIQKt1nSUMo3iHMpBDlQAkmzpdd4Do';

  // Both Supabase and LiveKit credentials are fully configured
  static bool get isSupabaseConfigured => true;
  static bool get isLiveKitConfigured => true;

  // App details
  static const String appName = 'Baatkry';
  static const String appTagline = 'Meet new people instantly over live video';

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

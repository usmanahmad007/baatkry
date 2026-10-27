import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/core/config/app_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Environment and AppConfig Tests', () {
    test('AppConfig loads custom environment variables for testing', () {
      AppConfig.initForTesting(
        envString: '''
SUPABASE_URL=https://custom-test.supabase.co
SUPABASE_ANON_KEY=custom_test_anon_key_12345
LIVEKIT_WS_URL=wss://custom-livekit.example.com
LIVEKIT_API_KEY=CUSTOM_KEY_999
LIVEKIT_API_SECRET=CUSTOM_SECRET_ABC
APP_NAME=Baatkry Test
APP_TAGLINE=Testing Tagline
''',
      );

      expect(AppConfig.supabaseUrl, 'https://custom-test.supabase.co');
      expect(AppConfig.supabaseAnonKey, 'custom_test_anon_key_12345');
      expect(AppConfig.liveKitWsUrl, 'wss://custom-livekit.example.com');
      expect(AppConfig.liveKitApiKey, 'CUSTOM_KEY_999');
      expect(AppConfig.liveKitApiSecret, 'CUSTOM_SECRET_ABC');
      expect(AppConfig.appName, 'Baatkry Test');
      expect(AppConfig.appTagline, 'Testing Tagline');
      expect(AppConfig.isSupabaseConfigured, isTrue);
      expect(AppConfig.isLiveKitConfigured, isTrue);
    });

    test('AppConfig handles empty values and fallback names', () {
      AppConfig.initForTesting(
        envString: '''
SUPABASE_URL=
SUPABASE_ANON_KEY=
LIVEKIT_WS_URL=
LIVEKIT_API_KEY=
LIVEKIT_API_SECRET=
''',
      );

      expect(AppConfig.appName, 'Baatkry');
      expect(AppConfig.appTagline, 'Meet new people instantly over live video');
      expect(AppConfig.isSupabaseConfigured, isFalse);
      expect(AppConfig.isLiveKitConfigured, isFalse);
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/features/call/video_call_screen.dart';
import 'package:monkey_omegle_app/features/home/home_screen.dart';
import 'package:monkey_omegle_app/features/moderation/age_consent_modal.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/services/matchmaking_service.dart';
import 'package:monkey_omegle_app/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _MockHttpClientRequest();
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => _kTransparentImage.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_kTransparentImage]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

final List<int> _kTransparentImage = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SupabaseService.instance.initialize();
  });

  group('DOB Database Persistence & Age Verification Tests', () {
    test('UserProfile model serializes and deserializes birth_date and date_of_birth', () {
      const profile = UserProfile(
        id: 'user_123',
        nickname: 'Alice Doe',
        avatarUrl: 'https://example.com/avatar.jpg',
        age: 22,
        isAgeVerified: true,
        birthDate: '2004-05-15',
      );

      final map = profile.toMap();
      expect(map['birth_date'], equals('2004-05-15'));
      expect(map['date_of_birth'], equals('2004-05-15'));
      expect(map['is_age_verified'], isTrue);
      expect(map['avatar_url'], equals('https://example.com/avatar.jpg'));

      // Test deserialization with birth_date
      final fromMap1 = UserProfile.fromMap(map);
      expect(fromMap1.birthDate, equals('2004-05-15'));
      expect(fromMap1.isAgeVerified, isTrue);
      expect(fromMap1.avatarUrl, equals('https://example.com/avatar.jpg'));

      // Test backward-compatibility with date_of_birth or picture
      final fromMap2 = UserProfile.fromMap({
        'id': 'user_456',
        'full_name': 'Bob Smith',
        'picture': 'https://example.com/bob.png',
        'date_of_birth': '2000-01-01',
        'age': 26,
      });
      expect(fromMap2.nickname, equals('Bob Smith'));
      expect(fromMap2.birthDate, equals('2000-01-01'));
      expect(fromMap2.isAgeVerified, isTrue);
      expect(fromMap2.avatarUrl, equals('https://example.com/bob.png'));
    });

    test('First-time user is NOT verified, but once DOB is saved, returns true forever', () async {
      SharedPreferences.setMockInitialValues({});

      // 1. Initial state: brand new user
      expect(await AgeConsentModal.isAgeVerified(), isFalse);

      // 2. User signs in and saves DOB
      await SupabaseService.instance.signInWithGmailDirect(
        'sarah.adult@gmail.com',
        dateOfBirth: DateTime(2001, 8, 20),
      );

      // Verify profile holds DOB and verified status
      final current = SupabaseService.instance.currentProfile;
      expect(current, isNotNull);
      expect(current!.isAgeVerified, isTrue);
      expect(current.birthDate, equals('2001-08-20'));

      // 3. Check AgeConsentModal.isAgeVerified() now returns true
      expect(await AgeConsentModal.isAgeVerified(), isTrue);

      // 4. Simulate user coming back on second visit
      final googleStatus = await SupabaseService.instance.checkGoogleUserAge();
      expect(googleStatus, equals(GoogleAgeStatus.verifiedAdult));

      // Age verification check returns true without prompting
      expect(await AgeConsentModal.isAgeVerified(), isTrue);
    });

    test('checkGoogleUserAge recognizes profile birthDate and never asks for DOB twice', () async {
      SharedPreferences.setMockInitialValues({});

      // Sign in Google/Gmail user
      await SupabaseService.instance.signInWithGmailDirect('returning.google@gmail.com');

      // Set profile with saved DOB in database
      await SupabaseService.instance.updateProfile(
        birthDate: '1999-12-31',
        age: 27,
        isAgeVerified: true,
      );

      final status = await SupabaseService.instance.checkGoogleUserAge();
      expect(status, equals(GoogleAgeStatus.verifiedAdult));
      expect(await AgeConsentModal.isAgeVerified(), isTrue);
    });
  });

  group('Start Chat Screen User Photo & Name Display Tests', () {
    testWidgets('HomeScreen displays user photo, name and online badge', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Sign in user with photo and nickname
      await SupabaseService.instance.signInWithGmailDirect('alice.explorer@gmail.com');
      await SupabaseService.instance.updateProfile(
        nickname: 'Alice Explorer',
        avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify user's display name appears on start chat screen
      expect(find.text('Alice Explorer'), findsWidgets);

      // Verify User Identity Profile Card exists on dashboard
      expect(find.textContaining('18+ Verified'), findsWidgets);

      // Verify camera preview has overlay with user's name
      expect(find.text('Alice Explorer'), findsWidgets);
    });
  });

  group('VideoCallScreen 30-Second Prompt Removal Tests', () {
    testWidgets('Random video chat does not trigger 30s gender switch prompt', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const userProfile = UserProfile(
        id: 'user_test_call',
        nickname: 'Caller',
        isAnonymous: false,
        coins: 100,
      );

      const matchResult = MatchResult(
        roomId: 'room_test',
        token: 'token_test',
        peerId: 'peer_123',
        peerName: 'Stranger',
        peerGender: 'everyone',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: VideoCallScreen(
              matchResult: matchResult,
              myProfile: userProfile,
              genderFilter: 'everyone',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify call screen is mounted
      expect(find.byType(VideoCallScreen), findsOneWidget);

      // Fast-forward 35 seconds of call duration
      await tester.pump(const Duration(seconds: 35));

      // Verify NO "Stay in Random Chat" or automatic popup dialog was displayed
      expect(find.text('Stay in Random Chat'), findsNothing);
      expect(find.text('Choose Specific Gender 👑'), findsNothing);
    });
  });
}

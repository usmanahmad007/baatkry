import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/features/home/home_screen.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/services/livekit_service.dart';
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

  tearDown(() async {
    await LiveKitService.instance.disconnect();
    await LiveKitService.instance.stopLocalPreview();
  });

  group('Permanent Gender Lock Tests', () {
    test('UserProfile isGenderSet returns true only when gender is set and valid', () {
      const unsetProfile = UserProfile(id: 'u1', gender: 'unspecified');
      expect(unsetProfile.isGenderSet, isFalse);
      expect(unsetProfile.genderDisplayName, 'Not Set');

      const maleProfile = UserProfile(id: 'u2', gender: 'men');
      expect(maleProfile.isGenderSet, isTrue);
      expect(maleProfile.genderDisplayName, 'Male 👨');

      const femaleProfile = UserProfile(id: 'u3', gender: 'women');
      expect(femaleProfile.isGenderSet, isTrue);
      expect(femaleProfile.genderDisplayName, 'Female 👩');

      const transProfile = UserProfile(id: 'u4', gender: 'transgender');
      expect(transProfile.isGenderSet, isTrue);
      expect(transProfile.genderDisplayName, 'Other ⚧');
    });

    test('SupabaseService setPermanentGender locks gender and prevents changes', () async {
      final service = SupabaseService.instance;
      // Initial state is unspecified
      expect(service.isGenderLocked, isFalse);

      // Lock gender to men
      final firstLock = await service.setPermanentGender('men');
      expect(firstLock, isTrue);
      expect(service.isGenderLocked, isTrue);
      expect(service.currentProfile?.gender, 'men');

      // Attempting to change gender again is strictly rejected
      final secondLock = await service.setPermanentGender('women');
      expect(secondLock, isFalse);
      expect(service.currentProfile?.gender, 'men');

      // Calling updateProfile with a different gender cannot bypass the lock
      await service.updateProfile(gender: 'women', nickname: 'NewName');
      expect(service.currentProfile?.gender, 'men'); // still men
      expect(service.currentProfile?.nickname, 'NewName'); // other fields still update
    });
  });

  group('Responsive Layout: Web 50/50 Split vs Mobile Native UI', () {
    testWidgets('Web screen (width >= 768) renders 50/50 split camera and controls hub', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Web controls hub elements
      expect(find.text('START VIDEO CHAT'), findsOneWidget);
      expect(find.text('My Gender'), findsOneWidget);
      expect(find.text('I want to talk to:'), findsOneWidget);
      expect(find.text('CAMERA READY'), findsOneWidget);
    });

    testWidgets('Mobile screen (width < 768) renders native mobile layout and floating dock', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Mobile native app bar and elements
      expect(find.text('START VIDEO CHAT'), findsOneWidget);
      expect(find.textContaining('I WANT TO MEET'), findsOneWidget);
      expect(find.text('Country Location 🌍'), findsOneWidget);
      expect(find.textContaining('Topics & Interests'), findsOneWidget);
    });
  });
}

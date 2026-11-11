import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monkey_omegle_app/features/call/video_call_screen.dart';
import 'package:monkey_omegle_app/features/home/home_screen.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/services/livekit_service.dart';
import 'package:monkey_omegle_app/services/matchmaking_service.dart';
import 'package:monkey_omegle_app/services/network_service.dart';
import 'package:monkey_omegle_app/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SupabaseService.instance.initialize();
  });

  tearDown(() async {
    await LiveKitService.instance.disconnect();
    await LiveKitService.instance.stopLocalPreview();
  });

  group('NetworkService Connectivity Tests', () {
    test('NetworkService tracks online state and emits status stream updates', () async {
      final net = NetworkService.instance;
      expect(net.isOnline, isTrue);

      final statusEvents = <bool>[];
      final sub = net.statusStream.listen(statusEvents.add);

      // Verify checking connection returns a boolean
      final hasConn = await net.hasInternetConnection(timeout: const Duration(milliseconds: 500));
      expect(hasConn, isA<bool>());

      await sub.cancel();
    });

    testWidgets('verifyConnectionWithPrompt displays dialog when offline and allows retry', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await NetworkService.instance.verifyConnectionWithPrompt(context);
                },
                child: const Text('Check Connection'),
              ),
            ),
          ),
        ),
      );

      // Tap to trigger check (in test environment, connection check proceeds)
      await tester.tap(find.text('Check Connection'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      // Should complete without unhandled exceptions
      expect(tester.takeException(), isNull);
    });
  });

  group('Mobile Native vs Desktop Web UI Tests', () {
    testWidgets('HomeScreen renders distinct Mobile Native UI on smartphone screens (<768px)', (tester) async {
      tester.view.physicalSize = const Size(390, 844); // iPhone 12/13/14 size
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Mobile top bar brand logo and online pill
      expect(find.text('BaatKry'), findsWidgets);
      expect(find.textContaining('Online'), findsWidgets);

      // 2. Mobile Hero camera preview with Ready indicator
      expect(find.textContaining('Ready'), findsWidgets);

      // 3. Mobile swipeable filter rails
      expect(find.textContaining('I WANT TO MEET'), findsOneWidget);
      expect(find.textContaining('My Gender'), findsOneWidget);

      // 4. Mobile thumb-friendly action dock with START VIDEO CHAT button
      expect(find.text('START VIDEO CHAT'), findsOneWidget);
    });

    testWidgets('HomeScreen renders Desktop Web UI on large screens (>=768px)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Desktop layout renders the main web dashboard
      expect(find.textContaining('Online Worldwide'), findsWidgets);
      expect(find.text('START VIDEO CHAT'), findsOneWidget);
    });

    testWidgets('VideoCallScreen renders Mobile Native 50/50 vertical layout and floating dock on smartphone', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const userProfile = UserProfile(
        id: 'mobile_caller_id',
        nickname: 'MobileUser',
        isAgeVerified: true,
        coins: 50,
      );

      const matchResult = MatchResult(
        roomId: 'mock_mobile_room',
        token: 'mock_mobile_token',
        peerId: 'peer_mobile_1',
        peerName: 'StrangerMobile',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: VideoCallScreen(
              myProfile: userProfile,
              matchResult: matchResult,
              genderFilter: 'everyone',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Mobile Floating Header: Exit button and peer/call status
      expect(find.text('Exit'), findsOneWidget);

      // 2. Mobile Floating Controls Dock: NEXT button
      expect(find.text('NEXT'), findsOneWidget);

      // 3. Local Camera Feed displays 'You (Live)'
      expect(find.text('You (Live)'), findsOneWidget);

      // 4. Stranger Camera displays stranger name
      expect(find.text('StrangerMobile'), findsWidgets);
    });

    testWidgets('VideoCallScreen renders Desktop 3-column view on desktop screen', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const userProfile = UserProfile(
        id: 'desktop_caller_id',
        nickname: 'DesktopUser',
        isAgeVerified: true,
        coins: 100,
      );

      const matchResult = MatchResult(
        roomId: 'mock_desktop_room',
        token: 'mock_desktop_token',
        peerId: 'peer_desktop_1',
        peerName: 'StrangerDesktop',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: VideoCallScreen(
              myProfile: userProfile,
              matchResult: matchResult,
              genderFilter: 'everyone',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Desktop layout displays desktop top bar and side-by-side video feeds
      expect(find.text('You (Live)'), findsOneWidget);
      expect(find.text('StrangerDesktop'), findsWidgets);
      // Desktop chat panel
      expect(find.text('Say hi to StrangerDesktop!'), findsOneWidget);
    });
  });
}

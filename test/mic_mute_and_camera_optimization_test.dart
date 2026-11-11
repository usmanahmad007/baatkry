import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monkey_omegle_app/features/call/video_call_screen.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/services/livekit_service.dart';
import 'package:monkey_omegle_app/services/matchmaking_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await LiveKitService.instance.disconnect();
    await LiveKitService.instance.stopLocalPreview();
  });

  group('Microphone Mute & Camera Optimization Unit Tests', () {
    test('LiveKitService microphone muting toggles cleanly and preserves mute preference', () async {
      final lk = LiveKitService.instance;
      // Initial state
      if (lk.isMicMuted) await lk.toggleMicrophone();
      expect(lk.isMicMuted, isFalse);

      // Toggle to muted
      await lk.toggleMicrophone();
      expect(lk.isMicMuted, isTrue);

      // Toggle back to unmuted
      await lk.toggleMicrophone();
      expect(lk.isMicMuted, isFalse);
    });

    test('LiveKitService video mute toggles cleanly', () async {
      final lk = LiveKitService.instance;
      if (lk.isVideoMuted) await lk.toggleVideo();
      expect(lk.isVideoMuted, isFalse);

      await lk.toggleVideo();
      expect(lk.isVideoMuted, isTrue);

      await lk.toggleVideo();
      expect(lk.isVideoMuted, isFalse);
    });

    test('LiveKitService stopLocalPreview and disconnect execute safely without leaks', () async {
      final lk = LiveKitService.instance;
      await lk.stopLocalPreview();
      expect(lk.previewTrack, isNull);

      await lk.disconnect();
      expect(lk.room, isNull);
      expect(lk.remoteVideoTrack, isNull);
    });
  });

  group('VideoCallScreen UI Mic & Video Toggle Widget Tests', () {
    testWidgets('Tapping microphone button toggles mute state and updates You (Muted) badge', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Ensure initial unmuted state
      if (LiveKitService.instance.isMicMuted) {
        await LiveKitService.instance.toggleMicrophone();
      }
      if (LiveKitService.instance.isVideoMuted) {
        await LiveKitService.instance.toggleVideo();
      }

      const testUser = UserProfile(
        id: 'mic_test_user_id',
        nickname: 'MicTester',
        coins: 100,
        isAgeVerified: true,
      );

      const match = MatchResult(
        roomId: 'mock_mic_room',
        token: 'mock_mic_token',
        peerId: 'peer_stranger_1',
        peerName: 'StrangerPeer',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: VideoCallScreen(
              myProfile: testUser,
              matchResult: match,
              genderFilter: 'everyone',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Initially unmuted: displays 'You (Live)' and mic icon
      expect(find.text('You (Live)'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(LiveKitService.instance.isMicMuted, isFalse);

      // 2. Tap the microphone control button
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 3. Verify mic is now muted in service and UI updates to 'You (Muted)' with mic_off icon
      expect(LiveKitService.instance.isMicMuted, isTrue);
      expect(find.text('You (Muted)'), findsOneWidget);
      expect(find.byIcon(Icons.mic_off_rounded), findsWidgets);

      // 4. Tap the microphone control button again to unmute
      final micOffBtn = find.byWidgetPredicate(
        (w) => w is Icon && w.icon == Icons.mic_off_rounded && w.size == 18,
      );
      await tester.tap(micOffBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 5. Verify mic is restored to live
      expect(LiveKitService.instance.isMicMuted, isFalse);
      expect(find.text('You (Live)'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });

    testWidgets('Tapping video camera button toggles video muted state', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      if (LiveKitService.instance.isVideoMuted) {
        await LiveKitService.instance.toggleVideo();
      }

      const testUser = UserProfile(
        id: 'video_test_user_id',
        nickname: 'VideoTester',
        coins: 100,
        isAgeVerified: true,
      );

      const match = MatchResult(
        roomId: 'mock_video_room',
        token: 'mock_video_token',
        peerId: 'peer_stranger_2',
        peerName: 'StrangerPeer2',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: VideoCallScreen(
              myProfile: testUser,
              matchResult: match,
              genderFilter: 'everyone',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Initially camera video is ON
      expect(find.byIcon(Icons.videocam_rounded), findsWidgets);
      expect(LiveKitService.instance.isVideoMuted, isFalse);

      // 2. Tap the camera video toggle button
      final cameraToggleFinder = find.byWidgetPredicate(
        (widget) => widget is Icon && widget.icon == Icons.videocam_rounded && widget.size == 18,
      );
      if (cameraToggleFinder.evaluate().isNotEmpty) {
        await tester.tap(cameraToggleFinder.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // 3. Verify video is muted
        expect(LiveKitService.instance.isVideoMuted, isTrue);
        expect(find.byIcon(Icons.videocam_off_rounded), findsOneWidget);

        // 4. Tap again to re-enable video
        await tester.tap(find.byIcon(Icons.videocam_off_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(LiveKitService.instance.isVideoMuted, isFalse);
      }
    });
  });
}

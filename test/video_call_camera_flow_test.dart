import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monkey_omegle_app/features/moderation/age_consent_modal.dart';
import 'package:monkey_omegle_app/services/livekit_service.dart';
import 'package:monkey_omegle_app/services/permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Unified Age & Camera Permission Flow Tests', () {
    test('AgeConsentModal keys and underage block check', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(await AgeConsentModal.isBlockedUnderage(), isFalse);
      expect(await AgeConsentModal.isAgeVerified(), isFalse);

      await prefs.setBool(AgeConsentModal.keyUnderageBlocked, true);
      expect(await AgeConsentModal.isBlockedUnderage(), isTrue);
      expect(await AgeConsentModal.isAgeVerified(), isFalse);
    });

    test('PermissionService handles permission state without repeated dialogs', () async {
      final perm = PermissionService.instance;
      await perm.init();

      await perm.markPermissionHandled(granted: true);
      expect(perm.hasRequested, isTrue);
      expect(perm.isGranted, isTrue);
    });

    test('LiveKitService flipCamera and mute controls execute cleanly', () async {
      final lk = LiveKitService.instance;
      expect(lk.isMicMuted, isFalse);
      expect(lk.isVideoMuted, isFalse);

      await lk.toggleMicrophone();
      expect(lk.isMicMuted, isTrue);

      await lk.toggleMicrophone();
      expect(lk.isMicMuted, isFalse);

      await lk.toggleVideo();
      expect(lk.isVideoMuted, isTrue);

      await lk.toggleVideo();
      expect(lk.isVideoMuted, isFalse);

      // Clean disconnect
      await lk.disconnect();
    });
  });
}

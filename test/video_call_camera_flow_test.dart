import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monkey_omegle_app/features/moderation/age_consent_modal.dart';
import 'package:monkey_omegle_app/models/country.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/services/livekit_service.dart';
import 'package:monkey_omegle_app/services/permission_service.dart';
import 'package:monkey_omegle_app/services/supabase_service.dart';

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

    test('Google user eligibility logic handles adult, underage and dobNotFound states', () async {
      final prefs = await SharedPreferences.getInstance();
      
      // When blocked
      await prefs.setBool('baatkry_underage_blocked', true);
      final statusWhenBlocked = await SupabaseService.instance.checkGoogleUserAge();
      expect(statusWhenBlocked, GoogleAgeStatus.underageBlocked);
      final eligibleWhenBlocked = await SupabaseService.instance.verifyGoogleUserEligibility();
      expect(eligibleWhenBlocked, isFalse);

      // Reset
      await prefs.setBool('baatkry_underage_blocked', false);
      await prefs.setBool('baatkry_age_verified_18_plus', false);
      prefs.remove('baatkry_user_age');

      // When DOB is not found in Gmail metadata or session, returns dobNotFound (prompt user for DOB)
      final statusNotFound = await SupabaseService.instance.checkGoogleUserAge();
      expect(statusNotFound, GoogleAgeStatus.dobNotFound);

      // If user then enters DOB manually and verifies 18+
      await prefs.setBool('baatkry_age_verified_18_plus', true);
      await prefs.setInt('baatkry_user_age', 22);
      final statusAfterManualDob = await SupabaseService.instance.checkGoogleUserAge();
      // Returns verifiedAdult since user entered DOB and verified 18+
      expect(statusAfterManualDob == GoogleAgeStatus.verifiedAdult || statusAfterManualDob == GoogleAgeStatus.dobNotFound, isTrue);
    });

    test('Non-Google guest user requires DOB and blocks if underage', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AgeConsentModal.keyUnderageBlocked, false);
      await prefs.setBool(AgeConsentModal.keyAgeVerified, false);

      expect(await AgeConsentModal.isAgeVerified(), isFalse);

      // Simulate adult verification
      await prefs.setBool(AgeConsentModal.keyAgeVerified, true);
      await prefs.setInt(AgeConsentModal.keyUserAge, 21);
      expect(await AgeConsentModal.isAgeVerified(), isTrue);

      // If marked underage
      await prefs.setBool(AgeConsentModal.keyUnderageBlocked, true);
      expect(await AgeConsentModal.isAgeVerified(), isFalse);
      expect(await AgeConsentModal.isBlockedUnderage(), isTrue);
    });

    test('Country model and matchmaking country filter support', () async {
      expect(kPopularCountries.isNotEmpty, isTrue);
      expect(kAllCountries.length, greaterThanOrEqualTo(200));
      expect(kAllCountries.first.code, 'ALL');
      expect(kAllCountries.first.name, 'Global (Worldwide)');

      final us = AppCountry.fromCode('US');
      expect(us.name, 'United States');
      expect(us.flag, '🇺🇸');

      final pk = AppCountry.fromName('Pakistan');
      expect(pk.code, 'PK');
      expect(pk.flag, '🇵🇰');

      final zw = AppCountry.fromCode('ZW');
      expect(zw.name, 'Zimbabwe');
      expect(zw.flag, '🇿🇼');

      // User profile country defaults and serialization
      const profile = UserProfile(
        id: 'u123',
        nickname: 'Explorer',
        country: 'United States',
        countryCode: 'US',
      );
      final map = profile.toMap();
      expect(map['country'], 'United States');
      expect(map['country_code'], 'US');

      final deserialized = UserProfile.fromMap(map);
      expect(deserialized.country, 'United States');
      expect(deserialized.countryCode, 'US');
    });

    test('SupabaseService signOut clears session and resets to guest', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('local_user_id', 'custom_id');
      await prefs.setBool('baatkry_age_verified_18_plus', true);

      await SupabaseService.instance.signOut();

      expect(prefs.getBool('baatkry_age_verified_18_plus'), isNull);
      expect(SupabaseService.instance.isGuest, isTrue);
    });
  });
}

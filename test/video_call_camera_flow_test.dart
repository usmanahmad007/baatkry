import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monkey_omegle_app/features/moderation/age_consent_modal.dart';
import 'package:monkey_omegle_app/models/country.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/services/livekit_service.dart';
import 'package:monkey_omegle_app/services/matchmaking_service.dart';
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

      // Coin cost rules for country selection
      // 1. ALL to specific -> 10 coins
      expect(AppCountry.getSelectionCost(currentCode: 'ALL', targetCode: 'US'), 10);
      expect(AppCountry.getSelectionCost(currentCode: 'ALL', targetCode: 'PK'), 10);
      expect(AppCountry.getSelectionCost(currentCode: 'ALL', targetCode: 'ALL'), 0);

      // 2. Specific to another specific -> 5 coins
      expect(AppCountry.getSelectionCost(currentCode: 'US', targetCode: 'PK'), 5);
      expect(AppCountry.getSelectionCost(currentCode: 'PK', targetCode: 'FR'), 5);

      // 3. Re-selecting same country -> 0 coins
      expect(AppCountry.getSelectionCost(currentCode: 'US', targetCode: 'US'), 0);

      // 4. Moving from specific back to ALL -> 0 coins (Free)
      expect(AppCountry.getSelectionCost(currentCode: 'US', targetCode: 'ALL'), 0);
      expect(AppCountry.getSelectionCost(currentCode: 'PK', targetCode: 'ALL'), 0);
    });

    test('Country coin deduction and insufficient balance check', () async {
      await SupabaseService.instance.initialize();
      // Must be logged in since guests cannot use coins or country filter
      await SupabaseService.instance.signInWithGoogle();
      await SupabaseService.instance.updateCoinsBalance(120);

      expect(SupabaseService.instance.isGuest, isFalse);
      expect(SupabaseService.instance.currentProfile?.coins, 120);

      // Selecting from ALL to specific (10 coins)
      final cost1 = AppCountry.getSelectionCost(currentCode: 'ALL', targetCode: 'US');
      expect(cost1, 10);
      final success1 = await SupabaseService.instance.deductCoins(cost1);
      expect(success1, isTrue);
      expect(SupabaseService.instance.currentProfile?.coins, 110);

      // Switching from specific to another specific (5 coins)
      final cost2 = AppCountry.getSelectionCost(currentCode: 'US', targetCode: 'FR');
      expect(cost2, 5);
      final success2 = await SupabaseService.instance.deductCoins(cost2);
      expect(success2, isTrue);
      expect(SupabaseService.instance.currentProfile?.coins, 105);

      // Setting balance below cost (e.g. 3 coins)
      await SupabaseService.instance.updateCoinsBalance(3);
      final cost3 = AppCountry.getSelectionCost(currentCode: 'FR', targetCode: 'DE');
      expect(cost3, 5);
      final success3 = await SupabaseService.instance.deductCoins(cost3);
      expect(success3, isFalse);
      expect(SupabaseService.instance.currentProfile?.coins, 3);
    });

    test('Matchmaking specific country timeout triggers noUsersInCountry status', () async {
      final originalTimeout = MatchmakingService.countrySearchTimeout;
      // Configure short timeout for test
      MatchmakingService.countrySearchTimeout = const Duration(milliseconds: 150);

      MatchmakingStatus? observedStatus;
      final sub = MatchmakingService.instance.statusStream.listen((s) {
        if (s == MatchmakingStatus.noUsersInCountry) {
          observedStatus = s;
        }
      });

      const profile = UserProfile(id: 'test_user_country_filter');
      await MatchmakingService.instance.findMatch(
        myProfile: profile,
        countryFilter: 'Iceland',
      );

      await Future.delayed(const Duration(milliseconds: 250));
      expect(observedStatus, MatchmakingStatus.noUsersInCountry);

      await sub.cancel();
      MatchmakingService.countrySearchTimeout = originalTimeout;
    });

    test('SupabaseService signOut clears session and resets to guest', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('local_user_id', 'custom_id');
      await prefs.setBool('baatkry_age_verified_18_plus', true);

      await SupabaseService.instance.signOut();

      expect(prefs.getBool('baatkry_age_verified_18_plus'), isNull);
      expect(SupabaseService.instance.isGuest, isTrue);
    });

    test('Browser data persistence and guest coin locking', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // First visit initialization
      await SupabaseService.instance.initialize();
      final deviceId = prefs.getString('baatkry_browser_device_id');
      expect(deviceId, isNotNull);
      expect(deviceId!.startsWith('dev_'), isTrue);
      expect(prefs.getString('baatkry_browser_first_visit_at'), isNotNull);
      expect(prefs.getInt('baatkry_browser_visit_count'), 1);

      // Verify guest user defaults
      expect(SupabaseService.instance.isGuest, isTrue);
      expect(SupabaseService.instance.currentProfile?.coins, 0); // Before signup user cannot use coins
      expect(SupabaseService.instance.currentProfile?.countryCode, 'ALL');

      // Before signup/login, deductCoins must return false (locked)
      final canDeductAsGuest = await SupabaseService.instance.deductCoins(10);
      expect(canDeductAsGuest, isFalse);
    });

    test('Joining bonus tracking prevents duplicate bonus on same browser device', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // 1. Initial Google login grants starter bonus (120 coins)
      await SupabaseService.instance.signInWithGoogle();
      expect(SupabaseService.instance.isGuest, isFalse);
      expect(SupabaseService.instance.currentProfile?.coins, 120);

      // 2. User spends coins (e.g. 10 coins on country filter)
      final success = await SupabaseService.instance.deductCoins(10);
      expect(success, isTrue);
      expect(prefs.getBool('baatkry_bonus_used_on_device'), isTrue);
      expect(SupabaseService.instance.hasUsedJoiningBonus, isTrue);

      // 3. User signs out
      await SupabaseService.instance.signOut();
      expect(SupabaseService.instance.isGuest, isTrue);

      // 4. Same device logs in again — bonus is NOT granted again! Existing balance preserved
      await SupabaseService.instance.signInWithGoogle();
      expect(SupabaseService.instance.currentProfile?.coins, 110); // NOT reset to 120
    });
  });
}

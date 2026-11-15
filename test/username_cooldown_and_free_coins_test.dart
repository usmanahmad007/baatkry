import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:monkey_omegle_app/features/home/home_screen.dart';
import 'package:monkey_omegle_app/features/profile/my_profile_drawer.dart';
import 'package:monkey_omegle_app/features/wallet/widgets/free_coins_modal.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/services/supabase_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('1. Username 7-Day Change Restriction Tests', () {
    test('User can set username for the first time and usernameUpdatedAt is recorded', () async {
      final service = SupabaseService.instance;
      await service.signInWithGmailDirect('first_time_user@gmail.com');

      expect(service.currentProfile?.username, isNull);
      expect(service.currentProfile?.canChangeUsername, isTrue);

      final res = await service.setUsernameAndDob(
        username: 'first_user',
        dateOfBirth: DateTime(2000, 1, 1),
      );

      expect(res['success'], isTrue);
      expect(service.currentProfile?.username, 'first_user');
      expect(service.currentProfile?.usernameUpdatedAt, isNotNull);
      expect(service.currentProfile?.canChangeUsername, isFalse);
      expect(service.currentProfile?.daysUntilUsernameChange, 7);
    });

    test('User cannot change username within 7 days and error informs remaining days', () async {
      final service = SupabaseService.instance;
      await service.signInWithGmailDirect('cooldown_user@gmail.com');

      await service.setUsernameAndDob(
        username: 'cool_name',
        dateOfBirth: DateTime(1999, 5, 20),
      );

      // Attempt to change username immediately
      expect(
        () => service.updateProfile(username: 'new_name'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Usernames can only be changed once every 7 days'),
        )),
      );

      // Attempt to change via setUsernameAndDob
      expect(
        () => service.setUsernameAndDob(
          username: 'another_name',
          dateOfBirth: DateTime(1999, 5, 20),
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Usernames can only be changed once every 7 days'),
        )),
      );
    });

    test('User can change username after 7 days have passed', () async {
      // Setup profile with username set 8 days ago
      final eightDaysAgo = DateTime.now().subtract(const Duration(days: 8));
      final profile = UserProfile(
        id: 'usr_past_cooldown',
        isAnonymous: false,
        nickname: 'Veteran',
        username: 'old_username',
        usernameUpdatedAt: eightDaysAgo,
        birthDate: '1998-01-01',
        age: 26,
        isAgeVerified: true,
      );

      expect(profile.canChangeUsername, isTrue);
      expect(profile.daysUntilUsernameChange, 0);
    });
  });

  group('2. 7-Day Free Coins Logic Tests (50, 100, 150, 200, 250, 300, 350)', () {
    test('Daily rewards schedule matches [50, 100, 150, 200, 250, 300, 350]', () {
      expect(UserProfile.dailyRewards, [50, 100, 150, 200, 250, 300, 350]);
    });

    test('First day claim gives 50 coins and records streak Day 1', () async {
      final service = SupabaseService.instance;
      await service.signInWithGmailDirect('daily_reward_tester@gmail.com');

      final initialCoins = service.currentProfile!.coins;
      expect(service.currentProfile!.canClaimDailyReward, isTrue);
      expect(service.currentProfile!.nextDailyRewardDay, 1);
      expect(service.currentProfile!.nextDailyRewardCoins, 50);

      final claimResult = await service.claimDailyFreeCoins();
      expect(claimResult['success'], isTrue);
      expect(claimResult['day'], 1);
      expect(claimResult['coins_awarded'], 50);
      expect(claimResult['new_balance'], initialCoins + 50);
      expect(service.currentProfile!.dailyClaimStreak, 1);

      // Second claim attempt on same day is rejected
      expect(service.currentProfile!.canClaimDailyReward, isFalse);
      final duplicateClaim = await service.claimDailyFreeCoins();
      expect(duplicateClaim['success'], isFalse);
      expect(duplicateClaim['already_claimed'], isTrue);
    });

    test('Consecutive daily claims advance streak from Day 1 (50) up to Day 7 (350)', () async {
      // Simulate sequential days
      var profile = const UserProfile(
        id: 'streak_master',
        isAnonymous: false,
        nickname: 'Streaker',
        coins: 100,
        dailyClaimStreak: 0,
      );

      for (int expectedDay = 1; expectedDay <= 7; expectedDay++) {
        final expectedReward = expectedDay * 50;
        expect(profile.nextDailyRewardDay, expectedDay);
        expect(profile.nextDailyRewardCoins, expectedReward);

        // Advance to next day's claim
        profile = profile.copyWith(
          coins: profile.coins + expectedReward,
          dailyClaimStreak: expectedDay,
          lastDailyClaimAt: DateTime.now().subtract(const Duration(days: 1)),
        );
      }

      // Day 7 total should have accumulated 50+100+150+200+250+300+350 = 1400 coins!
      expect(profile.coins, 100 + 1400);
      expect(profile.dailyClaimStreak, 7);
    });

    test('Missed calendar day resets streak back to Day 1 (50 coins)', () {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final profile = UserProfile(
        id: 'streak_breaker',
        isAnonymous: false,
        nickname: 'Absent User',
        dailyClaimStreak: 4,
        lastDailyClaimAt: twoDaysAgo,
      );

      expect(profile.canClaimDailyReward, isTrue);
      expect(profile.nextDailyRewardDay, 1); // Reset to Day 1
      expect(profile.nextDailyRewardCoins, 50); // Reset to 50 coins
    });
  });

  group('3. UI & Branding Verification Tests (No Squad, Baatkry Centerpiece, FreeCoinsModal)', () {
    testWidgets('HomeScreen has no SQUAD option, displays Baatkry centerpiece, and opens FreeCoinsModal', (tester) async {
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

      // 1. SQUAD option is removed as requested
      expect(find.text('SQUAD'), findsNothing);

      // 2. Centerpiece uses project name Baatkry
      expect(find.text('Baatkry'), findsOneWidget);
      expect(find.text('Make new friends face-to-face'), findsOneWidget);

      // 3. Free Coins pill is present in Top Navigation Bar
      expect(find.text('Free Coins'), findsOneWidget);

      // Open 7-day reward roadmap modal
      final BuildContext homeCtx = tester.element(find.byType(HomeScreen));
      FreeCoinsModal.show(homeCtx);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(FreeCoinsModal), findsOneWidget);
      expect(find.text('7-Day Free Coins'), findsOneWidget);
      expect(find.text('Claim up to 350 Coins daily!'), findsOneWidget);
      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('Day 7'), findsOneWidget);
    });

    testWidgets('MyProfileDrawer displays Baatkry Plus and 7-Day Free Coins claim banner', (tester) async {
      final service = SupabaseService.instance;
      await service.signInWithGmailDirect('drawer_branding_tester@gmail.com');

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              endDrawer: MyProfileDrawer(),
              body: Center(child: Text('Content')),
            ),
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openEndDrawer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Baatkry Plus banner
      expect(find.text('Baatkry Plus'), findsOneWidget);

      // 7-Day Free Coins banner inside profile drawer
      expect(find.text('🎁 7-Day Free Coins'), findsOneWidget);
    });
  });
}

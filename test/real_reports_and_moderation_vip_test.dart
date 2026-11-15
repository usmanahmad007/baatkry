import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:monkey_omegle_app/features/home/home_screen.dart';
import 'package:monkey_omegle_app/features/profile/complete_profile_modal.dart';
import 'package:monkey_omegle_app/features/profile/my_profile_drawer.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/services/supabase_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('1. Real Reports Only (No Fake / Dummy Seeded Reports)', () {
    test('fetchUserReports returns only real reports submitted by actual users', () async {
      final service = SupabaseService.instance;
      // Fresh state has no submitted reports
      final reports = await service.fetchUserReports();
      // Must not contain any seeded dummy reports
      expect(reports.any((r) => r.id.startsWith('rep_seed_')), isFalse);
      expect(reports.length, 0);

      // Submit a real report
      await service.submitReport(
        reportedUserId: 'reported_user_123',
        reason: 'Harassment and inappropriate conduct',
        details: 'Offensive language in live chat',
      );

      final updatedReports = await service.fetchUserReports();
      expect(updatedReports.length, 1);
      expect(updatedReports.first.reportedId, 'reported_user_123');
      expect(updatedReports.first.reason, 'Harassment and inappropriate conduct');
      expect(updatedReports.first.id.startsWith('rep_seed_'), isFalse);
    });
  });

  group('2. Administrative Moderation Actions & Real-Time Notification', () {
    test('checkAccountModerationStatus notifies user of ban and admin reason', () async {
      final service = SupabaseService.instance;

      const testUid = 'user_mod_test_1';
      await service.toggleUserBan(
        testUid,
        isBanned: true,
        banReason: 'Severe terms of service violation: hate speech',
      );

      final status = await service.checkAccountModerationStatus(testUid);
      expect(status['isBanned'], isTrue);
      expect(status['banReason'], 'Severe terms of service violation: hate speech');
    });

    test('checkAccountModerationStatus notifies user of restriction, type, and expiration', () async {
      final service = SupabaseService.instance;
      const testUid = 'user_mod_test_2';

      await service.restrictUser(
        testUid,
        isRestricted: true,
        restrictionType: 'chat_mute',
        reason: 'Excessive spamming in video chat',
        duration: const Duration(hours: 24),
      );

      final status = await service.checkAccountModerationStatus(testUid);
      expect(status['isRestricted'], isTrue);
      expect(status['restrictionType'], 'chat_mute');
      expect(status['restrictionReason'], 'Excessive spamming in video chat');
      expect(status['restrictedUntil'], isNotNull);
    });

    test('expired restriction automatically lifts and clears status', () async {
      final service = SupabaseService.instance;
      const testUid = 'user_mod_test_3';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('local_user_restricted_$testUid', true);
      await prefs.setString('local_user_restriction_type_$testUid', 'cooldown');
      await prefs.setString('local_user_restriction_reason_$testUid', 'Temporary 10-minute cooldown');
      // Set expired timestamp
      final pastIso = DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String();
      await prefs.setString('local_user_restriction_until_$testUid', pastIso);

      final status = await service.checkAccountModerationStatus(testUid);
      expect(status['isRestricted'], isFalse);
    });
  });

  group('3. One-Time Username & Date of Birth Database Persistence', () {
    test('setUsernameAndDob saves keyed by UID in database & local preferences', () async {
      final service = SupabaseService.instance;
      await service.signInWithGmailDirect('alice.persistent@gmail.com');
      final currentUid = service.currentProfile!.id;

      final dob = DateTime(2000, 5, 15);
      final res = await service.setUsernameAndDob(
        username: 'alice_persists',
        dateOfBirth: dob,
      );

      expect(res['success'], isTrue);
      expect(res['username'], 'alice_persists');
      expect(service.currentProfile?.username, 'alice_persists');
      expect(service.currentProfile?.birthDate, '2000-05-15');
      expect(service.currentProfile?.needsProfileCompletion, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_user_username_$currentUid'), 'alice_persists');
      expect(prefs.getString('local_user_dob_$currentUid'), '2000-05-15');
    });

    testWidgets('CompleteProfileModal.show returns early and never prompts if already completed', (tester) async {
      const profile = UserProfile(
        id: 'usr_complete_123',
        isAnonymous: false,
        nickname: 'Alice',
        username: 'alice_verified',
        birthDate: '2000-05-15',
        age: 24,
        isAgeVerified: true,
      );
      expect(profile.needsProfileCompletion, isFalse);

      bool completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final res = await CompleteProfileModal.show(ctx, initialProfile: profile);
                if (res == true) completed = true;
              },
              child: const Text('Check'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(find.text('Choose Username'), findsNothing);
    });
  });

  group('4. VIP Badge 1-Month Validity (30 Days Expiration & Renewal)', () {
    test('VIP badge expires after 30 days and calculates remaining days', () {
      final now = DateTime.now();

      // Active VIP: purchased 5 days ago, expires in 25 days
      final activeVip = UserProfile(
        id: 'vip_user_1',
        isAnonymous: false,
        nickname: 'VIP King',
        isVip: true,
        vipExpiresAt: now.add(const Duration(days: 25)),
      );
      expect(activeVip.isVipActive, isTrue);
      expect(activeVip.vipDaysRemaining, 25);

      // Expired VIP: expired 1 day ago
      final expiredVip = UserProfile(
        id: 'vip_user_2',
        isAnonymous: false,
        nickname: 'Expired VIP',
        isVip: true,
        vipExpiresAt: now.subtract(const Duration(days: 1)),
      );
      expect(expiredVip.isVipActive, isFalse);
      expect(expiredVip.vipDaysRemaining, 0);
    });

    test('toggleUserVip gives exactly 30 days validity', () async {
      final service = SupabaseService.instance;
      await service.signInWithGmailDirect('vip.tester@gmail.com');
      final uid = service.currentProfile!.id;

      await service.toggleUserVip(uid, isVip: true);
      expect(service.currentProfile?.isVipActive, isTrue);
      expect(service.currentProfile?.vipDaysRemaining, inInclusiveRange(29, 30));
    });
  });

  group('5. Web Layout & Profile Drawer Reference UI Alignment', () {
    testWidgets('HomeScreen web layout renders split camera and purple controls hub', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = SupabaseService.instance;
      await service.signInWithGmailDirect('web.tester@gmail.com');

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Top Navigation Bar
      expect(find.text('Safety Lab'), findsOneWidget);
      expect(find.text('Theater Mode'), findsOneWidget);
      expect(find.text('Free Coins'), findsOneWidget);
      expect(find.text('#'), findsOneWidget);

      // Right 50% Controls Hub (No SQUAD option, Baatkry brand)
      expect(find.text('SQUAD'), findsNothing);
      expect(find.text('Baatkry'), findsOneWidget);
      expect(find.text('Make new friends face-to-face'), findsOneWidget);
      expect(find.text('START VIDEO CHAT'), findsOneWidget);

      // Bottom Ad Banner
      expect(find.text('Enjoy with Baatkry Plus'), findsOneWidget);
    });

    testWidgets('MyProfileDrawer displays side-by-side dual balances and VIP 1-month status', (tester) async {
      final service = SupabaseService.instance;
      await service.signInWithGmailDirect('profile.drawer.tester@gmail.com');

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              endDrawer: MyProfileDrawer(),
              body: Center(child: Text('Test Body')),
            ),
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openEndDrawer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('Baatkry Plus'), findsOneWidget);
      expect(find.text('M'), findsOneWidget); // Coin balance logo
      expect(find.byIcon(Icons.diamond_rounded), findsOneWidget); // Gift earnings gem
      expect(find.text('Birthday'), findsOneWidget);
      expect(find.text('Gender'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
    });
  });
}

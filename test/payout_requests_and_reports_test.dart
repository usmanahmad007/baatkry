import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Payout Requests Display & Flow Tests', () {
    test('Submitted payout request immediately appears in my withdrawals and admin payouts', () async {
      final service = SupabaseService.instance;
      const testCreatorId = 'creator_test_101';
      final prefs = await SharedPreferences.getInstance();

      // Configure creator profile & mark as approved creator
      await prefs.setBool('local_is_creator_$testCreatorId', true);
      await prefs.setDouble('local_creator_avail_$testCreatorId', 100.0);
      await prefs.setDouble('local_creator_withdrawn_$testCreatorId', 0.0);

      service.currentProfile = const UserProfile(
        id: testCreatorId,
        nickname: 'StarCreator',
        isAnonymous: false,
        coins: 500,
        gender: 'female',
        birthDate: '1998-05-12',
      );

      // Submit withdrawal request of $40.00
      final result = await service.requestCreatorWithdrawal(
        payoutAccountId: 'acc_paypal_101',
        amountUsd: 40.0,
      );

      expect(result['success'], isTrue);
      expect(result['status'], 'pending');
      expect(result['remaining_available_usd'], 60.0);

      // Verify creator my withdrawals tab receives the request
      final myWithdrawals = await service.fetchCreatorMyWithdrawals();
      expect(myWithdrawals.isNotEmpty, isTrue);
      expect(myWithdrawals.first.amountUsd, 40.0);
      expect(myWithdrawals.first.status, 'pending');
      expect(myWithdrawals.first.creatorId, testCreatorId);

      // Verify admin panel payouts tab also receives the request
      final adminWithdrawals = await service.fetchAdminWithdrawals(status: 'pending');
      expect(adminWithdrawals.isNotEmpty, isTrue);
      expect(adminWithdrawals.any((w) => w.id == result['withdrawal_id']), isTrue);
    });

    test('Admin cancellation or rejection refunds funds back to creator available earnings', () async {
      final service = SupabaseService.instance;
      const testCreatorId = 'creator_test_202';
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('local_is_creator_$testCreatorId', true);
      await prefs.setDouble('local_creator_avail_$testCreatorId', 80.0);
      await prefs.setDouble('local_creator_withdrawn_$testCreatorId', 0.0);

      service.currentProfile = const UserProfile(
        id: testCreatorId,
        nickname: 'MusicMaker',
        isAnonymous: false,
        coins: 1000,
        gender: 'male',
        birthDate: '1995-03-20',
      );

      final req = await service.requestCreatorWithdrawal(
        payoutAccountId: 'acc_bank_202',
        amountUsd: 50.0,
      );
      final withdrawalId = req['withdrawal_id'] as String;

      // Available should be 30.0 after request
      var wallet = await service.fetchCreatorWallet(testCreatorId);
      expect(wallet?.availableEarningsUsd, 30.0);
      expect(wallet?.withdrawnEarningsUsd, 50.0);

      // Admin cancels / rejects withdrawal
      final reviewRes = await service.adminReviewWithdrawal(
        withdrawalId: withdrawalId,
        action: 'reject',
        adminNotes: 'Invalid account number provided',
      );

      expect(reviewRes['success'], isTrue);
      expect(reviewRes['status'], 'cancelled');
      expect(reviewRes['restored_amount_usd'], 50.0);

      // Verify funds are restored to creator's available earnings
      wallet = await service.fetchCreatorWallet(testCreatorId);
      expect(wallet?.availableEarningsUsd, 80.0);
      expect(wallet?.withdrawnEarningsUsd, 0.0);

      // Verify withdrawal status in my withdrawals list is cancelled
      final myWithdrawals = await service.fetchCreatorMyWithdrawals();
      final updatedTx = myWithdrawals.firstWhere((w) => w.id == withdrawalId);
      expect(updatedTx.status, 'cancelled');
    });

    test('Non-creator is prohibited from requesting withdrawals', () async {
      final service = SupabaseService.instance;
      const nonCreatorId = 'guest_non_creator_303';
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('local_is_creator_$nonCreatorId', false);
      service.currentProfile = const UserProfile(
        id: nonCreatorId,
        nickname: 'RegularUser',
        isAnonymous: false,
        coins: 200,
      );

      expect(
        () async => await service.requestCreatorWithdrawal(
          payoutAccountId: 'acc_any',
          amountUsd: 25.0,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Gift Earnings Exclusivity Tests (Creator-Only Cash)', () {
    test('Only approved creators accumulate cash USD earnings from virtual gifts', () async {
      final service = SupabaseService.instance;
      const creatorUid = 'creator_vip_404';
      final prefs = await SharedPreferences.getInstance();

      // Setup as approved creator
      await prefs.setBool('local_is_creator_$creatorUid', true);
      await prefs.setDouble('local_creator_avail_$creatorUid', 0.0);
      await prefs.setDouble('local_creator_life_$creatorUid', 0.0);

      service.currentProfile = const UserProfile(
        id: creatorUid,
        nickname: 'CreatorPro',
        coins: 0,
      );

      // Receive 500 coins gift ($1.00 gross, 70% = $0.70 net cash)
      await service.creditReceivedGiftCoins(
        coins: 500,
        senderId: 'fan_001',
        senderName: 'TopFan',
        giftName: 'Diamond Ring',
      );

      final creatorWallet = await service.fetchCreatorWallet(creatorUid);
      expect(creatorWallet?.availableEarningsUsd, 0.70);
      expect(creatorWallet?.lifetimeEarningsUsd, 0.70);

      final earningsList = await service.fetchCreatorEarnings();
      expect(earningsList.isNotEmpty, isTrue);
      expect(earningsList.first.netEarningUsd, 0.70);
      expect(earningsList.first.giftName, 'Diamond Ring');
    });

    test('Non-creator receives in-app coins but DOES NOT receive cash USD earnings', () async {
      final service = SupabaseService.instance;
      const nonCreatorUid = 'user_regular_505';
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('local_is_creator_$nonCreatorUid', false);
      service.currentProfile = const UserProfile(
        id: nonCreatorUid,
        nickname: 'CasualUser',
        coins: 50,
      );

      await service.creditReceivedGiftCoins(
        coins: 100,
        senderId: 'friend_002',
        senderName: 'Friend',
        giftName: 'Heart',
      );

      // Coins balance should increase to 150 for spending
      expect(service.currentProfile?.coins, 150);

      // But creator earnings must be empty
      final earningsList = await service.fetchCreatorEarnings();
      expect(earningsList.isEmpty, isTrue);

      final creatorWallet = await service.fetchCreatorWallet(nonCreatorUid);
      expect(creatorWallet?.availableEarningsUsd, 0.0);
    });
  });

  group('Complete Report System & Moderation Operations', () {
    test('User can submit report and admin can view in Safety & Reports', () async {
      final service = SupabaseService.instance;
      service.currentProfile = const UserProfile(
        id: 'usr_reporter_701',
        nickname: 'GoodCitizen',
      );

      await service.submitReport(
        reportedUserId: 'usr_troll_999',
        reason: 'Harassment or Hate Speech',
        details: 'User uttered offensive insults during live video match.',
        roomId: 'room_live_456',
      );

      final reports = await service.fetchUserReports(status: 'all');
      expect(reports.isNotEmpty, isTrue);
      final submitted = reports.firstWhere((r) => r.reportedId == 'usr_troll_999');
      expect(submitted.reason, 'Harassment or Hate Speech');
      expect(submitted.isPending, isTrue);
      expect(submitted.roomId, 'room_live_456');
    });

    test('Admin banning reported user sets ban status and resolves report', () async {
      final service = SupabaseService.instance;
      service.currentProfile = const UserProfile(
        id: 'admin_super_1',
        nickname: 'AdminMod',
      );

      await service.submitReport(
        reportedUserId: 'usr_spammer_888',
        reason: 'Nudity or Inappropriate Content',
        details: 'Inappropriate camera behavior',
      );

      final reports = await service.fetchUserReports(status: 'pending');
      final targetReport = reports.firstWhere((r) => r.reportedId == 'usr_spammer_888');

      // Admin resolves with 'banned'
      final resolveRes = await service.resolveUserReport(
        reportId: targetReport.id,
        action: 'banned',
        adminNotes: 'Confirmed violation of safety guidelines.',
      );

      expect(resolveRes['success'], isTrue);
      expect(resolveRes['status'], 'resolved');
      expect(resolveRes['action_taken'], 'banned');

      // Verify user is banned
      final isBanned = await service.isUserBanned('usr_spammer_888');
      expect(isBanned, isTrue);

      // Verify blocked users set includes the banned user
      final blocked = await service.fetchBlockedUsers();
      expect(blocked.contains('usr_spammer_888'), isTrue);
    });

    test('Admin restricting reported user applies temporary restriction', () async {
      final service = SupabaseService.instance;
      service.currentProfile = const UserProfile(
        id: 'admin_super_2',
        nickname: 'SafetyOfficer',
      );

      await service.submitReport(
        reportedUserId: 'usr_noisy_777',
        reason: 'Spam or Disturbance',
        details: 'Excessive spamming in chat',
      );

      final reports = await service.fetchUserReports(status: 'pending');
      final targetReport = reports.firstWhere((r) => r.reportedId == 'usr_noisy_777');

      // Admin resolves with 'suspended_24h'
      final resolveRes = await service.resolveUserReport(
        reportId: targetReport.id,
        action: 'suspended_24h',
        adminNotes: 'Suspended for 24 hours for disruptive behavior.',
      );

      expect(resolveRes['success'], isTrue);
      expect(resolveRes['status'], 'resolved');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('local_user_restricted_usr_noisy_777'), isTrue);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/models/moderation_action.dart';
import 'package:monkey_omegle_app/models/user_report.dart';
import 'package:monkey_omegle_app/services/rate_limiter.dart';
import 'package:monkey_omegle_app/services/supabase_service.dart';

void main() {
  group('UserReport Model Tests', () {
    test('UserReport parses from Supabase map correctly and checks status predicates', () {
      final map = {
        'id': 'rep-101',
        'reporter_id': 'u-alpha',
        'reported_id': 'u-bravo',
        'reason': 'Inappropriate Content / Nudity',
        'details': 'Explicit camera feed shown in room',
        'room_id': 'room-99',
        'status': 'pending',
        'action_taken': 'none',
        'created_at': '2026-11-01T04:00:00Z',
        'reporter_nickname': 'Whistleblower',
        'reported_nickname': 'OffenderUser',
      };

      final report = UserReport.fromMap(map);
      expect(report.id, 'rep-101');
      expect(report.reporterId, 'u-alpha');
      expect(report.reportedId, 'u-bravo');
      expect(report.isPending, isTrue);
      expect(report.isResolved, isFalse);
      expect(report.isUnderageFlag, isFalse);
      expect(report.reporterName, 'Whistleblower');
      expect(report.reportedName, 'OffenderUser');
      expect(report.statusDisplayName, 'Pending Review');
    });

    test('UserReport correctly identifies Underage violation flag for strict 18+ enforcement', () {
      final report1 = UserReport(
        id: 'rep-102',
        reportedId: 'u-charlie',
        reason: 'Underage User (<18)',
        createdAt: DateTime.now(),
      );

      final report2 = UserReport(
        id: 'rep-103',
        reportedId: 'u-delta',
        reason: 'Safety Concern',
        details: 'User admits to being underage in chat',
        createdAt: DateTime.now(),
      );

      expect(report1.isUnderageFlag, isTrue);
      expect(report1.riskBadgeColor, const Color(0xFFE91E63)); // High-visibility pink/red

      expect(report2.isUnderageFlag, isTrue);
      expect(report2.riskBadgeColor, const Color(0xFFE91E63));
    });

    test('UserReport formats administrative actions accurately', () {
      final report = UserReport(
        id: 'rep-104',
        reportedId: 'u-echo',
        reason: 'Financial Scam / Coin Begging',
        status: 'resolved',
        actionTaken: 'banned',
        adminNotes: 'Permanent ban executed for coin extortion',
        resolvedAt: DateTime.now(),
        createdAt: DateTime.now(),
      );

      expect(report.isResolved, isTrue);
      expect(report.isPending, isFalse);
      expect(report.actionLabel, 'Permanently Banned');
      expect(report.statusBadgeColor, const Color(0xFF4CAF50));
    });

    test('UserReport handles creator sanctions: creator_revoked and wallet_frozen', () {
      final reportRevoked = UserReport(
        id: 'rep-105',
        reportedId: 'u-foxtrot',
        reason: 'Terms violation',
        actionTaken: 'creator_revoked',
        createdAt: DateTime.now(),
      );

      final reportFrozen = UserReport(
        id: 'rep-106',
        reportedId: 'u-golf',
        reason: 'Fraudulent balance acquisition',
        actionTaken: 'wallet_frozen',
        createdAt: DateTime.now(),
      );

      expect(reportRevoked.actionLabel, 'Creator KYC Revoked');
      expect(reportFrozen.actionLabel, 'Creator Wallet Frozen');
    });
  });

  group('ModerationAction Model Tests', () {
    test('ModerationAction parses and evaluates permanence', () {
      final action = ModerationAction(
        id: 'act-01',
        targetUserId: 'u-hotel',
        adminId: 'adm-01',
        actionType: 'ban',
        reason: 'Repeated severe platform violation',
        createdAt: DateTime.now(),
      );

      expect(action.isPermanent, isTrue);
      expect(action.isExpired, isFalse);
      expect(action.displayName, 'Permanent Ban');
    });

    test('ModerationAction evaluates expiration for temporary suspension', () {
      final expiredAction = ModerationAction(
        id: 'act-02',
        targetUserId: 'u-india',
        actionType: 'suspend',
        reason: '24h cooldown',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        createdAt: DateTime.now().subtract(const Duration(hours: 24)),
      );

      final activeAction = ModerationAction(
        id: 'act-03',
        targetUserId: 'u-juliet',
        actionType: 'suspend',
        reason: '7d suspension',
        expiresAt: DateTime.now().add(const Duration(days: 3)),
        createdAt: DateTime.now(),
      );

      expect(expiredAction.isPermanent, isFalse);
      expect(expiredAction.isExpired, isTrue);
      expect(activeAction.isExpired, isFalse);
    });
  });

  group('RateLimiter Anti-Fraud & Anti-Spam Tests', () {
    setUp(() {
      RateLimiter.instance.clear();
    });

    test('RateLimiter permits actions within burst window and blocks excessive attempts', () {
      const userId = 'bot-attacker-1';

      // Send 5 gifts allowed by burst limit
      for (int i = 0; i < 5; i++) {
        expect(
          RateLimiter.instance.canSendGift(userId, maxBurst: 5, window: const Duration(seconds: 2)),
          isTrue,
        );
      }

      // 6th attempt should be blocked by anti-fraud limiter
      expect(
        RateLimiter.instance.canSendGift(userId, maxBurst: 5, window: const Duration(seconds: 2)),
        isFalse,
      );
    });

    test('RateLimiter maintains separate quotas for distinct users', () {
      const userA = 'legit-user-a';
      const userB = 'legit-user-b';

      for (int i = 0; i < 3; i++) {
        RateLimiter.instance.canSendGift(userA, maxBurst: 3);
      }

      // User A exhausted quota
      expect(RateLimiter.instance.canSendGift(userA, maxBurst: 3), isFalse);

      // User B quota is completely fresh and unaffected
      expect(RateLimiter.instance.canSendGift(userB, maxBurst: 3), isTrue);
    });

    test('RateLimiter withdrawal throttle prevents rapid payout spam', () {
      const creatorId = 'creator-payout-target';

      expect(RateLimiter.instance.canRequestWithdrawal(creatorId, maxRequests: 2), isTrue);
      expect(RateLimiter.instance.canRequestWithdrawal(creatorId, maxRequests: 2), isTrue);
      expect(RateLimiter.instance.canRequestWithdrawal(creatorId, maxRequests: 2), isFalse);
    });

    test('RateLimiter clears records cleanly on reset', () {
      const user = 'spammer';
      RateLimiter.instance.canSendGift(user, maxBurst: 1);
      expect(RateLimiter.instance.canSendGift(user, maxBurst: 1), isFalse);

      RateLimiter.instance.clear();
      expect(RateLimiter.instance.canSendGift(user, maxBurst: 1), isTrue);
    });
  });

  group('Blocklist & Matchmaking Safety Tests', () {
    test('SupabaseService blocks user and maintains local blacklist set', () async {
      const targetUserId = 'bad-actor-999';

      expect(SupabaseService.instance.isUserBlocked(targetUserId), isFalse);

      await SupabaseService.instance.blockUser(targetUserId, 'Inappropriate behavior');

      expect(SupabaseService.instance.isUserBlocked(targetUserId), isTrue);
      expect(SupabaseService.instance.blockedUserIds, contains(targetUserId));
    });
  });
}

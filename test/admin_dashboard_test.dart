import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/models/admin_audit_log.dart';
import 'package:monkey_omegle_app/models/admin_kpi_metrics.dart';
import 'package:monkey_omegle_app/models/admin_user.dart';
import 'package:monkey_omegle_app/models/creator_withdrawal.dart';

void main() {
  group('AdminKpiMetrics Model Tests', () {
    test('AdminKpiMetrics initializes with defaults', () {
      const metrics = AdminKpiMetrics();
      expect(metrics.totalUsers, 0);
      expect(metrics.activeUsers, 0);
      expect(metrics.totalCoinSalesUsd, 0.0);
      expect(metrics.formattedPlatformRevenue, '\$0.00');
    });

    test('AdminKpiMetrics parses from Supabase dictionary accurately', () {
      final map = {
        'total_users': 540,
        'active_users': 85,
        'total_coin_sales_usd': 3420.50,
        'total_coins_circulating': 1200000,
        'total_creator_earnings_usd': 2100.00,
        'total_platform_revenue_usd': 900.00,
        'pending_applications_count': 7,
        'pending_withdrawals_count': 3,
        'pending_withdrawals_usd': 145.20,
      };

      final kpi = AdminKpiMetrics.fromMap(map);
      expect(kpi.totalUsers, 540);
      expect(kpi.activeUsers, 85);
      expect(kpi.totalCoinSalesUsd, 3420.50);
      expect(kpi.formattedCoinSales, '\$3420.50');
      expect(kpi.formattedPlatformRevenue, '\$900.00');
      expect(kpi.formattedCreatorEarnings, '\$2100.00');
      expect(kpi.formattedPendingWithdrawals, '\$145.20');
      expect(kpi.pendingApplicationsCount, 7);
      expect(kpi.pendingWithdrawalsCount, 3);
    });
  });

  group('CreatorWithdrawal Model Tests', () {
    test('CreatorWithdrawal parses and validates status predicates', () {
      final withdrawal = CreatorWithdrawal(
        id: 'w-001',
        creatorId: 'c-100',
        creatorName: 'Elena Rostova',
        amountUsd: 50.00,
        feeUsd: 1.50,
        netAmountUsd: 48.50,
        payoutMethod: 'paypal',
        status: 'pending',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(withdrawal.isPending, isTrue);
      expect(withdrawal.isApproved, isFalse);
      expect(withdrawal.isCompleted, isFalse);
      expect(withdrawal.isTerminal, isFalse);
      expect(withdrawal.formattedAmount, '\$50.00');
      expect(withdrawal.formattedNetAmount, '\$48.50');
      expect(withdrawal.statusDisplayName, 'Pending Review');
    });

    test('CreatorWithdrawal handles terminal completed state', () {
      final withdrawal = CreatorWithdrawal(
        id: 'w-002',
        creatorId: 'c-100',
        creatorName: 'Elena Rostova',
        amountUsd: 100.00,
        feeUsd: 2.00,
        netAmountUsd: 98.00,
        status: 'completed',
        payoutTransactionReference: 'PAYPAL_TX_98765',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(withdrawal.isPending, isFalse);
      expect(withdrawal.isCompleted, isTrue);
      expect(withdrawal.isTerminal, isTrue);
      expect(withdrawal.statusDisplayName, 'Completed');
      expect(withdrawal.payoutTransactionReference, 'PAYPAL_TX_98765');
    });

    test('CreatorWithdrawal handles rejection state', () {
      final withdrawal = CreatorWithdrawal(
        id: 'w-003',
        creatorId: 'c-100',
        creatorName: 'Elena Rostova',
        amountUsd: 25.00,
        netAmountUsd: 25.00,
        status: 'rejected',
        adminNotes: 'Invalid bank account number',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(withdrawal.isPending, isFalse);
      expect(withdrawal.isTerminal, isTrue);
      expect(withdrawal.statusDisplayName, 'Rejected');
      expect(withdrawal.adminNotes, 'Invalid bank account number');
    });
  });

  group('AdminUser Model Tests', () {
    test('AdminUser correctly identifies admin and creator roles', () {
      final user = AdminUser(
        id: 'u-1',
        username: 'ChiefAdmin',
        gender: 'unspecified',
        country: 'Global',
        roles: const ['admin', 'creator', 'user'],
        createdAt: DateTime.now(),
      );

      expect(user.isAdmin, isTrue);
      expect(user.isCreator, isTrue);
      expect(user.isModerator, isFalse);
    });

    test('AdminUser handles regular user without elevated privileges', () {
      final user = AdminUser(
        id: 'u-2',
        username: 'RegularCaller',
        gender: 'women',
        country: 'United States',
        roles: const ['user'],
        createdAt: DateTime.now(),
      );

      expect(user.isAdmin, isFalse);
      expect(user.isCreator, isFalse);
    });
  });

  group('AdminAuditLog Model Tests', () {
    test('AdminAuditLog parses and formats human-readable action names', () {
      final log = AdminAuditLog(
        id: 'log-1',
        adminId: 'adm-9',
        action: 'review_creator_approve',
        targetType: 'creator_applications',
        targetId: 'app-55',
        details: {'user_id': 'u-99', 'status': 'approved'},
        createdAt: DateTime.now(),
      );

      expect(log.actionDisplayName, 'Approved Creator KYC');
      expect(log.targetType, 'creator_applications');
      expect(log.targetId, 'app-55');
    });
  });
}

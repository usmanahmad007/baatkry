import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/models/creator_wallet.dart';
import 'package:monkey_omegle_app/models/creator_withdrawal.dart';
import 'package:monkey_omegle_app/models/payout_account.dart';

void main() {
  group('PayoutAccount Model Tests', () {
    test('PayoutAccount parses from Supabase dictionary correctly', () {
      final map = {
        'id': 'acc-123',
        'creator_id': 'creator-456',
        'payout_method': 'paypal',
        'account_title': 'Sarah Connor',
        'account_number': 'sarah.connor@example.com',
        'is_verified': true,
        'is_primary': true,
      };

      final acc = PayoutAccount.fromMap(map);
      expect(acc.id, 'acc-123');
      expect(acc.payoutMethod, 'paypal');
      expect(acc.methodDisplayName, 'PayPal');
      expect(acc.accountTitle, 'Sarah Connor');
      expect(acc.maskedAccountNumber, 'sa***@example.com');
      expect(acc.isVerified, isTrue);
      expect(acc.isPrimary, isTrue);
    });

    test('PayoutAccount masks bank account and IBAN numbers safely', () {
      final acc = PayoutAccount(
        id: 'acc-bank-1',
        creatorId: 'c-1',
        payoutMethod: 'bank_transfer',
        accountTitle: 'John Doe',
        accountNumber: 'GB29NWBK60161331926819',
        bankName: 'NatWest',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(acc.methodDisplayName, 'Bank Transfer');
      expect(acc.maskedAccountNumber, '•••• •••• 6819');
    });

    test('PayoutAccount formats modern payment methods properly', () {
      final wise = PayoutAccount(
        id: '1',
        creatorId: 'c',
        payoutMethod: 'wise',
        accountTitle: 'Test',
        accountNumber: 'test@wise.com',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(wise.methodDisplayName, 'Wise Transfer');

      final crypto = PayoutAccount(
        id: '2',
        creatorId: 'c',
        payoutMethod: 'crypto',
        accountTitle: 'USDT TRC20',
        accountNumber: 'TXyz1234567890abcdef',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(crypto.methodDisplayName, 'Crypto USDT (TRC20)');
      expect(crypto.maskedAccountNumber, '•••• •••• cdef');
    });
  });

  group('CreatorWithdrawal Timeline and Cancellation Tests', () {
    test('CreatorWithdrawal accurately tracks timeline steps', () {
      final pending = CreatorWithdrawal(
        id: 'w-1',
        creatorId: 'c-1',
        creatorName: 'Creator',
        amountUsd: 50.0,
        netAmountUsd: 50.0,
        status: 'pending',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(pending.timelineStep, 0);
      expect(pending.canCancel, isTrue);

      final review = CreatorWithdrawal(
        id: 'w-2',
        creatorId: 'c-1',
        creatorName: 'Creator',
        amountUsd: 50.0,
        netAmountUsd: 50.0,
        status: 'under_review',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(review.timelineStep, 1);
      expect(review.canCancel, isTrue);

      final approved = CreatorWithdrawal(
        id: 'w-3',
        creatorId: 'c-1',
        creatorName: 'Creator',
        amountUsd: 50.0,
        netAmountUsd: 50.0,
        status: 'approved',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(approved.timelineStep, 2);
      expect(approved.canCancel, isFalse);

      final completed = CreatorWithdrawal(
        id: 'w-4',
        creatorId: 'c-1',
        creatorName: 'Creator',
        amountUsd: 50.0,
        netAmountUsd: 50.0,
        status: 'completed',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(completed.timelineStep, 4);
      expect(completed.canCancel, isFalse);
    });

    test('CreatorWallet withdrawal threshold and balance calculations', () {
      final wallet = CreatorWallet(
        id: 'w-100',
        creatorId: 'c-100',
        availableEarningsUsd: 45.50,
        lifetimeEarningsUsd: 120.00,
        withdrawnEarningsUsd: 74.50,
      );

      expect(wallet.canWithdraw(20.00), isTrue);
      expect(wallet.progressToMinimum(20.00), 1.0);

      // Simulating $30.00 payout deduction
      final afterRequest = wallet.copyWith(
        availableEarningsUsd: wallet.availableEarningsUsd - 30.00,
        withdrawnEarningsUsd: wallet.withdrawnEarningsUsd + 30.00,
      );
      expect(afterRequest.availableEarningsUsd, 15.50);
      expect(afterRequest.withdrawnEarningsUsd, 104.50);
      expect(afterRequest.canWithdraw(20.00), isFalse);
      expect(afterRequest.progressToMinimum(20.00), closeTo(0.775, 0.001));

      // Simulating cancellation rollback: funds restored
      final afterCancellation = afterRequest.copyWith(
        availableEarningsUsd: afterRequest.availableEarningsUsd + 30.00,
        withdrawnEarningsUsd: afterRequest.withdrawnEarningsUsd - 30.00,
      );
      expect(afterCancellation.availableEarningsUsd, 45.50);
      expect(afterCancellation.withdrawnEarningsUsd, 74.50);
      expect(afterCancellation.canWithdraw(20.00), isTrue);
    });
  });
}

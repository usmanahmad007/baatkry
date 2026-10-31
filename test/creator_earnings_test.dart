import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/models/commission_rule.dart';
import 'package:monkey_omegle_app/models/creator_earning_entry.dart';
import 'package:monkey_omegle_app/models/creator_wallet.dart';

void main() {
  group('CreatorWallet Model Tests', () {
    test('CreatorWallet initializes with separated balances', () {
      final wallet = CreatorWallet(
        id: 'cw-1',
        creatorId: 'creator-1',
        availableEarningsUsd: 140.50,
        pendingEarningsUsd: 15.00,
        lifetimeEarningsUsd: 350.00,
        withdrawnEarningsUsd: 194.50,
      );

      expect(wallet.availableEarningsUsd, 140.50);
      expect(wallet.pendingEarningsUsd, 15.00);
      expect(wallet.totalEarningsUsd, 155.50);
      expect(wallet.lifetimeEarningsUsd, 350.00);
      expect(wallet.withdrawnEarningsUsd, 194.50);
      expect(wallet.formattedAvailable, '\$140.50');
      expect(wallet.formattedLifetime, '\$350.00');
    });

    test('CreatorWallet parses from Supabase map correctly', () {
      final map = {
        'id': 'cw-2',
        'creator_id': 'u-uuid-2',
        'available_earnings_usd': 42.00,
        'pending_earnings_usd': 0.00,
        'lifetime_earnings_usd': 100.00,
        'withdrawn_earnings_usd': 58.00,
        'currency': 'USD',
      };

      final wallet = CreatorWallet.fromMap(map);
      expect(wallet.id, 'cw-2');
      expect(wallet.availableEarningsUsd, 42.00);
      expect(wallet.withdrawnEarningsUsd, 58.00);
      expect(wallet.currency, 'USD');
    });
  });

  group('CommissionRule Model & Calculation Tests', () {
    test('Standard CommissionRule implements 70/30 split and \$0.002 rate', () {
      final rule = CommissionRule.standardDefault;
      expect(rule.creatorPercentage, 0.70);
      expect(rule.platformPercentage, 0.30);
      expect(rule.coinToUsdRate, 0.002000);
      expect(rule.minWithdrawalUsd, 20.00);

      // Crown gift: 1000 coins -> $2.00 Gross
      const coins = 1000;
      final gross = rule.coinsToUsd(coins);
      expect(gross, 2.00);

      final creatorEarned = rule.calculateCreatorEarning(coins);
      expect(creatorEarned, 1.40); // 70% of $2.00

      final platformCommission = rule.calculatePlatformCommission(coins);
      expect(platformCommission, 0.60); // 30% of $2.00

      expect(creatorEarned + platformCommission, gross);
    });

    test('Super Gift calculations (5,000 coins)', () {
      final rule = CommissionRule.standardDefault;
      const coins = 5000;
      final gross = rule.coinsToUsd(coins);
      expect(gross, 10.00); // 5000 * 0.002 = $10.00

      expect(rule.calculateCreatorEarning(coins), 7.00);
      expect(rule.calculatePlatformCommission(coins), 3.00);
    });
  });

  group('CreatorEarningEntry Model Tests', () {
    test('CreatorEarningEntry parses itemized gift record', () {
      final map = {
        'id': 'ce-1',
        'creator_id': 'c-1',
        'gift_transaction_id': 'gt-1',
        'gross_amount_usd': 2.00,
        'platform_commission_usd': 0.60,
        'net_earning_usd': 1.40,
        'status': 'available',
        'gift_transactions': {
          'gift_id': 'gift_crown',
          'coins_spent': 1000,
          'sender_id': 'sender-1',
        },
      };

      final entry = CreatorEarningEntry.fromMap(map);
      expect(entry.id, 'ce-1');
      expect(entry.grossAmountUsd, 2.00);
      expect(entry.platformCommissionUsd, 0.60);
      expect(entry.netEarningUsd, 1.40);
      expect(entry.formattedNet, '+\$1.40');
      expect(entry.formattedCommission, '-\$0.60');
      expect(entry.isAvailable, true);
      expect(entry.giftName, 'Crown');
      expect(entry.giftEmoji, '👑');
      expect(entry.coins, 1000);
    });
  });
}

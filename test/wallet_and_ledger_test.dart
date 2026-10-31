import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/models/wallet.dart';
import 'package:monkey_omegle_app/models/wallet_ledger_entry.dart';
import 'package:monkey_omegle_app/models/coin_package.dart';

void main() {
  group('UserWallet Model Tests', () {
    test('UserWallet initializes correctly and calculates availableBalance', () {
      final wallet = UserWallet(
        id: 'w-123',
        userId: 'u-456',
        balance: 500,
        lockedBalance: 50,
        totalPurchased: 1000,
        totalSpent: 450,
      );

      expect(wallet.id, 'w-123');
      expect(wallet.userId, 'u-456');
      expect(wallet.balance, 500);
      expect(wallet.lockedBalance, 50);
      expect(wallet.availableBalance, 450);
      expect(wallet.totalPurchased, 1000);
      expect(wallet.totalSpent, 450);
    });

    test('UserWallet.fromMap parses Supabase JSON correctly', () {
      final map = {
        'id': 'w-uuid-1',
        'user_id': 'user-uuid-1',
        'balance': 1200,
        'locked_balance': 200,
        'total_purchased': 2000,
        'total_spent': 600,
        'created_at': '2026-11-01T00:00:00Z',
        'updated_at': '2026-11-01T01:00:00Z',
      };

      final wallet = UserWallet.fromMap(map);
      expect(wallet.id, 'w-uuid-1');
      expect(wallet.userId, 'user-uuid-1');
      expect(wallet.balance, 1200);
      expect(wallet.lockedBalance, 200);
      expect(wallet.availableBalance, 1000);
      expect(wallet.totalPurchased, 2000);
      expect(wallet.totalSpent, 600);
      expect(wallet.createdAt, isNotNull);
      expect(wallet.updatedAt, isNotNull);
    });

    test('UserWallet copyWith updates fields immutably', () {
      final wallet = UserWallet(
        id: 'w-1',
        userId: 'u-1',
        balance: 100,
      );

      final updated = wallet.copyWith(balance: 250, totalPurchased: 500);
      expect(updated.id, 'w-1');
      expect(updated.balance, 250);
      expect(updated.totalPurchased, 500);
      expect(wallet.balance, 100);
    });
  });

  group('WalletLedgerEntry Model Tests', () {
    test('WalletLedgerEntry.fromMap parses credit transactions', () {
      final map = {
        'id': 'ledger-1',
        'wallet_id': 'w-1',
        'user_id': 'u-1',
        'transaction_type': 'purchase',
        'amount': 500,
        'balance_after': 620,
        'description': 'Purchased Starter Pack (500 Coins)',
        'created_at': '2026-11-01T02:00:00Z',
      };

      final entry = WalletLedgerEntry.fromMap(map);
      expect(entry.id, 'ledger-1');
      expect(entry.type, LedgerTransactionType.purchase);
      expect(entry.amount, 500);
      expect(entry.isCredit, true);
      expect(entry.balanceAfter, 620);
      expect(entry.typeDisplayName, 'Coin Purchase');
    });

    test('WalletLedgerEntry.fromMap parses debit transactions', () {
      final map = {
        'id': 'ledger-2',
        'wallet_id': 'w-1',
        'user_id': 'u-1',
        'transaction_type': 'gift_sent',
        'amount': -100,
        'balance_after': 520,
        'description': 'Sent Diamond Gift',
        'created_at': '2026-11-01T02:05:00Z',
      };

      final entry = WalletLedgerEntry.fromMap(map);
      expect(entry.type, LedgerTransactionType.giftSent);
      expect(entry.amount, -100);
      expect(entry.isCredit, false);
      expect(entry.typeDisplayName, 'Gift Sent');
    });

    test('WalletLedgerEntry handles bonus and admin adjustments', () {
      final bonusEntry = WalletLedgerEntry.fromMap({
        'transaction_type': 'bonus',
        'amount': 120,
        'balance_after': 120,
        'description': 'Welcome 120 Coins Starter Bonus',
      });
      expect(bonusEntry.type, LedgerTransactionType.bonus);
      expect(bonusEntry.isCredit, true);

      final adminEntry = WalletLedgerEntry.fromMap({
        'transaction_type': 'admin_adjustment',
        'amount': 50,
        'balance_after': 170,
        'description': 'Customer support credit',
      });
      expect(adminEntry.type, LedgerTransactionType.adminAdjustment);
      expect(adminEntry.isCredit, true);
    });
  });

  group('CoinPackage Model Tests', () {
    test('CoinPackage parses both USD and PKR pricing', () {
      final map = {
        'id': 'pkg_popular_3500',
        'title': 'Popular Pack',
        'description': 'Great for long chats',
        'coins': 3500,
        'price_usd': 4.99,
        'price_rs': 1400,
        'badge': 'BEST VALUE',
        'is_popular': true,
        'sort_order': 3,
        'is_active': true,
      };

      final pkg = CoinPackage.fromMap(map);
      expect(pkg.id, 'pkg_popular_3500');
      expect(pkg.title, 'Popular Pack');
      expect(pkg.coins, 3500);
      expect(pkg.priceUsd, 4.99);
      expect(pkg.priceRs, 1400);
      expect(pkg.badge, 'BEST VALUE');
      expect(pkg.isPopular, true);
      expect(pkg.minutes, 58); // 3500 ~/ 60 = 58
    });

    test('CoinPackage.availablePackages has standard defaults', () {
      const packages = CoinPackage.availablePackages;
      expect(packages.length, greaterThanOrEqualTo(5));

      final starter = packages.firstWhere((p) => p.id == 'pack_starter_500');
      expect(starter.coins, 500);
      expect(starter.priceUsd, 0.99);
      expect(starter.priceRs, 280);

      final ultimate = packages.firstWhere((p) => p.id == 'pack_ultimate_18000');
      expect(ultimate.coins, 18000);
      expect(ultimate.priceUsd, 19.99);
      expect(ultimate.priceRs, 5600);
    });
  });
}

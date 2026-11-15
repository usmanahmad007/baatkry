import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/features/gift/gift_modal.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/models/virtual_gift.dart';
import 'package:monkey_omegle_app/models/wallet.dart';
import 'package:monkey_omegle_app/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Live Balance Everywhere & Gift Coin Transfer Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SupabaseService.instance.signInWithGmailDirect('alice.live@gmail.com');
      SupabaseService.instance.updateLocalCoinsInMemory(500);
    });

    test('Deducting coins updates profileStream and in-memory balance immediately', () async {
      final initialCoins = SupabaseService.instance.currentProfile?.coins ?? 500;
      expect(initialCoins, 500);

      int? streamEmittedCoins;
      final sub = SupabaseService.instance.profileStream.listen((p) {
        streamEmittedCoins = p?.coins;
      });

      // Gifter sends a Rose (25 coins)
      final gift = VirtualGift.defaultGifts[1]; // Rose (25 coins)
      expect(gift.coinPrice, 25);

      await SupabaseService.instance.sendVirtualGift(
        gift: gift,
        receiverId: 'mock_receiver_user_id',
        receiverName: 'Stranger Bob',
      );

      await Future.delayed(const Duration(milliseconds: 50));

      // Verify balance deducted on gifter account
      expect(SupabaseService.instance.currentProfile?.coins, 475);
      expect(streamEmittedCoins, 475);

      await sub.cancel();
    });

    test('Receiving a gift credits coins to recipient account and broadcasts live update', () async {
      final initialCoins = SupabaseService.instance.currentProfile?.coins ?? 500;

      int? streamEmittedCoins;
      final sub = SupabaseService.instance.profileStream.listen((p) {
        streamEmittedCoins = p?.coins;
      });

      // Recipient receives a Diamond (500 coins)
      await SupabaseService.instance.creditReceivedGiftCoins(
        coins: 500,
        senderId: 'user_alice_999',
        senderName: 'Alice',
        giftName: 'Diamond',
      );

      await Future.delayed(const Duration(milliseconds: 50));

      // Verify balance increased on receiver account
      expect(SupabaseService.instance.currentProfile?.coins, initialCoins + 500);
      expect(streamEmittedCoins, initialCoins + 500);

      await sub.cancel();
    });

    test('Wallet stream and profile stream remain in sync upon live balance changes', () async {
      UserWallet? emittedWallet;
      final sub = SupabaseService.instance.walletStream.listen((w) {
        emittedWallet = w;
      });

      SupabaseService.instance.updateLocalCoinsInMemory(750);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(SupabaseService.instance.currentProfile?.coins, 750);
      if (SupabaseService.instance.currentWallet != null) {
        expect(emittedWallet?.balance, 750);
      }

      await sub.cancel();
    });

    test('UserProfile copyWith correctly reflects live additions and deductions', () {
      const profile = UserProfile(
        id: 'u-live-test',
        nickname: 'LiveTester',
        coins: 100,
      );

      // Gifter sends 25 coin gift
      final deducted = profile.copyWith(coins: profile.coins - 25);
      expect(deducted.coins, 75);

      // Receiver receives 100 coin gift
      final credited = deducted.copyWith(coins: deducted.coins + 100);
      expect(credited.coins, 175);
    });

    test('Received gift is persisted across page reload / initialization', () async {
      final initialCoins = SupabaseService.instance.currentProfile?.coins ?? 500;

      // Credit 250 coins from received gift
      await SupabaseService.instance.creditReceivedGiftCoins(
        coins: 250,
        senderId: 'user_bob',
        senderName: 'Bob',
        giftName: 'Super Gift',
      );

      expect(SupabaseService.instance.currentProfile?.coins, initialCoins + 250);

      // Verify transaction appears in fetchWalletLedger
      final ledger = await SupabaseService.instance.fetchWalletLedger();
      expect(ledger.any((e) => e.description?.contains('Received Super Gift from Bob') ?? false), isTrue);
      expect(ledger.firstWhere((e) => e.description?.contains('Received Super Gift') ?? false).amount, 250);

      // Simulate page reload by re-initializing SupabaseService
      await SupabaseService.instance.initialize();

      // Balance must NOT be lost on reload!
      expect(SupabaseService.instance.currentProfile?.coins, initialCoins + 250);

      // Ledger must still have the transaction on reload!
      final reloadedLedger = await SupabaseService.instance.fetchWalletLedger();
      expect(reloadedLedger.any((e) => e.description?.contains('Received Super Gift from Bob') ?? false), isTrue);
    });

    testWidgets('GiftModal renders cleanly without overflow on narrow 379.4px mobile screens', (tester) async {
      tester.view.physicalSize = const Size(379.4, 700.0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: GiftModal(
                peerId: 'peer_123',
                peerName: 'Stranger Jane',
                roomId: 'room_123',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Send Gift to Stranger Jane'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

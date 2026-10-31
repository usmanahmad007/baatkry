import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/models/gift_transaction.dart';
import 'package:monkey_omegle_app/models/virtual_gift.dart';

void main() {
  group('VirtualGift Model Tests', () {
    test('defaultGifts contains all 7 specification gifts in sorted order', () {
      const gifts = VirtualGift.defaultGifts;
      expect(gifts.length, 7);

      expect(gifts[0].id, 'gift_heart');
      expect(gifts[0].name, 'Heart');
      expect(gifts[0].coinPrice, 10);
      expect(gifts[0].emoji, '❤️');

      expect(gifts[1].id, 'gift_rose');
      expect(gifts[1].name, 'Rose');
      expect(gifts[1].coinPrice, 25);
      expect(gifts[1].emoji, '🌹');

      expect(gifts[2].id, 'gift_coffee');
      expect(gifts[2].name, 'Coffee');
      expect(gifts[2].coinPrice, 50);
      expect(gifts[2].emoji, '☕');

      expect(gifts[3].id, 'gift_star');
      expect(gifts[3].name, 'Star');
      expect(gifts[3].coinPrice, 100);
      expect(gifts[3].emoji, '⭐');

      expect(gifts[4].id, 'gift_diamond');
      expect(gifts[4].name, 'Diamond');
      expect(gifts[4].coinPrice, 500);
      expect(gifts[4].emoji, '💎');

      expect(gifts[5].id, 'gift_crown');
      expect(gifts[5].name, 'Crown');
      expect(gifts[5].coinPrice, 1000);
      expect(gifts[5].emoji, '👑');

      expect(gifts[6].id, 'gift_super');
      expect(gifts[6].name, 'Super Gift');
      expect(gifts[6].coinPrice, 5000);
      expect(gifts[6].emoji, '🚀');
    });

    test('VirtualGift.fromMap parses Supabase record correctly', () {
      final map = {
        'id': 'gift_custom_gem',
        'name': 'Golden Gem',
        'coin_price': 250,
        'icon_url': 'assets/gifts/gem.png',
        'animation_url': 'assets/animations/gem.json',
        'description': 'A rare golden gem',
        'sort_order': 8,
        'is_active': true,
      };

      final gift = VirtualGift.fromMap(map);
      expect(gift.id, 'gift_custom_gem');
      expect(gift.name, 'Golden Gem');
      expect(gift.coinPrice, 250);
      expect(gift.sortOrder, 8);
      expect(gift.isActive, true);
      expect(gift.emoji, isNotEmpty);
    });
  });

  group('GiftEvent LiveKit Data Channel Tests', () {
    test('GiftEvent serializes and deserializes accurately across WebRTC', () {
      final now = DateTime.now();
      final event = GiftEvent(
        giftId: 'gift_diamond',
        giftName: 'Diamond',
        coins: 500,
        senderId: 'user_sender_123',
        senderName: 'Alice',
        receiverId: 'user_receiver_456',
        receiverName: 'Bob',
        emoji: '💎',
        transactionId: 'tx_uuid_999',
        timestamp: now,
      );

      final map = event.toMap();
      expect(map['type'], 'gift_event');
      expect(map['gift_id'], 'gift_diamond');
      expect(map['coins'], 500);
      expect(map['sender_name'], 'Alice');
      expect(map['receiver_name'], 'Bob');
      expect(map['emoji'], '💎');

      final reconstructed = GiftEvent.fromMap(map);
      expect(reconstructed.giftId, 'gift_diamond');
      expect(reconstructed.giftName, 'Diamond');
      expect(reconstructed.coins, 500);
      expect(reconstructed.senderId, 'user_sender_123');
      expect(reconstructed.receiverId, 'user_receiver_456');
      expect(reconstructed.emoji, '💎');
      expect(reconstructed.transactionId, 'tx_uuid_999');
    });

    test('GiftEvent.isSentBy identifies message ownership', () {
      final event = GiftEvent(
        giftId: 'gift_rose',
        giftName: 'Rose',
        coins: 25,
        senderId: 'my_user_id',
        senderName: 'Me',
        receiverId: 'peer_user_id',
        receiverName: 'Stranger',
        emoji: '🌹',
        timestamp: DateTime.now(),
      );

      expect(event.isSentBy('my_user_id'), true);
      expect(event.isSentBy('peer_user_id'), false);
    });
  });

  group('GiftTransaction Model Tests', () {
    test('GiftTransaction.fromMap parses financial records with creator earnings', () {
      final map = {
        'id': 'tx-1234',
        'gift_id': 'gift_crown',
        'sender_id': 'sender-uuid',
        'receiver_id': 'creator-uuid',
        'room_id': 'room-xyz',
        'coins_spent': 1000,
        'creator_earnings_usd': 1.4000,
        'platform_commission_usd': 0.6000,
        'commission_rate': 0.3000,
        'receiver_was_creator': true,
        'idempotency_key': 'idemp_key_crown_1',
        'created_at': '2026-11-01T03:00:00Z',
      };

      final tx = GiftTransaction.fromMap(map);
      expect(tx.id, 'tx-1234');
      expect(tx.giftId, 'gift_crown');
      expect(tx.coinsSpent, 1000);
      expect(tx.creatorEarningsUsd, 1.4000);
      expect(tx.platformCommissionUsd, 0.6000);
      expect(tx.commissionRate, 0.3000);
      expect(tx.receiverWasCreator, true);
      expect(tx.idempotencyKey, 'idemp_key_crown_1');
    });
  });
}

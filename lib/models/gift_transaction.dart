class GiftTransaction {
  final String id;
  final String giftId;
  final String senderId;
  final String receiverId;
  final String? roomId;
  final int coinsSpent;
  final double creatorEarningsUsd;
  final double platformCommissionUsd;
  final double commissionRate;
  final bool receiverWasCreator;
  final String idempotencyKey;
  final DateTime createdAt;

  const GiftTransaction({
    required this.id,
    required this.giftId,
    required this.senderId,
    required this.receiverId,
    this.roomId,
    required this.coinsSpent,
    this.creatorEarningsUsd = 0.0,
    this.platformCommissionUsd = 0.0,
    this.commissionRate = 0.30,
    this.receiverWasCreator = false,
    required this.idempotencyKey,
    required this.createdAt,
  });

  factory GiftTransaction.fromMap(Map<String, dynamic> map) {
    return GiftTransaction(
      id: map['id'] as String? ?? '',
      giftId: map['gift_id'] as String? ?? '',
      senderId: map['sender_id'] as String? ?? '',
      receiverId: map['receiver_id'] as String? ?? '',
      roomId: map['room_id'] as String?,
      coinsSpent: (map['coins_spent'] as num?)?.toInt() ?? 0,
      creatorEarningsUsd: (map['creator_earnings_usd'] as num?)?.toDouble() ?? 0.0,
      platformCommissionUsd: (map['platform_commission_usd'] as num?)?.toDouble() ?? 0.0,
      commissionRate: (map['commission_rate'] as num?)?.toDouble() ?? 0.30,
      receiverWasCreator: map['receiver_was_creator'] as bool? ?? false,
      idempotencyKey: map['idempotency_key'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'gift_id': giftId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'room_id': roomId,
      'coins_spent': coinsSpent,
      'creator_earnings_usd': creatorEarningsUsd,
      'platform_commission_usd': platformCommissionUsd,
      'commission_rate': commissionRate,
      'receiver_was_creator': receiverWasCreator,
      'idempotency_key': idempotencyKey,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Real-time WebRTC data-channel event delivered between call participants
class GiftEvent {
  final String giftId;
  final String giftName;
  final int coins;
  final String senderId;
  final String senderName;
  final String receiverId;
  final String receiverName;
  final String emoji;
  final String? transactionId;
  final DateTime timestamp;

  const GiftEvent({
    required this.giftId,
    required this.giftName,
    required this.coins,
    required this.senderId,
    required this.senderName,
    required this.receiverId,
    required this.receiverName,
    required this.emoji,
    this.transactionId,
    required this.timestamp,
  });

  bool isSentBy(String userId) => senderId == userId;

  Map<String, dynamic> toMap() {
    return {
      'type': 'gift_event',
      'gift_id': giftId,
      'gift_name': giftName,
      'coins': coins,
      'sender_id': senderId,
      'sender_name': senderName,
      'receiver_id': receiverId,
      'receiver_name': receiverName,
      'emoji': emoji,
      'transaction_id': transactionId,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory GiftEvent.fromMap(Map<String, dynamic> map) {
    return GiftEvent(
      giftId: map['gift_id'] as String? ?? 'gift_heart',
      giftName: map['gift_name'] as String? ?? 'Gift',
      coins: (map['coins'] as num?)?.toInt() ?? 10,
      senderId: map['sender_id'] as String? ?? '',
      senderName: map['sender_name'] as String? ?? 'Friend',
      receiverId: map['receiver_id'] as String? ?? '',
      receiverName: map['receiver_name'] as String? ?? 'Friend',
      emoji: map['emoji'] as String? ?? '🎁',
      transactionId: map['transaction_id'] as String?,
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

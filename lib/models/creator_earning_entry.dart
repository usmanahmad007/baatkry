class CreatorEarningEntry {
  final String id;
  final String creatorId;
  final String giftTransactionId;
  final double grossAmountUsd;
  final double platformCommissionUsd;
  final double netEarningUsd;
  final String status;
  final String? giftName;
  final String? giftEmoji;
  final String? senderName;
  final int? coins;
  final DateTime createdAt;

  CreatorEarningEntry({
    required this.id,
    required this.creatorId,
    required this.giftTransactionId,
    required this.grossAmountUsd,
    required this.platformCommissionUsd,
    required this.netEarningUsd,
    this.status = 'available',
    this.giftName,
    this.giftEmoji,
    this.senderName,
    this.coins,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get formattedNet => '+\$${netEarningUsd.toStringAsFixed(2)}';
  String get formattedGross => '\$${grossAmountUsd.toStringAsFixed(2)}';
  String get formattedCommission => '-\$${platformCommissionUsd.toStringAsFixed(2)}';

  bool get isAvailable => status == 'available';
  bool get isWithdrawn => status == 'withdrawn';

  factory CreatorEarningEntry.fromMap(Map<String, dynamic> map) {
    // Check joined gift_transactions if present
    final giftTx = map['gift_transactions'] as Map<String, dynamic>?;

    final giftId = giftTx != null ? giftTx['gift_id'] as String? : null;
    final coins = giftTx != null ? (giftTx['coins_spent'] as num?)?.toInt() : null;

    return CreatorEarningEntry(
      id: map['id'] as String? ?? '',
      creatorId: map['creator_id'] as String? ?? '',
      giftTransactionId: map['gift_transaction_id'] as String? ?? '',
      grossAmountUsd: (map['gross_amount_usd'] as num?)?.toDouble() ?? 0.0,
      platformCommissionUsd: (map['platform_commission_usd'] as num?)?.toDouble() ?? 0.0,
      netEarningUsd: (map['net_earning_usd'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] as String? ?? 'available',
      giftName: map['gift_name'] as String? ?? _resolveName(giftId),
      giftEmoji: map['gift_emoji'] as String? ?? _resolveEmoji(giftId),
      senderName: map['sender_name'] as String?,
      coins: coins ?? ((map['gross_amount_usd'] as num?)?.toDouble() != null ? ((map['gross_amount_usd'] as num) / 0.002).round() : 0),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'creator_id': creatorId,
      'gift_transaction_id': giftTransactionId,
      'gross_amount_usd': grossAmountUsd,
      'platform_commission_usd': platformCommissionUsd,
      'net_earning_usd': netEarningUsd,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  static String _resolveName(String? giftId) {
    if (giftId == null) return 'Virtual Gift';
    final id = giftId.toLowerCase();
    if (id.contains('heart')) return 'Heart';
    if (id.contains('rose')) return 'Rose';
    if (id.contains('coffee')) return 'Coffee';
    if (id.contains('star')) return 'Star';
    if (id.contains('diamond')) return 'Diamond';
    if (id.contains('crown')) return 'Crown';
    if (id.contains('super')) return 'Super Gift';
    return 'Virtual Gift';
  }

  static String _resolveEmoji(String? giftId) {
    if (giftId == null) return '🎁';
    final id = giftId.toLowerCase();
    if (id.contains('heart')) return '❤️';
    if (id.contains('rose')) return '🌹';
    if (id.contains('coffee')) return '☕';
    if (id.contains('star')) return '⭐';
    if (id.contains('diamond')) return '💎';
    if (id.contains('crown')) return '👑';
    if (id.contains('super')) return '🚀';
    return '🎁';
  }
}

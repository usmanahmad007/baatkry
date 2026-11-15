enum LedgerTransactionType {
  purchase,
  giftSent,
  giftReceived,
  featureUnlock,
  bonus,
  refundDeduct,
  adminAdjustment,
  unknown;

  static LedgerTransactionType fromString(String? val) {
    switch (val?.toLowerCase().trim()) {
      case 'purchase':
        return LedgerTransactionType.purchase;
      case 'gift_sent':
        return LedgerTransactionType.giftSent;
      case 'gift_received':
        return LedgerTransactionType.giftReceived;
      case 'feature_unlock':
        return LedgerTransactionType.featureUnlock;
      case 'bonus':
        return LedgerTransactionType.bonus;
      case 'refund_deduct':
        return LedgerTransactionType.refundDeduct;
      case 'admin_adjustment':
        return LedgerTransactionType.adminAdjustment;
      default:
        return LedgerTransactionType.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case LedgerTransactionType.purchase:
        return 'Coin Purchase';
      case LedgerTransactionType.giftSent:
        return 'Gift Sent';
      case LedgerTransactionType.giftReceived:
        return 'Gift Received';
      case LedgerTransactionType.featureUnlock:
        return 'VIP Feature / Chat';
      case LedgerTransactionType.bonus:
        return 'Bonus Coins';
      case LedgerTransactionType.refundDeduct:
        return 'Refund Adjustment';
      case LedgerTransactionType.adminAdjustment:
        return 'Admin Credit';
      case LedgerTransactionType.unknown:
        return 'Transaction';
    }
  }

  bool get isCredit {
    switch (this) {
      case LedgerTransactionType.purchase:
      case LedgerTransactionType.bonus:
      case LedgerTransactionType.adminAdjustment:
      case LedgerTransactionType.giftReceived:
        return true;
      case LedgerTransactionType.giftSent:
      case LedgerTransactionType.featureUnlock:
      case LedgerTransactionType.refundDeduct:
      case LedgerTransactionType.unknown:
        return false;
    }
  }
}

class WalletLedgerEntry {
  final String id;
  final String walletId;
  final String userId;
  final LedgerTransactionType type;
  final int amount; // positive for credits, negative for debits
  final int balanceAfter;
  final String? referenceId;
  final String? description;
  final String? idempotencyKey;
  final DateTime createdAt;

  WalletLedgerEntry({
    required this.id,
    required this.walletId,
    required this.userId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.referenceId,
    this.description,
    this.idempotencyKey,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isPositive => amount > 0;
  bool get isCredit => type.isCredit || amount > 0;
  String get typeDisplayName => type.displayName;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'wallet_id': walletId,
      'user_id': userId,
      'transaction_type': type.name,
      'type': type.name,
      'amount': amount,
      'balance_after': balanceAfter,
      'reference_id': referenceId,
      'description': description,
      'idempotency_key': idempotencyKey,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory WalletLedgerEntry.fromMap(Map<String, dynamic> map) {
    return WalletLedgerEntry(
      id: map['id'] as String? ?? '',
      walletId: map['wallet_id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      type: LedgerTransactionType.fromString(
        map['transaction_type'] as String? ?? map['type'] as String?,
      ),
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      balanceAfter: (map['balance_after'] as num?)?.toInt() ?? 0,
      referenceId: map['reference_id'] as String?,
      description: map['description'] as String?,
      idempotencyKey: map['idempotency_key'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

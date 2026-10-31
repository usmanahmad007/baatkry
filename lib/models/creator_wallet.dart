class CreatorWallet {
  final String id;
  final String creatorId;
  final double availableEarningsUsd;
  final double pendingEarningsUsd;
  final double lifetimeEarningsUsd;
  final double withdrawnEarningsUsd;
  final String currency;
  final DateTime createdAt;
  final DateTime updatedAt;

  CreatorWallet({
    required this.id,
    required this.creatorId,
    this.availableEarningsUsd = 0.0,
    this.pendingEarningsUsd = 0.0,
    this.lifetimeEarningsUsd = 0.0,
    this.withdrawnEarningsUsd = 0.0,
    this.currency = 'USD',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  double get totalEarningsUsd => availableEarningsUsd + pendingEarningsUsd;

  String get formattedAvailable => '\$${availableEarningsUsd.toStringAsFixed(2)}';
  String get formattedPending => '\$${pendingEarningsUsd.toStringAsFixed(2)}';
  String get formattedLifetime => '\$${lifetimeEarningsUsd.toStringAsFixed(2)}';
  String get formattedWithdrawn => '\$${withdrawnEarningsUsd.toStringAsFixed(2)}';

  CreatorWallet copyWith({
    String? id,
    String? creatorId,
    double? availableEarningsUsd,
    double? pendingEarningsUsd,
    double? lifetimeEarningsUsd,
    double? withdrawnEarningsUsd,
    String? currency,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CreatorWallet(
      id: id ?? this.id,
      creatorId: creatorId ?? this.creatorId,
      availableEarningsUsd: availableEarningsUsd ?? this.availableEarningsUsd,
      pendingEarningsUsd: pendingEarningsUsd ?? this.pendingEarningsUsd,
      lifetimeEarningsUsd: lifetimeEarningsUsd ?? this.lifetimeEarningsUsd,
      withdrawnEarningsUsd: withdrawnEarningsUsd ?? this.withdrawnEarningsUsd,
      currency: currency ?? this.currency,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory CreatorWallet.fromMap(Map<String, dynamic> map) {
    return CreatorWallet(
      id: map['id'] as String? ?? '',
      creatorId: map['creator_id'] as String? ?? '',
      availableEarningsUsd: (map['available_earnings_usd'] as num?)?.toDouble() ?? 0.0,
      pendingEarningsUsd: (map['pending_earnings_usd'] as num?)?.toDouble() ?? 0.0,
      lifetimeEarningsUsd: (map['lifetime_earnings_usd'] as num?)?.toDouble() ?? 0.0,
      withdrawnEarningsUsd: (map['withdrawn_earnings_usd'] as num?)?.toDouble() ?? 0.0,
      currency: map['currency'] as String? ?? 'USD',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'creator_id': creatorId,
      'available_earnings_usd': availableEarningsUsd,
      'pending_earnings_usd': pendingEarningsUsd,
      'lifetime_earnings_usd': lifetimeEarningsUsd,
      'withdrawn_earnings_usd': withdrawnEarningsUsd,
      'currency': currency,
    };
  }
}

class CommissionRule {
  final String id;
  final String name;
  final double creatorPercentage;
  final double platformPercentage;
  final double coinToUsdRate;
  final double minWithdrawalUsd;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CommissionRule({
    required this.id,
    this.name = 'Standard Commission Tier',
    this.creatorPercentage = 0.70,
    this.platformPercentage = 0.30,
    this.coinToUsdRate = 0.002000, // 500 coins = $1.00 USD
    this.minWithdrawalUsd = 20.00,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  String get creatorPercentString => '${(creatorPercentage * 100).toStringAsFixed(0)}%';
  String get platformPercentString => '${(platformPercentage * 100).toStringAsFixed(0)}%';
  double get creatorSharePercentage => creatorPercentage * 100;
  double get platformSharePercentage => platformPercentage * 100;
  double get minimumWithdrawalAmountUsd => minWithdrawalUsd;
  double get coinConversionRateUsd => coinToUsdRate;
  String get formattedMinWithdrawal => '\$${minWithdrawalUsd.toStringAsFixed(2)}';

  double coinsToUsd(int coins) => coins * coinToUsdRate;

  double calculateCreatorEarning(int coins) {
    final gross = coinsToUsd(coins);
    return gross * creatorPercentage;
  }

  double calculatePlatformCommission(int coins) {
    final gross = coinsToUsd(coins);
    return gross * platformPercentage;
  }

  factory CommissionRule.fromMap(Map<String, dynamic> map) {
    return CommissionRule(
      id: map['id'] as String? ?? 'rule_default',
      name: map['name'] as String? ?? 'Standard Commission Tier',
      creatorPercentage: (map['creator_percentage'] as num?)?.toDouble() ?? 0.70,
      platformPercentage: (map['platform_percentage'] as num?)?.toDouble() ?? 0.30,
      coinToUsdRate: (map['coin_to_usd_rate'] as num?)?.toDouble() ?? 0.002000,
      minWithdrawalUsd: (map['min_withdrawal_usd'] as num?)?.toDouble() ?? 20.00,
      isActive: map['is_active'] as bool? ?? true,
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
      'name': name,
      'creator_percentage': creatorPercentage,
      'platform_percentage': platformPercentage,
      'coin_to_usd_rate': coinToUsdRate,
      'min_withdrawal_usd': minWithdrawalUsd,
      'is_active': isActive,
    };
  }

  static final CommissionRule standardDefault = CommissionRule(
    id: 'rule_standard',
    name: 'Standard Commission Tier',
    creatorPercentage: 0.70,
    platformPercentage: 0.30,
    coinToUsdRate: 0.002000,
    minWithdrawalUsd: 20.00,
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

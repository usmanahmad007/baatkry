class CoinPackage {
  final String id;
  final String title;
  final String description;
  final int coins;
  final int minutes;
  final int priceRs;
  final double priceUsd;
  final String? badge;
  final bool isPopular;
  final bool isActive;
  final int sortOrder;

  const CoinPackage({
    required this.id,
    required this.title,
    required this.description,
    required this.coins,
    required this.minutes,
    required this.priceRs,
    this.priceUsd = 0.99,
    this.badge,
    this.isPopular = false,
    this.isActive = true,
    this.sortOrder = 0,
  });

  String get name => title;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': title,
      'description': description,
      'coins': coins,
      'price_usd': priceUsd,
      'price_rs': priceRs,
      'badge': badge,
      'is_popular': isPopular,
      'is_active': isActive,
      'sort_order': sortOrder,
    };
  }

  factory CoinPackage.fromMap(Map<String, dynamic> map) {
    final coins = (map['coins'] as num?)?.toInt() ?? 500;
    final minutes = (coins / 60).round();
    final priceUsd = (map['price_usd'] as num?)?.toDouble() ?? 0.99;
    final priceRs = (map['price_rs'] as num?)?.toInt() ?? (priceUsd * 280).round();

    return CoinPackage(
      id: map['id'] as String? ?? 'pack_custom',
      title: map['name'] as String? ?? map['title'] as String? ?? 'Coin Package',
      description: map['description'] as String? ?? '$coins Virtual Coins for video chats & gifts.',
      coins: coins,
      minutes: minutes > 0 ? minutes : 1,
      priceRs: priceRs,
      priceUsd: priceUsd,
      badge: map['badge'] as String?,
      isPopular: map['is_popular'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? true,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  // Fallback defaults matching database seed
  static const List<CoinPackage> availablePackages = [
    CoinPackage(
      id: 'pack_starter_500',
      title: 'Starter Pack',
      description: '500 Virtual Coins for video chats & gifts',
      minutes: 8,
      coins: 500,
      priceUsd: 0.99,
      priceRs: 280,
      sortOrder: 1,
    ),
    CoinPackage(
      id: 'pack_basic_1200',
      title: 'Basic Pack',
      description: '1,200 Virtual Coins + Bonus',
      minutes: 20,
      coins: 1200,
      priceUsd: 1.99,
      priceRs: 560,
      sortOrder: 2,
    ),
    CoinPackage(
      id: 'pack_popular_3500',
      title: 'Popular Pack',
      description: '3,500 Virtual Coins (Most Selected)',
      minutes: 58,
      coins: 3500,
      priceUsd: 4.99,
      priceRs: 1400,
      badge: 'POPULAR',
      isPopular: true,
      sortOrder: 3,
    ),
    CoinPackage(
      id: 'pack_premium_8000',
      title: 'Premium VIP',
      description: '8,000 Coins + Gold VIP status badge',
      minutes: 133,
      coins: 8000,
      priceUsd: 9.99,
      priceRs: 2800,
      badge: 'VIP DEAL',
      sortOrder: 4,
    ),
    CoinPackage(
      id: 'pack_ultimate_18000',
      title: 'Ultimate King',
      description: '18,000 Coins + Crown badge & priority match',
      minutes: 300,
      coins: 18000,
      priceUsd: 19.99,
      priceRs: 5600,
      badge: 'BEST VALUE',
      sortOrder: 5,
    ),
    // Backward compatibility for existing PKR packages
    CoinPackage(
      id: 'pack_500_rs',
      title: 'Starter Pack (PKR)',
      description: '60 Minutes (1 Hour) of direct gender-filtered video chat (1 coin/sec).',
      minutes: 60,
      coins: 3600,
      priceUsd: 1.79,
      priceRs: 500,
      badge: 'MIN DEPOSIT',
      sortOrder: 6,
    ),
    CoinPackage(
      id: 'pack_1000_rs',
      title: 'Popular VIP (PKR)',
      description: '130 Minutes (120 mins + 10 Bonus mins) with priority matchmaking.',
      minutes: 130,
      coins: 7800,
      priceUsd: 3.57,
      priceRs: 1000,
      badge: 'POPULAR',
      isPopular: true,
      sortOrder: 7,
    ),
  ];
}

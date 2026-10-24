class CoinPackage {
  final String id;
  final String title;
  final String description;
  final int coins; // 1 coin = 1 second (20 Rs = 1 min = 60 coins)
  final int minutes;
  final int priceRs; // In Rupees (Minimum 500 Rs)
  final String? badge;
  final bool isPopular;

  const CoinPackage({
    required this.id,
    required this.title,
    required this.description,
    required this.coins,
    required this.minutes,
    required this.priceRs,
    this.badge,
    this.isPopular = false,
  });

  // Pricing Rule: 20 Rs = 1 Minute (1 Coin = 1 Second of Gender-Filtered Chat)
  // Minimum Deposit: 500 Rs (25 minutes = 1,500 coins)
  static const List<CoinPackage> availablePackages = [
    CoinPackage(
      id: 'pack_500_rs',
      title: 'Starter Pack',
      description: '25 Minutes of direct gender-filtered video chat (1 coin/sec).',
      minutes: 25,
      coins: 1500, // 25 mins * 60s
      priceRs: 500,
      badge: 'MIN DEPOSIT',
    ),
    CoinPackage(
      id: 'pack_1000_rs',
      title: 'Popular VIP',
      description: '55 Minutes (50 mins + 5 Bonus mins) with priority matchmaking.',
      minutes: 55,
      coins: 3300, // 55 mins * 60s
      priceRs: 1000,
      badge: 'POPULAR',
      isPopular: true,
    ),
    CoinPackage(
      id: 'pack_2500_rs',
      title: 'Pro VIP Pass',
      description: '150 Minutes (125 mins + 25 Bonus mins) + Gold VIP Badge.',
      minutes: 150,
      coins: 9000, // 150 mins * 60s
      priceRs: 2500,
      badge: 'VIP DEAL',
    ),
    CoinPackage(
      id: 'pack_5000_rs',
      title: 'King VIP Access',
      description: '350 Minutes (250 mins + 100 Bonus) + Instant match + Crown badge.',
      minutes: 350,
      coins: 21000, // 350 mins * 60s
      priceRs: 5000,
      badge: 'BEST VALUE',
    ),
  ];
}

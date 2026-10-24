class CoinPackage {
  final String id;
  final String title;
  final String description;
  final int coins; // 1 coin = 1 second of gender-filtered chat
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

  // Minimum Deposit: 500 Rs (60 minutes = 3,600 coins)
  // 1 Coin = 1 Second of Gender-Filtered Video Chat
  static const List<CoinPackage> availablePackages = [
    CoinPackage(
      id: 'pack_500_rs',
      title: 'Starter Pack',
      description: '60 Minutes (1 Hour) of direct gender-filtered video chat (1 coin/sec).',
      minutes: 60,
      coins: 3600, // 60 mins * 60s
      priceRs: 500,
      badge: 'MIN DEPOSIT',
    ),
    CoinPackage(
      id: 'pack_1000_rs',
      title: 'Popular VIP',
      description: '130 Minutes (120 mins + 10 Bonus mins) with priority matchmaking.',
      minutes: 130,
      coins: 7800, // 130 mins * 60s
      priceRs: 1000,
      badge: 'POPULAR',
      isPopular: true,
    ),
    CoinPackage(
      id: 'pack_2500_rs',
      title: 'Pro VIP Pass',
      description: '350 Minutes (300 mins + 50 Bonus mins) + Gold VIP Badge.',
      minutes: 350,
      coins: 21000, // 350 mins * 60s
      priceRs: 2500,
      badge: 'VIP DEAL',
    ),
    CoinPackage(
      id: 'pack_5000_rs',
      title: 'King VIP Access',
      description: '800 Minutes (600 mins + 200 Bonus) + Instant match + Crown badge.',
      minutes: 800,
      coins: 48000, // 800 mins * 60s
      priceRs: 5000,
      badge: 'BEST VALUE',
    ),
  ];
}

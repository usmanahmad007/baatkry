class VirtualGift {
  final String id;
  final String name;
  final int coinPrice;
  final String iconUrl;
  final String? animationUrl;
  final String description;
  final int sortOrder;
  final bool isActive;
  final String emoji;
  final String? badge;

  const VirtualGift({
    required this.id,
    required this.name,
    required this.coinPrice,
    required this.iconUrl,
    this.animationUrl,
    required this.description,
    this.sortOrder = 0,
    this.isActive = true,
    required this.emoji,
    this.badge,
  });

  factory VirtualGift.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String? ?? 'gift_heart';
    final name = map['name'] as String? ?? 'Gift';
    final coins = (map['coin_price'] as num?)?.toInt() ?? (map['coins'] as num?)?.toInt() ?? 10;
    final iconUrl = map['icon_url'] as String? ?? 'assets/gifts/heart.png';
    final animationUrl = map['animation_url'] as String?;
    final description = map['description'] as String? ?? 'Send a virtual gift in chat';
    final sortOrder = (map['sort_order'] as num?)?.toInt() ?? 0;
    final isActive = map['is_active'] as bool? ?? true;

    return VirtualGift(
      id: id,
      name: name,
      coinPrice: coins,
      iconUrl: iconUrl,
      animationUrl: animationUrl,
      description: description,
      sortOrder: sortOrder,
      isActive: isActive,
      emoji: _resolveEmoji(id, name),
      badge: _resolveBadge(id, coins),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'coin_price': coinPrice,
      'icon_url': iconUrl,
      'animation_url': animationUrl,
      'description': description,
      'sort_order': sortOrder,
      'is_active': isActive,
    };
  }

  static String _resolveEmoji(String id, String name) {
    final key = id.toLowerCase() + name.toLowerCase();
    if (key.contains('heart')) return '❤️';
    if (key.contains('rose')) return '🌹';
    if (key.contains('coffee')) return '☕';
    if (key.contains('star')) return '⭐';
    if (key.contains('diamond')) return '💎';
    if (key.contains('crown')) return '👑';
    if (key.contains('super')) return '🚀';
    return '🎁';
  }

  static String? _resolveBadge(String id, int coins) {
    if (coins >= 5000) return 'SUPREME';
    if (coins >= 1000) return 'KING';
    if (coins >= 500) return 'LUXURY';
    if (coins == 100) return 'HOT';
    if (coins == 25) return 'POPULAR';
    return null;
  }

  /// Default Virtual Gifts Catalogue as specified in Section 4.B
  static const List<VirtualGift> defaultGifts = [
    VirtualGift(
      id: 'gift_heart',
      name: 'Heart',
      coinPrice: 10,
      iconUrl: 'assets/gifts/heart.png',
      animationUrl: 'assets/animations/heart.json',
      description: 'Send love and sweet vibes',
      sortOrder: 1,
      emoji: '❤️',
      badge: 'SWEET',
    ),
    VirtualGift(
      id: 'gift_rose',
      name: 'Rose',
      coinPrice: 25,
      iconUrl: 'assets/gifts/rose.png',
      animationUrl: 'assets/animations/rose.json',
      description: 'A fresh blooming red rose',
      sortOrder: 2,
      emoji: '🌹',
      badge: 'POPULAR',
    ),
    VirtualGift(
      id: 'gift_coffee',
      name: 'Coffee',
      coinPrice: 50,
      iconUrl: 'assets/gifts/coffee.png',
      animationUrl: 'assets/animations/coffee.json',
      description: 'Treat them to a warm coffee',
      sortOrder: 3,
      emoji: '☕',
    ),
    VirtualGift(
      id: 'gift_star',
      name: 'Star',
      coinPrice: 100,
      iconUrl: 'assets/gifts/star.png',
      animationUrl: 'assets/animations/star.json',
      description: 'Make them shine bright',
      sortOrder: 4,
      emoji: '⭐',
      badge: 'HOT',
    ),
    VirtualGift(
      id: 'gift_diamond',
      name: 'Diamond',
      coinPrice: 500,
      iconUrl: 'assets/gifts/diamond.png',
      animationUrl: 'assets/animations/diamond.json',
      description: 'Sparkling luxury gemstone',
      sortOrder: 5,
      emoji: '💎',
      badge: 'LUXURY',
    ),
    VirtualGift(
      id: 'gift_crown',
      name: 'Crown',
      coinPrice: 1000,
      iconUrl: 'assets/gifts/crown.png',
      animationUrl: 'assets/animations/crown.json',
      description: 'Crown them king or queen',
      sortOrder: 6,
      emoji: '👑',
      badge: 'KING',
    ),
    VirtualGift(
      id: 'gift_super',
      name: 'Super Gift',
      coinPrice: 5000,
      iconUrl: 'assets/gifts/super_gift.png',
      animationUrl: 'assets/animations/super_gift.json',
      description: 'Ultimate fireworks rocket explosion',
      sortOrder: 7,
      emoji: '🚀',
      badge: 'SUPREME',
    ),
  ];
}

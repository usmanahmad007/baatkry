class CreatorProfile {
  final String id;
  final String displayName;
  final String? bio;
  final String? avatarUrl;
  final String? bannerUrl;
  final String category;
  final bool isVerified;
  final int totalGiftsReceived;
  final int totalCallMinutes;
  final int followerCount;
  final Map<String, dynamic> socialLinks;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CreatorProfile({
    required this.id,
    required this.displayName,
    this.bio,
    this.avatarUrl,
    this.bannerUrl,
    this.category = 'General',
    this.isVerified = false,
    this.totalGiftsReceived = 0,
    this.totalCallMinutes = 0,
    this.followerCount = 0,
    this.socialLinks = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory CreatorProfile.fromMap(Map<String, dynamic> map) {
    return CreatorProfile(
      id: map['id'] as String? ?? '',
      displayName: map['display_name'] as String? ?? 'Verified Creator',
      bio: map['bio'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      bannerUrl: map['banner_url'] as String?,
      category: map['category'] as String? ?? 'General',
      isVerified: map['is_verified'] as bool? ?? false,
      totalGiftsReceived: (map['total_gifts_received'] as num?)?.toInt() ?? 0,
      totalCallMinutes: (map['total_call_minutes'] as num?)?.toInt() ?? 0,
      followerCount: (map['follower_count'] as num?)?.toInt() ?? 0,
      socialLinks: (map['social_links'] as Map?)?.cast<String, dynamic>() ?? const {},
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
      'display_name': displayName,
      'bio': bio,
      'avatar_url': avatarUrl,
      'banner_url': bannerUrl,
      'category': category,
      'is_verified': isVerified,
      'total_gifts_received': totalGiftsReceived,
      'total_call_minutes': totalCallMinutes,
      'follower_count': followerCount,
      'social_links': socialLinks,
    };
  }
}

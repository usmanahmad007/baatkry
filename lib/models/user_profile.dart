class UserProfile {
  final String id;
  final bool isAnonymous;
  final String nickname;
  final String? avatarUrl;
  final String gender; // 'men', 'women', 'transgender', 'unspecified'
  final List<String> interests;
  final int coins;
  final bool isVip;
  final String status;

  const UserProfile({
    required this.id,
    this.isAnonymous = true,
    this.nickname = 'Anonymous Monkey',
    this.avatarUrl,
    this.gender = 'unspecified',
    this.interests = const [],
    this.coins = 50,
    this.isVip = false,
    this.status = 'online',
  });

  UserProfile copyWith({
    String? id,
    bool? isAnonymous,
    String? nickname,
    String? avatarUrl,
    String? gender,
    List<String>? interests,
    int? coins,
    bool? isVip,
    String? status,
  }) {
    return UserProfile(
      id: id ?? this.id,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      gender: gender ?? this.gender,
      interests: interests ?? this.interests,
      coins: coins ?? this.coins,
      isVip: isVip ?? this.isVip,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'is_anonymous': isAnonymous,
      'nickname': nickname,
      'avatar_url': avatarUrl,
      'gender': gender,
      'interests': interests,
      'coins': coins,
      'is_vip': isVip,
      'status': status,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String? ?? '',
      isAnonymous: map['is_anonymous'] as bool? ?? true,
      nickname: map['nickname'] as String? ?? 'Anonymous Monkey',
      avatarUrl: map['avatar_url'] as String?,
      gender: map['gender'] as String? ?? 'unspecified',
      interests: (map['interests'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      coins: map['coins'] as int? ?? 50,
      isVip: map['is_vip'] as bool? ?? false,
      status: map['status'] as String? ?? 'online',
    );
  }
}

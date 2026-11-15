class UserProfile {
  final String id;
  final bool isAnonymous;
  final String nickname;
  final String? username;
  final DateTime? usernameUpdatedAt;
  final String? avatarUrl;
  final String gender; // 'men', 'women', 'transgender', 'unspecified'
  final List<String> interests;
  final int coins;
  final bool isVip;
  final DateTime? vipExpiresAt;
  final String status;
  final int? age;
  final bool isAgeVerified;
  final String? birthDate;
  final String country;
  final String countryCode;
  final int dailyClaimStreak;
  final DateTime? lastDailyClaimAt;

  const UserProfile({
    required this.id,
    this.isAnonymous = true,
    this.nickname = 'Anonymous Explorer',
    this.username,
    this.usernameUpdatedAt,
    this.avatarUrl,
    this.gender = 'unspecified',
    this.interests = const [],
    this.coins = 120, // 120 coins initial signup bonus (2 minutes of gender-filtered chat)
    this.isVip = false,
    this.vipExpiresAt,
    this.status = 'online',
    this.age,
    this.isAgeVerified = false,
    this.birthDate,
    this.country = 'Global (Worldwide)',
    this.countryCode = 'ALL',
    this.dailyClaimStreak = 0,
    this.lastDailyClaimAt,
  });

  bool get isGenderSet => gender != 'unspecified' && gender.isNotEmpty;
  bool get hasUsername => username != null && username!.trim().isNotEmpty;
  bool get hasDob => birthDate != null && birthDate!.trim().isNotEmpty;
  bool get needsProfileCompletion => !isAnonymous && (!hasUsername || !hasDob);

  /// Daily Free Coins rewards schedule: Day 1: 50, Day 2: 100 ... Day 7: 350
  static const List<int> dailyRewards = [50, 100, 150, 200, 250, 300, 350];

  /// A user cannot change their username for 7 days after setting it.
  bool get canChangeUsername {
    if (username == null || username!.trim().isEmpty) return true;
    if (usernameUpdatedAt == null) return true;
    return DateTime.now().difference(usernameUpdatedAt!).inDays >= 7;
  }

  /// Days remaining before the username can be changed.
  int get daysUntilUsernameChange {
    if (canChangeUsername || usernameUpdatedAt == null) return 0;
    final diffInSeconds = DateTime.now().difference(usernameUpdatedAt!).inSeconds;
    final remainingSeconds = (7 * 86400) - diffInSeconds;
    if (remainingSeconds <= 0) return 0;
    return (remainingSeconds / 86400).ceil();
  }

  int get dailyStreak => dailyClaimStreak;

  /// Check if user can claim today's daily free coins reward
  bool get canClaimDailyReward {
    if (lastDailyClaimAt == null) return true;
    final now = DateTime.now();
    final last = lastDailyClaimAt!.toLocal();
    if (now.year == last.year && now.month == last.month && now.day == last.day) {
      return false; // Already claimed today
    }
    return true;
  }

  /// Next streak day to claim (1 to 7)
  int get nextDailyRewardDay {
    if (lastDailyClaimAt == null) return 1;
    final now = DateTime.now();
    final last = lastDailyClaimAt!.toLocal();

    // Same day -> current streak
    if (now.year == last.year && now.month == last.month && now.day == last.day) {
      return dailyClaimStreak > 0 ? dailyClaimStreak : 1;
    }

    // Yesterday -> consecutive claim advances
    final yesterday = now.subtract(const Duration(days: 1));
    if (yesterday.year == last.year && yesterday.month == last.month && yesterday.day == last.day) {
      final next = dailyClaimStreak + 1;
      return next > 7 ? 1 : next;
    }

    // Missed a day -> reset to Day 1
    return 1;
  }

  /// Next coins amount to claim (50, 100, 150, 200, 250, 300, 350)
  int get nextDailyRewardCoins {
    final day = nextDailyRewardDay;
    return day * 50;
  }

  /// VIP badge is valid for 30 days (1 month). If expired, user must renew.
  bool get isVipActive {
    if (!isVip) return false;
    if (vipExpiresAt == null) return true;
    return DateTime.now().isBefore(vipExpiresAt!);
  }

  int get vipDaysRemaining {
    if (!isVipActive || vipExpiresAt == null) return 0;
    final diff = vipExpiresAt!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    final days = (diff.inSeconds / 86400).ceil();
    return days > 0 ? days : 1;
  }

  String get displayUsername {
    if (hasUsername) {
      final clean = username!.trim().toLowerCase().replaceAll('@', '');
      return '@$clean';
    }
    final cleanNick = nickname.trim().toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    return '@${cleanNick.isNotEmpty ? cleanNick : displayId}';
  }

  String get displayId {
    if (id.isEmpty) return '117705886';
    final numericOnly = id.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericOnly.length >= 8) {
      return numericOnly.substring(0, 9.clamp(0, numericOnly.length));
    }
    final hash = id.hashCode.abs().toString().padLeft(9, '0');
    return hash.substring(0, 9);
  }

  String get genderDisplayName {
    switch (gender.toLowerCase()) {
      case 'men':
      case 'male':
        return 'Male 👨';
      case 'women':
      case 'female':
        return 'Female 👩';
      case 'transgender':
      case 'other':
        return 'Other ⚧';
      default:
        return 'Not Set';
    }
  }

  UserProfile copyWith({
    String? id,
    bool? isAnonymous,
    String? nickname,
    String? username,
    DateTime? usernameUpdatedAt,
    bool clearUsernameUpdatedAt = false,
    String? avatarUrl,
    String? gender,
    List<String>? interests,
    int? coins,
    bool? isVip,
    DateTime? vipExpiresAt,
    bool clearVipExpiry = false,
    String? status,
    int? age,
    bool? isAgeVerified,
    String? birthDate,
    String? country,
    String? countryCode,
    int? dailyClaimStreak,
    DateTime? lastDailyClaimAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      nickname: nickname ?? this.nickname,
      username: username ?? this.username,
      usernameUpdatedAt: clearUsernameUpdatedAt ? null : (usernameUpdatedAt ?? this.usernameUpdatedAt),
      avatarUrl: avatarUrl ?? this.avatarUrl,
      gender: gender ?? this.gender,
      interests: interests ?? this.interests,
      coins: coins ?? this.coins,
      isVip: isVip ?? this.isVip,
      vipExpiresAt: clearVipExpiry ? null : (vipExpiresAt ?? this.vipExpiresAt),
      status: status ?? this.status,
      age: age ?? this.age,
      isAgeVerified: isAgeVerified ?? this.isAgeVerified,
      birthDate: birthDate ?? this.birthDate,
      country: country ?? this.country,
      countryCode: countryCode ?? this.countryCode,
      dailyClaimStreak: dailyClaimStreak ?? this.dailyClaimStreak,
      lastDailyClaimAt: lastDailyClaimAt ?? this.lastDailyClaimAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'is_anonymous': isAnonymous,
      'nickname': nickname,
      'username': username,
      'username_updated_at': usernameUpdatedAt?.toIso8601String(),
      'avatar_url': avatarUrl,
      'gender': gender,
      'interests': interests,
      'coins': coins,
      'is_vip': isVip,
      'vip_expires_at': vipExpiresAt?.toIso8601String(),
      'status': status,
      'age': age,
      'is_age_verified': isAgeVerified,
      'birth_date': birthDate,
      'date_of_birth': birthDate,
      'country': country,
      'country_code': countryCode,
      'daily_claim_streak': dailyClaimStreak,
      'last_daily_claim_at': lastDailyClaimAt?.toIso8601String(),
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    final rawDob = (map['birth_date'] ?? map['date_of_birth'])?.toString();
    final rawAge = map['age'] as int?;
    final verified = map['is_age_verified'] as bool? ??
        (rawDob != null || (rawAge != null && rawAge >= 18));

    final rawVipExpiry = map['vip_expires_at'] != null
        ? DateTime.tryParse(map['vip_expires_at'].toString())
        : null;
    final rawIsVip = map['is_vip'] as bool? ?? false;
    final isVipEffective = rawIsVip && (rawVipExpiry == null || DateTime.now().isBefore(rawVipExpiry));

    final rawUsernameUpdatedAt = map['username_updated_at'] != null
        ? DateTime.tryParse(map['username_updated_at'].toString())
        : null;
    final rawDailyClaimAt = map['last_daily_claim_at'] != null
        ? DateTime.tryParse(map['last_daily_claim_at'].toString())
        : null;
    final rawDailyStreak = map['daily_claim_streak'] as int? ?? 0;

    final rawInterests = (map['interests'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    String? resolvedUsername = map['username']?.toString();
    if (resolvedUsername == null || resolvedUsername.isEmpty) {
      for (final tag in rawInterests) {
        if (tag.startsWith('uname:')) {
          resolvedUsername = tag.replaceFirst('uname:', '');
          break;
        }
      }
    }

    return UserProfile(
      id: map['id'] as String? ?? '',
      isAnonymous: map['is_anonymous'] as bool? ?? true,
      nickname: map['nickname'] as String? ??
          map['full_name'] as String? ??
          map['name'] as String? ??
          'Anonymous Explorer',
      username: resolvedUsername,
      usernameUpdatedAt: rawUsernameUpdatedAt,
      avatarUrl: (map['avatar_url'] ?? map['picture']) as String?,
      gender: map['gender'] as String? ?? 'unspecified',
      interests: rawInterests,
      coins: map['coins'] as int? ?? 120,
      isVip: isVipEffective,
      vipExpiresAt: rawVipExpiry,
      status: map['status'] as String? ?? 'online',
      age: rawAge,
      isAgeVerified: verified,
      birthDate: rawDob,
      country: map['country'] as String? ?? 'Global (Worldwide)',
      countryCode: map['country_code'] as String? ?? 'ALL',
      dailyClaimStreak: rawDailyStreak,
      lastDailyClaimAt: rawDailyClaimAt,
    );
  }
}

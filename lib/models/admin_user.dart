/// User representation for administrative oversight and role management
class AdminUser {
  final String id;
  final String username;
  final String? email;
  final String? avatarUrl;
  final String gender;
  final String country;
  final int coins;
  final bool isBanned;
  final String? banReason;
  final bool isRestricted;
  final String? restrictionReason;
  final String? restrictionType; // 'chat_mute', 'camera_disabled', 'matchmaking_cooldown', 'shadow_flagged'
  final DateTime? restrictedUntil;
  final bool isVip;
  final int reportsCount;
  final List<String> roles;
  final DateTime createdAt;
  final DateTime? lastActiveAt;

  const AdminUser({
    required this.id,
    required this.username,
    this.email,
    this.avatarUrl,
    required this.gender,
    required this.country,
    this.coins = 0,
    this.isBanned = false,
    this.banReason,
    this.isRestricted = false,
    this.restrictionReason,
    this.restrictionType,
    this.restrictedUntil,
    this.isVip = false,
    this.reportsCount = 0,
    this.roles = const ['user'],
    required this.createdAt,
    this.lastActiveAt,
  });

  bool get isAdmin => roles.contains('admin') || roles.contains('super_admin');
  bool get isCreator => roles.contains('creator');
  bool get isModerator => roles.contains('moderator');

  bool get isCurrentlyRestricted =>
      isRestricted && (restrictedUntil == null || restrictedUntil!.isAfter(DateTime.now()));

  String get restrictionDisplayName {
    if (!isCurrentlyRestricted) return 'None';
    switch (restrictionType) {
      case 'chat_mute':
        return 'Chat Muted 🔇';
      case 'camera_disabled':
        return 'Camera Disabled 📷';
      case 'matchmaking_cooldown':
        return 'Cooldown ⏳';
      case 'shadow_flagged':
        return 'Flagged ⚠️';
      default:
        return 'Restricted ⚠️';
    }
  }

  AdminUser copyWith({
    String? id,
    String? username,
    String? email,
    String? avatarUrl,
    String? gender,
    String? country,
    int? coins,
    bool? isBanned,
    String? banReason,
    bool? isRestricted,
    String? restrictionReason,
    String? restrictionType,
    DateTime? restrictedUntil,
    bool? isVip,
    int? reportsCount,
    List<String>? roles,
    DateTime? createdAt,
    DateTime? lastActiveAt,
  }) {
    return AdminUser(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      gender: gender ?? this.gender,
      country: country ?? this.country,
      coins: coins ?? this.coins,
      isBanned: isBanned ?? this.isBanned,
      banReason: banReason ?? this.banReason,
      isRestricted: isRestricted ?? this.isRestricted,
      restrictionReason: restrictionReason ?? this.restrictionReason,
      restrictionType: restrictionType ?? this.restrictionType,
      restrictedUntil: restrictedUntil ?? this.restrictedUntil,
      isVip: isVip ?? this.isVip,
      reportsCount: reportsCount ?? this.reportsCount,
      roles: roles ?? this.roles,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }

  factory AdminUser.fromMap(Map<String, dynamic> map) {
    List<String> parsedRoles = ['user'];
    if (map['user_roles'] is List) {
      final roleList = (map['user_roles'] as List)
          .map((r) => r is Map ? r['role']?.toString() : r?.toString())
          .whereType<String>()
          .toList();
      if (roleList.isNotEmpty) {
        parsedRoles = roleList;
      }
    }

    return AdminUser(
      id: map['id']?.toString() ?? '',
      username: map['username'] as String? ?? 'Anonymous',
      email: map['email'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      gender: map['gender'] as String? ?? 'unspecified',
      country: map['country'] as String? ?? 'Global',
      coins: (map['coins'] as num?)?.toInt() ?? 0,
      isBanned: map['is_banned'] as bool? ?? false,
      banReason: map['ban_reason'] as String?,
      isRestricted: map['is_restricted'] as bool? ?? false,
      restrictionReason: map['restriction_reason'] as String?,
      restrictionType: map['restriction_type'] as String?,
      restrictedUntil: map['restricted_until'] != null
          ? DateTime.tryParse(map['restricted_until'].toString())
          : null,
      isVip: map['is_vip'] as bool? ?? false,
      reportsCount: (map['reports_count'] as num?)?.toInt() ?? 0,
      roles: parsedRoles,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      lastActiveAt: map['last_active_at'] != null
          ? DateTime.tryParse(map['last_active_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'avatar_url': avatarUrl,
      'gender': gender,
      'country': country,
      'coins': coins,
      'is_banned': isBanned,
      'ban_reason': banReason,
      'is_restricted': isRestricted,
      'restriction_reason': restrictionReason,
      'restriction_type': restrictionType,
      'restricted_until': restrictedUntil?.toIso8601String(),
      'is_vip': isVip,
      'reports_count': reportsCount,
      'roles': roles,
      'created_at': createdAt.toIso8601String(),
      'last_active_at': lastActiveAt?.toIso8601String(),
    };
  }
}

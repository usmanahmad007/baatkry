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
    this.roles = const ['user'],
    required this.createdAt,
    this.lastActiveAt,
  });

  bool get isAdmin => roles.contains('admin') || roles.contains('super_admin');
  bool get isCreator => roles.contains('creator');
  bool get isModerator => roles.contains('moderator');

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
      'roles': roles,
      'created_at': createdAt.toIso8601String(),
      'last_active_at': lastActiveAt?.toIso8601String(),
    };
  }
}

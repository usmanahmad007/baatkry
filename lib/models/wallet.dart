class UserWallet {
  final String id;
  final String userId;
  final int balance;
  final int lockedBalance;
  final int totalPurchased;
  final int totalSpent;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserWallet({
    required this.id,
    required this.userId,
    required this.balance,
    this.lockedBalance = 0,
    this.totalPurchased = 0,
    this.totalSpent = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  int get availableBalance => balance > lockedBalance ? balance - lockedBalance : 0;

  UserWallet copyWith({
    String? id,
    String? userId,
    int? balance,
    int? lockedBalance,
    int? totalPurchased,
    int? totalSpent,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserWallet(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      balance: balance ?? this.balance,
      lockedBalance: lockedBalance ?? this.lockedBalance,
      totalPurchased: totalPurchased ?? this.totalPurchased,
      totalSpent: totalSpent ?? this.totalSpent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'balance': balance,
      'locked_balance': lockedBalance,
      'total_purchased': totalPurchased,
      'total_spent': totalSpent,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory UserWallet.fromMap(Map<String, dynamic> map) {
    return UserWallet(
      id: map['id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      balance: (map['balance'] as num?)?.toInt() ?? 0,
      lockedBalance: (map['locked_balance'] as num?)?.toInt() ?? 0,
      totalPurchased: (map['total_purchased'] as num?)?.toInt() ?? 0,
      totalSpent: (map['total_spent'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

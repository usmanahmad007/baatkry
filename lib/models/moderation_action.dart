/// Represents an administrative moderation action record
class ModerationAction {
  final String id;
  final String targetUserId;
  final String? adminId;
  final String actionType; // 'ban', 'unban', 'suspend', 'unsuspend', 'revoke_creator', 'freeze_wallet', 'unfreeze_wallet', 'warn', 'dismiss'
  final String reason;
  final String? adminNotes;
  final DateTime? expiresAt;
  final DateTime createdAt;

  const ModerationAction({
    required this.id,
    required this.targetUserId,
    this.adminId,
    required this.actionType,
    required this.reason,
    this.adminNotes,
    this.expiresAt,
    required this.createdAt,
  });

  bool get isPermanent => expiresAt == null;
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  String get displayName {
    switch (actionType) {
      case 'ban':
        return 'Permanent Ban';
      case 'suspend':
        return 'Account Suspension';
      case 'revoke_creator':
        return 'Revoke Creator Status';
      case 'freeze_wallet':
        return 'Freeze Creator Wallet';
      case 'warn':
        return 'Official Warning';
      case 'dismiss':
        return 'Dismissal';
      default:
        return actionType;
    }
  }

  factory ModerationAction.fromMap(Map<String, dynamic> map) {
    return ModerationAction(
      id: map['id']?.toString() ?? '',
      targetUserId: map['target_user_id']?.toString() ?? '',
      adminId: map['admin_id']?.toString(),
      actionType: map['action_type']?.toString() ?? 'warn',
      reason: map['reason']?.toString() ?? '',
      adminNotes: map['admin_notes']?.toString(),
      expiresAt: map['expires_at'] != null
          ? DateTime.tryParse(map['expires_at'].toString())
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'target_user_id': targetUserId,
      'admin_id': adminId,
      'action_type': actionType,
      'reason': reason,
      'admin_notes': adminNotes,
      'expires_at': expiresAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

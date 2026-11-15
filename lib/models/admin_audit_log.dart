/// Immutable Administrative Action Audit Log Entry
class AdminAuditLog {
  final String id;
  final String adminId;
  final String action;
  final String targetType;
  final String targetId;
  final Map<String, dynamic> details;
  final String? ipAddress;
  final DateTime createdAt;

  const AdminAuditLog({
    required this.id,
    required this.adminId,
    required this.action,
    required this.targetType,
    required this.targetId,
    this.details = const {},
    this.ipAddress,
    required this.createdAt,
  });

  String get actionDisplayName {
    switch (action) {
      case 'review_creator_approve':
        return 'Approved Creator KYC';
      case 'review_creator_reject':
        return 'Rejected Creator KYC';
      case 'review_withdrawal_approve':
        return 'Approved Withdrawal';
      case 'review_withdrawal_complete':
        return 'Settled Payout';
      case 'review_withdrawal_reject':
        return 'Rejected Withdrawal';
      case 'ban_user':
        return 'Banned User Account';
      case 'unban_user':
        return 'Unbanned User Account';
      case 'restrict_user':
        return 'Restricted User Account';
      case 'lift_restriction':
        return 'Lifted User Restriction';
      case 'adjust_coins':
        return 'Adjusted User Coins';
      case 'toggle_vip':
        return 'Updated VIP Status';
      case 'reset_gender_lock':
        return 'Reset Gender Lock';
      case 'update_gift_pricing':
        return 'Updated Gift Pricing';
      case 'update_coin_package':
        return 'Updated Coin Package';
      case 'update_commission_rule':
        return 'Updated Commission Rule';
      default:
        return action.replaceAll('_', ' ').toUpperCase();
    }
  }

  factory AdminAuditLog.fromMap(Map<String, dynamic> map) {
    return AdminAuditLog(
      id: map['id']?.toString() ?? '',
      adminId: map['admin_id']?.toString() ?? '',
      action: map['action'] as String? ?? 'action',
      targetType: map['target_type'] as String? ?? '',
      targetId: map['target_id']?.toString() ?? '',
      details: map['details'] is Map ? Map<String, dynamic>.from(map['details'] as Map) : {},
      ipAddress: map['ip_address'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'admin_id': adminId,
      'action': action,
      'target_type': targetType,
      'target_id': targetId,
      'details': details,
      'ip_address': ipAddress,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

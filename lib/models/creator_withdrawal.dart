/// Creator withdrawal payout request model
class CreatorWithdrawal {
  final String id;
  final String creatorId;
  final String creatorName;
  final String? creatorEmail;
  final double amountUsd;
  final double feeUsd;
  final double netAmountUsd;
  final String payoutMethod;
  final Map<String, dynamic> payoutDetails;
  final String status;
  final String? adminNotes;
  final String? payoutTransactionReference;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CreatorWithdrawal({
    required this.id,
    required this.creatorId,
    required this.creatorName,
    this.creatorEmail,
    required this.amountUsd,
    this.feeUsd = 0.0,
    required this.netAmountUsd,
    this.payoutMethod = 'paypal',
    this.payoutDetails = const {},
    this.status = 'pending',
    this.adminNotes,
    this.payoutTransactionReference,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPending => status == 'pending' || status == 'under_review';
  bool get isApproved => status == 'approved' || status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get isRejected => status == 'rejected' || status == 'failed';
  bool get isTerminal => status == 'completed' || status == 'rejected' || status == 'failed' || status == 'cancelled';
  bool get canCancel => isPending;

  int get timelineStep {
    switch (status.toLowerCase()) {
      case 'pending':
        return 0;
      case 'under_review':
        return 1;
      case 'approved':
        return 2;
      case 'processing':
        return 3;
      case 'completed':
        return 4;
      default:
        return -1;
    }
  }

  String get formattedAmount => '\$${amountUsd.toStringAsFixed(2)}';
  String get formattedNetAmount => '\$${netAmountUsd.toStringAsFixed(2)}';
  String get formattedFee => '\$${feeUsd.toStringAsFixed(2)}';

  String get statusDisplayName {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending Review';
      case 'under_review':
        return 'Under Review';
      case 'approved':
        return 'Approved';
      case 'processing':
        return 'Processing Payout';
      case 'completed':
        return 'Completed';
      case 'rejected':
        return 'Rejected';
      case 'failed':
        return 'Failed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.toUpperCase();
    }
  }

  factory CreatorWithdrawal.fromMap(Map<String, dynamic> map) {
    // Creator profile join if present
    final creatorProfile = map['profiles'] as Map<String, dynamic>?;
    final fallbackName = creatorProfile != null
        ? (creatorProfile['username'] as String? ?? 'Creator')
        : 'Creator';

    return CreatorWithdrawal(
      id: map['id']?.toString() ?? '',
      creatorId: map['creator_id']?.toString() ?? '',
      creatorName: map['creator_name'] as String? ?? fallbackName,
      creatorEmail: map['creator_email'] as String?,
      amountUsd: (map['amount_usd'] as num?)?.toDouble() ?? 0.0,
      feeUsd: (map['fee_usd'] as num?)?.toDouble() ?? 0.0,
      netAmountUsd: (map['net_payout_amount'] as num?)?.toDouble() ??
          ((map['net_amount_usd'] as num?)?.toDouble() ??
              ((map['amount_usd'] as num?)?.toDouble() ?? 0.0)),
      payoutMethod: map['payout_method'] as String? ??
          (map['payout_accounts'] != null && map['payout_accounts'] is Map
              ? (map['payout_accounts']['payout_method'] as String? ?? 'paypal')
              : 'paypal'),
      payoutDetails: map['payout_details'] is Map
          ? Map<String, dynamic>.from(map['payout_details'] as Map)
          : (map['payout_accounts'] is Map
              ? Map<String, dynamic>.from(map['payout_accounts'] as Map)
              : {}),
      status: map['status'] as String? ?? 'pending',
      adminNotes: map['admin_notes'] as String?,
      payoutTransactionReference: map['payout_transaction_reference'] as String?,
      reviewedBy: map['reviewed_by'] as String?,
      reviewedAt: map['reviewed_at'] != null
          ? DateTime.tryParse(map['reviewed_at'].toString())
          : null,
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
      'creator_id': creatorId,
      'creator_name': creatorName,
      'creator_email': creatorEmail,
      'amount_usd': amountUsd,
      'fee_usd': feeUsd,
      'net_amount_usd': netAmountUsd,
      'payout_method': payoutMethod,
      'payout_details': payoutDetails,
      'status': status,
      'admin_notes': adminNotes,
      'payout_transaction_reference': payoutTransactionReference,
      'reviewed_by': reviewedBy,
      'reviewed_at': reviewedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

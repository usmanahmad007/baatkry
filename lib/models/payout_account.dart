/// Beneficiary payout account for receiving creator earnings
class PayoutAccount {
  final String id;
  final String creatorId;
  final String payoutMethod;
  final String accountTitle;
  final String accountNumber;
  final String? bankName;
  final String? routingCode;
  final bool isVerified;
  final bool isPrimary;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PayoutAccount({
    required this.id,
    required this.creatorId,
    required this.payoutMethod,
    required this.accountTitle,
    required this.accountNumber,
    this.bankName,
    this.routingCode,
    this.isVerified = false,
    this.isPrimary = true,
    required this.createdAt,
    required this.updatedAt,
  });

  String get methodDisplayName {
    switch (payoutMethod.toLowerCase()) {
      case 'paypal':
        return 'PayPal';
      case 'bank_transfer':
        return 'Bank Transfer';
      case 'iban':
        return 'International Bank (IBAN)';
      case 'wise':
        return 'Wise Transfer';
      case 'payoneer':
        return 'Payoneer';
      case 'crypto':
      case 'usdt':
        return 'Crypto USDT (TRC20)';
      case 'jazzcash':
        return 'JazzCash';
      case 'easypaisa':
        return 'EasyPaisa';
      default:
        return payoutMethod.toUpperCase();
    }
  }

  String get maskedAccountNumber {
    if (accountNumber.contains('@')) {
      // Email masking: e.g. j***@domain.com
      final parts = accountNumber.split('@');
      if (parts[0].length <= 2) return '${parts[0][0]}***@${parts[1]}';
      return '${parts[0].substring(0, 2)}***@${parts[1]}';
    }
    if (accountNumber.length <= 4) return accountNumber;
    final last4 = accountNumber.substring(accountNumber.length - 4);
    return '•••• •••• $last4';
  }

  factory PayoutAccount.fromMap(Map<String, dynamic> map) {
    return PayoutAccount(
      id: map['id']?.toString() ?? '',
      creatorId: map['creator_id']?.toString() ?? '',
      payoutMethod: map['payout_method'] as String? ?? 'paypal',
      accountTitle: map['account_title'] as String? ?? '',
      accountNumber: map['account_number'] as String? ?? '',
      bankName: map['bank_name'] as String?,
      routingCode: map['routing_code'] as String?,
      isVerified: map['is_verified'] as bool? ?? false,
      isPrimary: map['is_primary'] as bool? ?? true,
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
      'payout_method': payoutMethod,
      'account_title': accountTitle,
      'account_number': accountNumber,
      'bank_name': bankName,
      'routing_code': routingCode,
      'is_verified': isVerified,
      'is_primary': isPrimary,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

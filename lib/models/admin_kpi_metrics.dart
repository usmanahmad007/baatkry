/// Data model for platform-wide Key Performance Indicators and financial summaries
class AdminKpiMetrics {
  final int totalUsers;
  final int activeUsers;
  final double totalCoinSalesUsd;
  final int totalCoinsCirculating;
  final double totalCreatorEarningsUsd;
  final double totalPlatformRevenueUsd;
  final int pendingApplicationsCount;
  final int pendingWithdrawalsCount;
  final double pendingWithdrawalsUsd;

  const AdminKpiMetrics({
    this.totalUsers = 0,
    this.activeUsers = 0,
    this.totalCoinSalesUsd = 0.0,
    this.totalCoinsCirculating = 0,
    this.totalCreatorEarningsUsd = 0.0,
    this.totalPlatformRevenueUsd = 0.0,
    this.pendingApplicationsCount = 0,
    this.pendingWithdrawalsCount = 0,
    this.pendingWithdrawalsUsd = 0.0,
  });

  String get formattedCoinSales => '\$${totalCoinSalesUsd.toStringAsFixed(2)}';
  String get formattedPlatformRevenue => '\$${totalPlatformRevenueUsd.toStringAsFixed(2)}';
  String get formattedCreatorEarnings => '\$${totalCreatorEarningsUsd.toStringAsFixed(2)}';
  String get formattedPendingWithdrawals => '\$${pendingWithdrawalsUsd.toStringAsFixed(2)}';

  factory AdminKpiMetrics.fromMap(Map<String, dynamic> map) {
    return AdminKpiMetrics(
      totalUsers: (map['total_users'] as num?)?.toInt() ?? 0,
      activeUsers: (map['active_users'] as num?)?.toInt() ?? 0,
      totalCoinSalesUsd: (map['total_coin_sales_usd'] as num?)?.toDouble() ?? 0.0,
      totalCoinsCirculating: (map['total_coins_circulating'] as num?)?.toInt() ?? 0,
      totalCreatorEarningsUsd: (map['total_creator_earnings_usd'] as num?)?.toDouble() ?? 0.0,
      totalPlatformRevenueUsd: (map['total_platform_revenue_usd'] as num?)?.toDouble() ?? 0.0,
      pendingApplicationsCount: (map['pending_applications_count'] as num?)?.toInt() ?? 0,
      pendingWithdrawalsCount: (map['pending_withdrawals_count'] as num?)?.toInt() ?? 0,
      pendingWithdrawalsUsd: (map['pending_withdrawals_usd'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'total_users': totalUsers,
      'active_users': activeUsers,
      'total_coin_sales_usd': totalCoinSalesUsd,
      'total_coins_circulating': totalCoinsCirculating,
      'total_creator_earnings_usd': totalCreatorEarningsUsd,
      'total_platform_revenue_usd': totalPlatformRevenueUsd,
      'pending_applications_count': pendingApplicationsCount,
      'pending_withdrawals_count': pendingWithdrawalsCount,
      'pending_withdrawals_usd': pendingWithdrawalsUsd,
    };
  }
}

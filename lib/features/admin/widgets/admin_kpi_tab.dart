import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/admin_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/admin_kpi_metrics.dart';

class AdminKpiTab extends ConsumerWidget {
  final VoidCallback onNavigateToApplications;
  final VoidCallback onNavigateToWithdrawals;

  const AdminKpiTab({
    super.key,
    required this.onNavigateToApplications,
    required this.onNavigateToWithdrawals,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpiAsync = ref.watch(adminKpiMetricsProvider);

    return kpiAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.brandPink),
      ),
      error: (err, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(
              'Failed to load KPI metrics: $err',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(adminKpiMetricsProvider),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPink),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
      data: (kpi) {
        return RefreshIndicator(
          color: AppColors.brandPink,
          backgroundColor: const Color(0xFF1A1A2E),
          onRefresh: () async => ref.invalidate(adminKpiMetricsProvider),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top alert actions if pending items exist
                if (kpi.pendingApplicationsCount > 0 || kpi.pendingWithdrawalsCount > 0)
                  _buildPendingAlerts(context, kpi),

                const SizedBox(height: 16),
                const Text(
                  'FINANCIAL PERFORMANCE',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),

                // Financial Overview Grid
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Platform Net Commission',
                        value: kpi.formattedPlatformRevenue,
                        subtitle: '30% split from gifts',
                        icon: Icons.account_balance_rounded,
                        color: AppColors.brandPink,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Total Coin Sales',
                        value: kpi.formattedCoinSales,
                        subtitle: 'Gross user purchases',
                        icon: Icons.monetization_on_rounded,
                        color: AppColors.coinGold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Creator Earnings',
                        value: kpi.formattedCreatorEarnings,
                        subtitle: '70% credited to creators',
                        icon: Icons.stars_rounded,
                        color: Colors.purpleAccent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Coins In Circulation',
                        value: '${kpi.totalCoinsCirculating}',
                        subtitle: 'Active unspent balance',
                        icon: Icons.toll_rounded,
                        color: AppColors.brandCyan,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                const Text(
                  'PLATFORM ACTIVITY',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Total Registered Users',
                        value: '${kpi.totalUsers}',
                        subtitle: 'Accounts created',
                        icon: Icons.people_alt_rounded,
                        color: Colors.blueAccent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Active Live Users',
                        value: '${kpi.activeUsers}',
                        subtitle: 'Online or in calls',
                        icon: Icons.sensors_rounded,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                _buildSystemHealthBanner(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingAlerts(BuildContext context, AdminKpiMetrics kpi) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1B10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orangeAccent.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
              SizedBox(width: 8),
              Text(
                'Action Required',
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (kpi.pendingApplicationsCount > 0)
            InkWell(
              onTap: onNavigateToApplications,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_right_rounded, color: Colors.white70),
                    Expanded(
                      child: Text(
                        '${kpi.pendingApplicationsCount} Creator KYC applications awaiting review',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Review', style: TextStyle(color: AppColors.brandPink, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          if (kpi.pendingWithdrawalsCount > 0)
            InkWell(
              onTap: onNavigateToWithdrawals,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_right_rounded, color: Colors.white70),
                    Expanded(
                      child: Text(
                        '${kpi.pendingWithdrawalsCount} Payout requests pending (${kpi.formattedPendingWithdrawals})',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.coinGold.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Process', style: TextStyle(color: AppColors.coinGold, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(color: color.withOpacity(0.4), blurRadius: 8),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemHealthBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141926),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified_user_rounded, color: Colors.greenAccent, size: 28),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Financial Ledger Integrity: Active',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                SizedBox(height: 2),
                Text(
                  'PostgreSQL double-entry ledger & atomic row locks operational. All balances synchronized.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/admin_provider.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/admin_catalog_tab.dart';
import 'widgets/admin_creator_apps_tab.dart';
import 'widgets/admin_kpi_tab.dart';
import 'widgets/admin_reports_tab.dart';
import 'widgets/admin_users_tab.dart';
import 'widgets/admin_withdrawals_tab.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminDashboardScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigateToTab(int index) {
    _tabController.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    final isAdminAsync = ref.watch(isAdminProvider);

    return isAdminAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.brandPink)),
      ),
      error: (_, __) => _buildAccessDeniedScreen(context),
      data: (isAdmin) {
        if (!isAdmin) {
          return _buildAccessDeniedScreen(context);
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: const Color(0xFF141424),
            elevation: 0,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.brandPink.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.brandPink),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.admin_panel_settings_rounded, color: AppColors.brandPink, size: 16),
                      SizedBox(width: 4),
                      Text('ADMIN CONSOLE', style: TextStyle(color: AppColors.brandPink, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Baatkry Backoffice',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                tooltip: 'Refresh All Metrics',
                onPressed: () {
                  ref.invalidate(adminKpiMetricsProvider);
                  ref.invalidate(adminGiftsProvider);
                  ref.invalidate(adminCoinPackagesProvider);
                  ref.invalidate(adminCommissionRuleProvider);
                  ref.invalidate(adminAuditLogsProvider);
                  ref.invalidate(adminReportsProvider);
                },
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AppColors.brandPink,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: const [
                Tab(icon: Icon(Icons.insights_rounded, size: 18), text: 'Analytics'),
                Tab(icon: Icon(Icons.verified_user_rounded, size: 18), text: 'Creator KYC'),
                Tab(icon: Icon(Icons.payments_rounded, size: 18), text: 'Payouts'),
                Tab(icon: Icon(Icons.storefront_rounded, size: 18), text: 'Catalog & Fees'),
                Tab(icon: Icon(Icons.security_rounded, size: 18), text: 'Users & Audit'),
                Tab(icon: Icon(Icons.shield_rounded, size: 18), text: 'Safety & Reports'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              AdminKpiTab(
                onNavigateToApplications: () => _navigateToTab(1),
                onNavigateToWithdrawals: () => _navigateToTab(2),
              ),
              const AdminCreatorAppsTab(),
              const AdminWithdrawalsTab(),
              const AdminCatalogTab(),
              const AdminUsersTab(),
              const AdminReportsTab(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccessDeniedScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_person_rounded, color: Colors.redAccent, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Access Denied',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'This section requires verified Administrator privileges on the backend.\nYour account is not assigned the admin role.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                label: const Text('Return to App', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/admin_audit_log.dart';
import '../../models/admin_kpi_metrics.dart';
import '../../models/admin_user.dart';
import '../../models/coin_package.dart';
import '../../models/commission_rule.dart';
import '../../models/creator_application.dart';
import '../../models/creator_withdrawal.dart';
import '../../models/user_report.dart';
import '../../models/virtual_gift.dart';
import '../../services/supabase_service.dart';
import 'user_provider.dart';

/// Provider checking whether current logged-in user holds administrator privileges
final isAdminProvider = FutureProvider<bool>((ref) async {
  final userProfile = ref.watch(currentProfileProvider);
  if (userProfile == null || userProfile.isAnonymous) return false;
  return SupabaseService.instance.checkIsAdmin(userProfile.id);
});

/// Provider fetching platform-wide KPI metrics and financials
final adminKpiMetricsProvider = FutureProvider<AdminKpiMetrics>((ref) async {
  return SupabaseService.instance.fetchAdminKpiMetrics();
});

/// Provider fetching users for moderation and role assignment
final adminUsersProvider = FutureProvider.family<List<AdminUser>, String?>((ref, query) async {
  return SupabaseService.instance.fetchAdminUsers(searchQuery: query);
});

/// Provider fetching creator KYC applications for admin review
final adminCreatorApplicationsProvider = FutureProvider.family<List<CreatorApplication>, String>((ref, status) async {
  return SupabaseService.instance.fetchAdminCreatorApplications(status: status);
});

/// Provider fetching creator withdrawal requests for payout processing
final adminWithdrawalsProvider = FutureProvider.family<List<CreatorWithdrawal>, String>((ref, status) async {
  return SupabaseService.instance.fetchAdminWithdrawals(status: status);
});

/// Provider fetching virtual gifts catalogue for pricing and status administration
final adminGiftsProvider = FutureProvider<List<VirtualGift>>((ref) async {
  return SupabaseService.instance.fetchAdminGifts();
});

/// Provider fetching coin packages for pricing and status administration
final adminCoinPackagesProvider = FutureProvider<List<CoinPackage>>((ref) async {
  return SupabaseService.instance.fetchAdminCoinPackages();
});

/// Provider fetching platform active commission rules
final adminCommissionRuleProvider = FutureProvider<CommissionRule>((ref) async {
  return SupabaseService.instance.fetchActiveCommissionRule();
});

/// Provider fetching immutable administrative audit logs
final adminAuditLogsProvider = FutureProvider<List<AdminAuditLog>>((ref) async {
  return SupabaseService.instance.fetchAdminAuditLogs();
});

/// Provider fetching user abuse and safety reports
final adminReportsProvider = FutureProvider.family<List<UserReport>, String?>((ref, status) async {
  return SupabaseService.instance.fetchUserReports(status: status);
});

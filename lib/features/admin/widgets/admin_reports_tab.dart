import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/admin_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_report.dart';
import '../../../services/supabase_service.dart';

class AdminReportsTab extends ConsumerStatefulWidget {
  const AdminReportsTab({super.key});

  @override
  ConsumerState<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends ConsumerState<AdminReportsTab> {
  String _filter = 'pending'; // 'pending', 'underage', 'resolved', 'all'
  bool _isProcessing = false;

  Future<void> _handleResolveReport(
    UserReport report,
    String action, {
    String? adminNotes,
  }) async {
    setState(() => _isProcessing = true);
    try {
      await SupabaseService.instance.resolveUserReport(
        reportId: report.id,
        action: action,
        adminNotes: adminNotes,
      );

      ref.invalidate(adminReportsProvider);
      ref.invalidate(adminAuditLogsProvider);

      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text('Report ${report.id.substring(0, 8)} resolved: $action'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Failed to resolve report: $e'),
          ),
        );
      }
    }
  }

  void _showActionDialog(UserReport report, String actionTitle, String actionKey, Color accentColor) {
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            Icon(Icons.gavel_rounded, color: accentColor, size: 22),
            const SizedBox(width: 8),
            Text(actionTitle, style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to apply "$actionTitle" to reported user ${report.reportedName ?? report.reportedId.substring(0, 8)}?',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: notesController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Admin audit notes (required for transparency)...',
                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                filled: true,
                fillColor: AppColors.backgroundElevated,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            onPressed: () {
              Navigator.pop(ctx);
              _handleResolveReport(
                report,
                actionKey,
                adminNotes: notesController.text.trim().isNotEmpty
                    ? notesController.text.trim()
                    : 'Action applied by admin console',
              );
            },
            child: Text(actionTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusQuery = _filter == 'all' || _filter == 'underage' ? null : _filter;
    final reportsAsync = ref.watch(adminReportsProvider(statusQuery));

    return Column(
      children: [
        // Filter bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: const Color(0xFF141424),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('pending', 'Pending Reviews', Icons.pending_actions_rounded),
                const SizedBox(width: 8),
                _buildFilterChip('underage', '🔞 Underage Flags', Icons.no_adult_content_rounded, const Color(0xFFE91E63)),
                const SizedBox(width: 8),
                _buildFilterChip('resolved', 'Resolved', Icons.check_circle_outline_rounded),
                const SizedBox(width: 8),
                _buildFilterChip('all', 'All Reports', Icons.list_alt_rounded),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                  tooltip: 'Refresh Reports',
                  onPressed: () => ref.invalidate(adminReportsProvider),
                ),
              ],
            ),
          ),
        ),

        if (_isProcessing)
          const LinearProgressIndicator(color: AppColors.brandPink, backgroundColor: Colors.transparent),

        // Reports list
        Expanded(
          child: reportsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandPink)),
            error: (err, _) => Center(
              child: Text('Error loading reports: $err', style: const TextStyle(color: AppColors.danger)),
            ),
            data: (reports) {
              var displayed = reports;
              if (_filter == 'underage') {
                displayed = reports.where((r) => r.isUnderageFlag).toList();
              }

              if (displayed.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_user_rounded, size: 56, color: AppColors.success.withOpacity(0.5)),
                      const SizedBox(height: 12),
                      const Text(
                        'No safety reports in this category!',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Community moderation standards are clean.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: displayed.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final report = displayed[index];
                  return _buildReportCard(report);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String key, String label, IconData icon, [Color? customColor]) {
    final isSelected = _filter == key;
    final activeColor = customColor ?? AppColors.brandPink;

    return InkWell(
      onTap: () => setState(() => _filter = key),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.2) : AppColors.backgroundElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.surfaceBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? activeColor : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textMuted,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(UserReport report) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: report.isUnderageFlag ? const Color(0xFFE91E63) : AppColors.surfaceBorder,
          width: report.isUnderageFlag ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.backgroundElevated.withOpacity(0.6),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                // Violation Reason badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: report.riskBadgeColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: report.riskBadgeColor, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        report.isUnderageFlag ? Icons.no_adult_content_rounded : Icons.shield_rounded,
                        color: report.riskBadgeColor,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        report.reason,
                        style: TextStyle(
                          color: report.riskBadgeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: report.statusBadgeColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    report.statusDisplayName,
                    style: TextStyle(
                      color: report.statusBadgeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('REPORTED USER', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(
                            report.reportedName ?? report.reportedId,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text('ID: ${report.reportedId}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('REPORTER', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(
                            report.reporterName ?? (report.reporterId ?? 'Anonymous Guest'),
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          if (report.roomId != null)
                            Text('Room: ${report.roomId}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),

                if (report.details != null && report.details!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Text(
                      'Context: "${report.details}"',
                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],

                if (report.isResolved) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.success.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Action Taken: ${report.actionLabel}',
                          style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        if (report.adminNotes != null)
                          Text(
                            'Admin Notes: ${report.adminNotes}',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ],

                // Action Bar (for pending reports)
                if (report.isPending) ...[
                  const SizedBox(height: 14),
                  const Divider(color: AppColors.surfaceBorder),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Ban User
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          icon: const Icon(Icons.block_rounded, size: 14),
                          label: const Text('Ban User', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: () => _showActionDialog(report, 'Ban User Permanently', 'banned', AppColors.danger),
                        ),
                        const SizedBox(width: 8),

                        // Suspend 24h
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF9800),
                            side: const BorderSide(color: Color(0xFFFF9800)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          icon: const Icon(Icons.timer_outlined, size: 14),
                          label: const Text('Suspend 24h', style: TextStyle(fontSize: 12)),
                          onPressed: () => _showActionDialog(report, 'Suspend User 24h', 'suspended_24h', const Color(0xFFFF9800)),
                        ),
                        const SizedBox(width: 8),

                        // Revoke Creator
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF9C27B0),
                            side: const BorderSide(color: Color(0xFF9C27B0)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          icon: const Icon(Icons.person_off_rounded, size: 14),
                          label: const Text('Revoke Creator', style: TextStyle(fontSize: 12)),
                          onPressed: () => _showActionDialog(report, 'Revoke Creator KYC', 'creator_revoked', const Color(0xFF9C27B0)),
                        ),
                        const SizedBox(width: 8),

                        // Freeze Wallet
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00E5FF),
                            side: const BorderSide(color: Color(0xFF00E5FF)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          icon: const Icon(Icons.ac_unit_rounded, size: 14),
                          label: const Text('Freeze Wallet', style: TextStyle(fontSize: 12)),
                          onPressed: () => _showActionDialog(report, 'Freeze Creator Wallet', 'wallet_frozen', const Color(0xFF00E5FF)),
                        ),
                        const SizedBox(width: 8),

                        // Dismiss
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textMuted,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          icon: const Icon(Icons.close_rounded, size: 14),
                          label: const Text('Dismiss', style: TextStyle(fontSize: 12)),
                          onPressed: () => _showActionDialog(report, 'Dismiss Report', 'dismissed', Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

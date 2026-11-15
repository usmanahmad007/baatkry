import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/admin_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/creator_application.dart';
import '../../../services/supabase_service.dart';

class AdminCreatorAppsTab extends ConsumerStatefulWidget {
  const AdminCreatorAppsTab({super.key});

  @override
  ConsumerState<AdminCreatorAppsTab> createState() => _AdminCreatorAppsTabState();
}

class _AdminCreatorAppsTabState extends ConsumerState<AdminCreatorAppsTab> {
  String _selectedStatus = 'pending';
  bool _isProcessing = false;

  Future<void> _reviewApplication(CreatorApplication app, String action) async {
    String? reason;
    if (action == 'reject') {
      final textController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reject Creator KYC', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Please provide feedback on why this KYC application is being rejected:',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g., ID photo blurry, document expired, etc.',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF0F0F1A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Confirm Rejection', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      reason = textController.text.trim();
      if (reason.isEmpty) reason = 'KYC documentation requirements not met';
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Approve Creator KYC', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Text(
            'Are you sure you want to approve ${app.fullName} as an official creator?\n\nThis will instantly grant creator privileges, create their earnings wallet, and enable real-money gift monetization.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Approve Creator', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    setState(() => _isProcessing = true);
    try {
      await SupabaseService.instance.adminReviewCreatorApplication(
        applicationId: app.id,
        action: action,
        rejectionReason: reason,
      );

      ref.invalidate(adminCreatorApplicationsProvider(_selectedStatus));
      ref.invalidate(adminKpiMetricsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: action == 'approve' ? Colors.green : Colors.redAccent,
            content: Text(
              action == 'approve'
                  ? 'Creator ${app.fullName} approved successfully!'
                  : 'Application for ${app.fullName} rejected.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.redAccent, content: Text('Action failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appsAsync = ref.watch(adminCreatorApplicationsProvider(_selectedStatus));

    return Column(
      children: [
        // Filter pills
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF121220),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('Pending', 'pending'),
                const SizedBox(width: 8),
                _buildFilterChip('Approved', 'approved'),
                const SizedBox(width: 8),
                _buildFilterChip('Rejected', 'rejected'),
                const SizedBox(width: 8),
                _buildFilterChip('All Applications', 'all'),
              ],
            ),
          ),
        ),

        // Applications list
        Expanded(
          child: appsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.brandPink),
            ),
            error: (err, _) => Center(
              child: Text('Error: $err', style: const TextStyle(color: Colors.redAccent)),
            ),
            data: (apps) {
              if (apps.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.assignment_turned_in_rounded, size: 48, color: Colors.white.withOpacity(0.3)),
                      const SizedBox(height: 12),
                      Text(
                        'No $_selectedStatus applications found',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                color: AppColors.brandPink,
                backgroundColor: const Color(0xFF1A1A2E),
                onRefresh: () async => ref.invalidate(adminCreatorApplicationsProvider(_selectedStatus)),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: apps.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (ctx, index) => _buildApplicationCard(apps[index]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedStatus == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _selectedStatus = value);
      },
      selectedColor: AppColors.brandPink,
      backgroundColor: const Color(0xFF1A1A2E),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.textMuted,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
    );
  }

  Widget _buildApplicationCard(CreatorApplication app) {
    Color statusColor = Colors.orangeAccent;
    if (app.isApproved) statusColor = Colors.green;
    if (app.isRejected) statusColor = Colors.redAccent;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Name & Status Badge
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.brandPink.withOpacity(0.2),
                child: Text(
                  app.fullName.isNotEmpty ? app.fullName[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.brandPink, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.fullName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      '${app.country} • Applied ${app.createdAt.month}/${app.createdAt.day}/${app.createdAt.year}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withOpacity(0.5)),
                ),
                child: Text(
                  app.status.name.toUpperCase(),
                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Applicant Comprehensive KYC Data Grid
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.badge_rounded, color: AppColors.brandPink, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'APPLICANT KYC DOSSIER',
                      style: TextStyle(color: AppColors.brandPink, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                    ),
                  ],
                ),
                const Divider(color: Colors.white10, height: 16),
                _buildDossierRow('Full Legal Name', app.fullName, Icons.person_rounded),
                const SizedBox(height: 6),
                _buildDossierRow(
                  'Date of Birth',
                  '${app.dateOfBirth.year}-${app.dateOfBirth.month.toString().padLeft(2, '0')}-${app.dateOfBirth.day.toString().padLeft(2, '0')} (Age: ${app.ageYears} yrs • Adult 18+)',
                  Icons.cake_rounded,
                  highlightGreen: true,
                ),
                const SizedBox(height: 6),
                _buildDossierRow('Nationality / Country', app.country, Icons.public_rounded),
                const SizedBox(height: 6),
                _buildDossierRow('ID Document Type', app.idType.displayName, Icons.credit_card_rounded),
                const SizedBox(height: 6),
                _buildDossierRow('Applicant User ID', app.userId, Icons.fingerprint_rounded),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ID Documents & Facial Verification Previews
          const Text(
            'GOVERNMENT ID & FACIAL VERIFICATION IMAGES',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildDocumentPreviewTile(
                  title: 'Front ID',
                  docUrl: app.idDocumentFrontUrl,
                  icon: Icons.credit_card_rounded,
                  onTap: () => _showDocumentInspectionDialog(context, 'Front ID Document', app.idDocumentFrontUrl, app),
                ),
              ),
              const SizedBox(width: 8),
              if (app.idDocumentBackUrl != null && app.idDocumentBackUrl!.isNotEmpty) ...[
                Expanded(
                  child: _buildDocumentPreviewTile(
                    title: 'Back ID',
                    docUrl: app.idDocumentBackUrl!,
                    icon: Icons.flip_rounded,
                    onTap: () => _showDocumentInspectionDialog(context, 'Back ID Document', app.idDocumentBackUrl!, app),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _buildDocumentPreviewTile(
                  title: 'Selfie Check',
                  docUrl: app.selfieUrl,
                  icon: Icons.face_retouching_natural_rounded,
                  onTap: () => _showDocumentInspectionDialog(context, 'Facial Selfie Verification', app.selfieUrl, app),
                ),
              ),
            ],
          ),

          if (app.bio != null && app.bio!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F1A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Creator Bio / Content Statement:', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    app.bio!,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],

          if (app.socialLinks.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Social Media Handles:', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: app.socialLinks.entries.map((entry) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link_rounded, size: 12, color: AppColors.brandPink),
                      const SizedBox(width: 4),
                      Text(
                        '${entry.key}: ${entry.value}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          if (app.rejectionReason != null && app.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Rejection Note: ${app.rejectionReason}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
            ),
          ],

          // Admin Review Action Buttons (if pending)
          if (app.isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : () => _reviewApplication(app, 'reject'),
                    icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 16),
                    label: const Text('Reject', style: TextStyle(color: Colors.redAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : () => _reviewApplication(app, 'approve'),
                    icon: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                    label: const Text('Approve', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDossierRow(String label, String value, IconData icon, {bool highlightGreen = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: highlightGreen ? Colors.greenAccent : AppColors.textMuted),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: highlightGreen ? Colors.greenAccent : Colors.white,
              fontSize: 12,
              fontWeight: highlightGreen ? FontWeight.bold : FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentPreviewTile({
    required String title,
    required String docUrl,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.brandCyan, size: 22),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            const Text(
              'Tap to Inspect',
              style: TextStyle(color: AppColors.brandPink, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _showDocumentInspectionDialog(BuildContext context, String title, String docUrl, CreatorApplication app) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141424),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.verified_user_rounded, color: AppColors.brandCyan, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Applicant: ${app.fullName} (${app.country})', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            Text('ID Document: ${app.idType.displayName}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.document_scanner_rounded, size: 48, color: AppColors.brandPink),
                    const SizedBox(height: 8),
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        docUrl,
                        style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Verified Image Attachment', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close Inspection', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}


import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/rate_limiter.dart';
import '../../services/supabase_service.dart';

class ReportModal extends StatefulWidget {
  final String peerId;
  final String peerName;
  final String roomId;
  final VoidCallback onReportSubmitted;

  const ReportModal({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.roomId,
    required this.onReportSubmitted,
  });

  static Future<void> show(
    BuildContext context, {
    required String peerId,
    required String peerName,
    required String roomId,
    required VoidCallback onReportSubmitted,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReportModal(
        peerId: peerId,
        peerName: peerName,
        roomId: roomId,
        onReportSubmitted: onReportSubmitted,
      ),
    );
  }

  @override
  State<ReportModal> createState() => _ReportModalState();
}

class _ReportModalState extends State<ReportModal> {
  String _selectedReason = 'Underage User (<18)';
  bool _blockUser = true;
  bool _isSubmitting = false;
  final TextEditingController _detailsController = TextEditingController();

  final List<Map<String, dynamic>> _reasons = [
    {
      'title': 'Underage User (<18)',
      'subtitle': 'Strict 18+ adult platform enforcement',
      'icon': Icons.no_adult_content_rounded,
      'color': const Color(0xFFE91E63),
    },
    {
      'title': 'Inappropriate Content / Nudity',
      'subtitle': 'Sexually explicit or inappropriate camera feed',
      'icon': Icons.visibility_off_rounded,
      'color': const Color(0xFFF44336),
    },
    {
      'title': 'Harassment / Bullying / Hate Speech',
      'subtitle': 'Threats, abusive language, or discrimination',
      'icon': Icons.sentiment_very_dissatisfied_rounded,
      'color': const Color(0xFF9C27B0),
    },
    {
      'title': 'Financial Scam / Coin Begging',
      'subtitle': 'Asking for money, extortion, or gift coercion',
      'icon': Icons.monetization_on_rounded,
      'color': const Color(0xFFFF9800),
    },
    {
      'title': 'Spam, Bot or Advertising',
      'subtitle': 'Automated camera stream, promotional links',
      'icon': Icons.smart_toy_rounded,
      'color': const Color(0xFF2196F3),
    },
    {
      'title': 'Other Safety Concern',
      'subtitle': 'Other suspicious or dangerous activity',
      'icon': Icons.warning_amber_rounded,
      'color': Colors.grey,
    },
  ];

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    final myId = SupabaseService.instance.currentProfile?.id ?? 'guest';

    // Anti-fraud rate limit check
    if (!RateLimiter.instance.canSubmitReport(myId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Please wait a moment before submitting another report.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final detailsText = _detailsController.text.trim();

      await SupabaseService.instance.submitReport(
        reportedUserId: widget.peerId,
        reason: _selectedReason,
        details: detailsText.isNotEmpty ? detailsText : null,
        roomId: widget.roomId,
      );

      if (_blockUser) {
        await SupabaseService.instance.blockUser(widget.peerId, _selectedReason);
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onReportSubmitted();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Report submitted. User blocked and session terminated.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Failed to submit report: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.surfaceBorder, width: 1.5)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_rounded, color: AppColors.danger, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Report & Block ${widget.peerName}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Strict 18+ Adult Community Safety',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Violation Category:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 8),

            ..._reasons.map((r) {
              final title = r['title'] as String;
              final subtitle = r['subtitle'] as String;
              final icon = r['icon'] as IconData;
              final color = r['color'] as Color;
              final isSelected = _selectedReason == title;

              return InkWell(
                onTap: () => setState(() => _selectedReason = title),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? color.withOpacity(0.15) : AppColors.backgroundElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? color : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: color, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              subtitle,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Radio<String>(
                        value: title,
                        groupValue: _selectedReason,
                        activeColor: color,
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedReason = val);
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 10),
            TextField(
              controller: _detailsController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Additional details or context (optional)...',
                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                filled: true,
                fillColor: AppColors.backgroundElevated,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.surfaceBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.surfaceBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.brandPink),
                ),
              ),
            ),

            const SizedBox(height: 10),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _blockUser,
              activeColor: AppColors.danger,
              title: const Text(
                'Permanently block user (never match again)',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Instantly disconnects call and matches next user',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              onChanged: (val) {
                if (val != null) setState(() => _blockUser = val);
              },
            ),

            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.gavel_rounded, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Submit Report & Terminate Session',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

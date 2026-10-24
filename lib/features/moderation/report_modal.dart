import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
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
  String _selectedReason = 'Inappropriate Content / Nudity';
  bool _blockUser = true;
  bool _isSubmitting = false;

  final List<String> _reasons = [
    'Inappropriate Content / Nudity',
    'Underage User (<18)',
    'Harassment / Bullying / Hate Speech',
    'Spam, Bot or Advertising',
    'Other Safety Concern',
  ];

  Future<void> _submitReport() async {
    setState(() => _isSubmitting = true);

    try {
      await SupabaseService.instance.submitReport(
        reportedUserId: widget.peerId,
        reason: _selectedReason,
        roomId: widget.roomId,
      );

      if (_blockUser) {
        await SupabaseService.instance.blockUser(widget.peerId);
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onReportSubmitted();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Report submitted. User has been blocked and skipped.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.surfaceBorder, width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flag_rounded, color: AppColors.danger, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Report ${widget.peerName}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    const Text('Help keep our community safe', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Select a Reason:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          ..._reasons.map(
            (reason) => RadioListTile<String>(
              dense: true,
              value: reason,
              groupValue: _selectedReason,
              activeColor: AppColors.danger,
              contentPadding: EdgeInsets.zero,
              title: Text(reason, style: const TextStyle(color: Colors.white, fontSize: 14)),
              onChanged: (val) {
                if (val != null) setState(() => _selectedReason = val);
              },
            ),
          ),
          const Divider(color: AppColors.surfaceBorder),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _blockUser,
            activeColor: AppColors.danger,
            title: const Text('Block user (never match with them again)', style: TextStyle(color: Colors.white, fontSize: 14)),
            onChanged: (val) {
              if (val != null) setState(() => _blockUser = val);
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submitReport,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _isSubmitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Submit Report & Skip User', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

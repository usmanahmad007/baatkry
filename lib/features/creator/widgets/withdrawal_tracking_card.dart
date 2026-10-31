import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/creator_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/creator_withdrawal.dart';
import '../../../services/supabase_service.dart';

class WithdrawalTrackingCard extends ConsumerStatefulWidget {
  final CreatorWithdrawal withdrawal;

  const WithdrawalTrackingCard({
    super.key,
    required this.withdrawal,
  });

  @override
  ConsumerState<WithdrawalTrackingCard> createState() => _WithdrawalTrackingCardState();
}

class _WithdrawalTrackingCardState extends ConsumerState<WithdrawalTrackingCard> {
  bool _isCancelling = false;

  Future<void> _cancelWithdrawal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Payout Request?', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          'Are you sure you want to cancel this withdrawal request of ${widget.withdrawal.formattedAmount}?\n\nThe full amount will immediately be restored to your available earnings balance.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Request', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Cancel & Restore Funds', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCancelling = true);
    try {
      await SupabaseService.instance.cancelCreatorWithdrawal(widget.withdrawal.id);
      ref.invalidate(creatorMyWithdrawalsProvider);
      ref.invalidate(creatorWalletProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text('${widget.withdrawal.formattedAmount} restored to your available earnings.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.redAccent, content: Text('Cancellation failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.withdrawal;
    Color statusColor = Colors.orangeAccent;
    if (tx.isCompleted) statusColor = Colors.green;
    if (tx.isApproved) statusColor = AppColors.brandCyan;
    if (tx.isCancelled || tx.isRejected) statusColor = Colors.redAccent;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161626),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Amount & Status Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.coinGold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.payments_rounded, color: AppColors.coinGold, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.formattedAmount,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      '${tx.payoutMethod.toUpperCase()} • ${tx.createdAt.month}/${tx.createdAt.day}/${tx.createdAt.year}',
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
                  tx.statusDisplayName,
                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 5-Step Visual Timeline (if in active progression)
          if (!tx.isCancelled && !tx.isRejected) ...[
            _buildTimeline(tx.timelineStep),
            const SizedBox(height: 12),
          ],

          // Transaction Reference if Completed
          if (tx.isCompleted && tx.payoutTransactionReference != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Reference: ${tx.payoutTransactionReference}',
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Rejection / Cancellation Notice
          if (tx.isRejected) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rejection Reason: ${tx.adminNotes ?? "Payment details could not be verified."}',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '✓ Funds have been fully restored to your available earnings balance.',
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          if (tx.isCancelled) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: const Text(
                'Request cancelled by you. Funds restored to available balance.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Cancel Action (if pending or under review)
          if (tx.canCancel) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isCancelling ? null : _cancelWithdrawal,
                icon: const Icon(Icons.undo_rounded, color: Colors.redAccent, size: 16),
                label: Text(
                  _isCancelling ? 'Cancelling...' : 'Cancel Request & Restore Funds',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeline(int currentStep) {
    const steps = ['Requested', 'Review', 'Approved', 'Processing', 'Paid'];

    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          // Connector line
          final prevStepIndex = i ~/ 2;
          final isPassed = currentStep > prevStepIndex;
          return Expanded(
            child: Container(
              height: 2,
              color: isPassed ? Colors.green : Colors.white12,
            ),
          );
        }

        // Node
        final stepIndex = i ~/ 2;
        final isPassed = currentStep >= stepIndex;
        final isCurrent = currentStep == stepIndex;

        return Column(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isPassed ? Colors.green : const Color(0xFF202035),
                border: Border.all(
                  color: isCurrent ? Colors.white : (isPassed ? Colors.green : Colors.white24),
                  width: isCurrent ? 2 : 1,
                ),
              ),
              child: isPassed
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 10)
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              steps[stepIndex],
              style: TextStyle(
                color: isPassed ? Colors.white70 : AppColors.textMuted,
                fontSize: 9,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        );
      }),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/admin_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/creator_withdrawal.dart';
import '../../../services/supabase_service.dart';

class AdminWithdrawalsTab extends ConsumerStatefulWidget {
  const AdminWithdrawalsTab({super.key});

  @override
  ConsumerState<AdminWithdrawalsTab> createState() => _AdminWithdrawalsTabState();
}

class _AdminWithdrawalsTabState extends ConsumerState<AdminWithdrawalsTab> {
  String _selectedStatus = 'pending';
  bool _isProcessing = false;

  Future<void> _reviewWithdrawal(CreatorWithdrawal tx, String action) async {
    String? notes;
    String? txRef;

    if (action == 'reject' || action == 'fail') {
      final textController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reject Withdrawal Request', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rejecting this payout of ${tx.formattedAmount} will automatically restore \$${tx.amountUsd.toStringAsFixed(2)} back to ${tx.creatorName}\'s available balance.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Reason (e.g., Invalid PayPal email, bank details mismatch)',
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
              child: const Text('Reject & Refund', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      notes = textController.text.trim();
      if (notes.isEmpty) notes = 'Payout rejected by administrator';
    } else if (action == 'complete') {
      final txRefController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirm Completed Payout', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter transaction reference for ${tx.formattedNetAmount} sent via ${tx.payoutMethod.toUpperCase()}:',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: txRefController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g. PayPal TX ID, Wire Ref #',
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Mark Completed', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      txRef = txRefController.text.trim();
      if (txRef.isEmpty) txRef = 'MANUAL_TX_${DateTime.now().millisecondsSinceEpoch}';
    } else if (action == 'approve') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Approve Withdrawal', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Text(
            'Approve payout of ${tx.formattedNetAmount} for ${tx.creatorName}?\nThis moves the request to processing status.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPink),
              child: const Text('Approve Payout', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    setState(() => _isProcessing = true);
    try {
      await SupabaseService.instance.adminReviewWithdrawal(
        withdrawalId: tx.id,
        action: action,
        adminNotes: notes,
        transactionReference: txRef,
      );

      ref.invalidate(adminWithdrawalsProvider(_selectedStatus));
      ref.invalidate(adminKpiMetricsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: action == 'complete'
                ? Colors.green
                : (action == 'reject' ? Colors.redAccent : AppColors.brandPink),
            content: Text(
              action == 'complete'
                  ? 'Withdrawal marked as completed!'
                  : (action == 'reject'
                      ? 'Withdrawal rejected and refunded to creator.'
                      : 'Withdrawal approved.'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.redAccent, content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final withdrawalsAsync = ref.watch(adminWithdrawalsProvider(_selectedStatus));

    return Column(
      children: [
        // Status filter tabs
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
                _buildFilterChip('Completed', 'completed'),
                const SizedBox(width: 8),
                _buildFilterChip('Rejected', 'rejected'),
                const SizedBox(width: 8),
                _buildFilterChip('All Payouts', 'all'),
              ],
            ),
          ),
        ),

        // Withdrawals list
        Expanded(
          child: withdrawalsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.brandPink),
            ),
            error: (err, _) => Center(
              child: Text('Error: $err', style: const TextStyle(color: Colors.redAccent)),
            ),
            data: (txList) {
              if (txList.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.payments_rounded, size: 48, color: Colors.white.withOpacity(0.3)),
                      const SizedBox(height: 12),
                      Text(
                        'No $_selectedStatus withdrawal requests found',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                color: AppColors.brandPink,
                backgroundColor: const Color(0xFF1A1A2E),
                onRefresh: () async => ref.invalidate(adminWithdrawalsProvider(_selectedStatus)),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: txList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (ctx, index) => _buildWithdrawalCard(txList[index]),
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

  Widget _buildWithdrawalCard(CreatorWithdrawal tx) {
    Color statusColor = Colors.orangeAccent;
    if (tx.isCompleted) statusColor = Colors.green;
    if (tx.isApproved) statusColor = AppColors.brandCyan;
    if (tx.status == 'rejected' || tx.status == 'failed') statusColor = Colors.redAccent;

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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.coinGold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.attach_money_rounded, color: AppColors.coinGold, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.creatorName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      'Method: ${tx.payoutMethod.toUpperCase()} • ${tx.createdAt.month}/${tx.createdAt.day}/${tx.createdAt.year}',
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

          // Payout Financial Breakdown Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F1A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Requested Gross', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(tx.formattedAmount, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Processing Fee', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(tx.formattedFee, style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Net Payout', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(tx.formattedNetAmount, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
              ],
            ),
          ),

          if (tx.payoutDetails.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Account: ${tx.payoutDetails['account'] ?? tx.payoutDetails['email'] ?? tx.payoutDetails.values.join(', ')}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],

          if (tx.payoutTransactionReference != null) ...[
            const SizedBox(height: 6),
            Text(
              'Reference: ${tx.payoutTransactionReference}',
              style: const TextStyle(color: AppColors.brandCyan, fontSize: 11, fontFamily: 'monospace'),
            ),
          ],

          if (tx.adminNotes != null) ...[
            const SizedBox(height: 6),
            Text(
              'Admin Note: ${tx.adminNotes}',
              style: const TextStyle(color: Colors.white60, fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],

          // Admin Review Controls
          if (tx.isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isProcessing ? null : () => _reviewWithdrawal(tx, 'reject'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Reject & Refund', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : () => _reviewWithdrawal(tx, 'approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandPink,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Approve', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ] else if (tx.isApproved) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : () => _reviewWithdrawal(tx, 'complete'),
                icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                label: const Text('Mark as Completed & Settle', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/wallet_ledger_entry.dart';

class TransactionTile extends StatelessWidget {
  final WalletLedgerEntry entry;

  const TransactionTile({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final isCredit = entry.isPositive || entry.type.isCredit;
    final color = isCredit ? AppColors.success : AppColors.brandPink;

    IconData icon;
    switch (entry.type) {
      case LedgerTransactionType.purchase:
        icon = Icons.add_card_rounded;
        break;
      case LedgerTransactionType.giftSent:
        icon = Icons.card_giftcard_rounded;
        break;
      case LedgerTransactionType.giftReceived:
        icon = Icons.redeem_rounded;
        break;
      case LedgerTransactionType.featureUnlock:
        icon = Icons.lock_open_rounded;
        break;
      case LedgerTransactionType.bonus:
        icon = Icons.stars_rounded;
        break;
      case LedgerTransactionType.adminAdjustment:
        icon = Icons.admin_panel_settings_rounded;
        break;
      case LedgerTransactionType.refundDeduct:
        icon = Icons.undo_rounded;
        break;
      default:
        icon = Icons.receipt_long_rounded;
    }

    final formattedDate = _formatDate(entry.createdAt);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.description ?? entry.type.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.amount >= 0 ? '+' : ''}${entry.amount} Coins',
                style: TextStyle(
                  color: isCredit ? AppColors.coinGold : AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Bal: ${entry.balanceAfter}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

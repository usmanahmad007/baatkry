import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/creator_earning_entry.dart';

class EarningTile extends StatelessWidget {
  final CreatorEarningEntry entry;

  const EarningTile({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          // Gift Emoji Avatar
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.brandIndigo.withOpacity(0.2),
                  AppColors.brandPink.withOpacity(0.12),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(entry.giftEmoji ?? '🎁', style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 14),

          // Details Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.giftName != null && entry.giftName!.isNotEmpty
                            ? 'Received ${entry.giftName}'
                            : 'Virtual Gift Earning',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      entry.formattedNet,
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${entry.coins ?? 0} Coins',
                      style: const TextStyle(color: AppColors.coinGold, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    const Text('•', style: TextStyle(color: Colors.white30, fontSize: 10)),
                    const SizedBox(width: 6),
                    Text(
                      'Gross: ${entry.formattedGross} (Fee: ${entry.formattedCommission})',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${entry.createdAt.year}-${entry.createdAt.month.toString().padLeft(2, '0')}-${entry.createdAt.day.toString().padLeft(2, '0')} ${entry.createdAt.hour.toString().padLeft(2, '0')}:${entry.createdAt.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: entry.isWithdrawn
                            ? AppColors.brandBlue.withOpacity(0.15)
                            : AppColors.success.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        entry.status.toUpperCase(),
                        style: TextStyle(
                          color: entry.isWithdrawn ? AppColors.brandBlue : AppColors.success,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

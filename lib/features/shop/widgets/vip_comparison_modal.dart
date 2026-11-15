import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/vip_avatar.dart';
import '../shop_modal.dart';

/// Interactive modal presenting the side-by-side comparison between Normal and VIP users
class VipComparisonModal extends ConsumerWidget {
  const VipComparisonModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VipComparisonModal(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final isVip = profile?.isVip ?? false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14172B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: isVip ? const Color(0xFFFFD700) : AppColors.brandIndigo,
            width: 2.0,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  gradient: AppColors.vipGoldGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.black, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Free User vs VIP Member',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isVip ? 'Your VIP membership is currently ACTIVE 👑' : 'Unlock unlimited gender filters & priority matching',
                      style: TextStyle(
                        color: isVip ? AppColors.coinGold : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: isVip ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 22),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Side-by-side Avatar preview comparing Normal vs VIP
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1D223B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Normal User Avatar
                Column(
                  children: [
                    VipAvatar(
                      nickname: profile?.nickname ?? 'Normal',
                      avatarUrl: profile?.avatarUrl,
                      radius: 26,
                      isVip: false,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Normal User',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Standard Ring',
                      style: TextStyle(fontSize: 10, color: Colors.white38),
                    ),
                  ],
                ),
                Container(
                  width: 1,
                  height: 60,
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
                // VIP Member Avatar
                Column(
                  children: [
                    VipAvatar(
                      nickname: profile?.nickname ?? 'VIP',
                      avatarUrl: profile?.avatarUrl,
                      radius: 26,
                      isVip: true,
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('👑 ', style: TextStyle(fontSize: 11)),
                        Text(
                          'VIP Member',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.coinGold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Gold Ring + VIP Badge',
                      style: TextStyle(fontSize: 10, color: AppColors.coinGold, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Feature Comparison Table
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _comparisonRow(
                    feature: 'Gender Filtering (Women/Men)',
                    normal: 'Random / Both Only',
                    vip: '100% UNLIMITED',
                    isHighlight: true,
                  ),
                  _comparisonRow(
                    feature: 'Profile Picture VIP Circle',
                    normal: 'Standard Border',
                    vip: 'Gold Ring + "VIP" Badge',
                    isHighlight: false,
                  ),
                  _comparisonRow(
                    feature: 'Matchmaking Speed',
                    normal: 'Standard Queue',
                    vip: '1-2s Instant VIP Priority',
                    isHighlight: true,
                  ),
                  _comparisonRow(
                    feature: 'Global Country Filter',
                    normal: '50 Coins / switch',
                    vip: 'Free Unlimited Selection',
                    isHighlight: false,
                  ),
                  _comparisonRow(
                    feature: 'In-Call Identity Badge',
                    normal: 'Standard Name',
                    vip: '👑 VIP Tag & Gold Flair',
                    isHighlight: false,
                  ),
                  _comparisonRow(
                    feature: 'Coins Needed for Filtered Calls',
                    normal: 'Coins Deducted',
                    vip: 'Zero Coin Charge',
                    isHighlight: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Bottom Action
          if (isVip)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.success.withOpacity(0.4)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'VIP Membership Active',
                    style: TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            )
          else
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                ShopModal.show(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.coinGold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('👑', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Text(
                    'Get VIP Membership Now',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _comparisonRow({
    required String feature,
    required String normal,
    required String vip,
    required bool isHighlight,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isHighlight ? AppColors.coinGold.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isHighlight ? Border.all(color: AppColors.coinGold.withOpacity(0.25)) : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              feature,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              normal,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.coinGold, size: 14),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    vip,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.coinGold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

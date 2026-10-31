import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/admin_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/coin_package.dart';
import '../../../models/commission_rule.dart';
import '../../../models/virtual_gift.dart';
import '../../../services/supabase_service.dart';

class AdminCatalogTab extends ConsumerStatefulWidget {
  const AdminCatalogTab({super.key});

  @override
  ConsumerState<AdminCatalogTab> createState() => _AdminCatalogTabState();
}

class _AdminCatalogTabState extends ConsumerState<AdminCatalogTab> {
  Future<void> _editGift(VirtualGift gift) async {
    final priceController = TextEditingController(text: '${gift.coinPrice}');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit ${gift.name} (${gift.emoji})', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Coin Price:', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F0F1A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixText: 'Coins',
                suffixStyle: const TextStyle(color: AppColors.coinGold),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPink),
            child: const Text('Save Changes', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final newPrice = int.tryParse(priceController.text.trim());
    if (newPrice != null && newPrice > 0) {
      await SupabaseService.instance.updateAdminGift(gift.id, coinPrice: newPrice);
      ref.invalidate(adminGiftsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.green, content: Text('${gift.name} price updated to $newPrice coins.')),
        );
      }
    }
  }

  Future<void> _editPackage(CoinPackage pkg) async {
    final coinsController = TextEditingController(text: '${pkg.coins}');
    final priceController = TextEditingController(text: pkg.priceUsd.toStringAsFixed(2));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit ${pkg.name} Package', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Coins Included:', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: coinsController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F0F1A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixText: 'Coins',
                suffixStyle: const TextStyle(color: AppColors.coinGold),
              ),
            ),
            const SizedBox(height: 12),
            const Text('USD Price:', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F0F1A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixText: '\$ ',
                prefixStyle: const TextStyle(color: Colors.greenAccent),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPink),
            child: const Text('Save Package', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final newCoins = int.tryParse(coinsController.text.trim());
    final newPrice = double.tryParse(priceController.text.trim());

    if (newCoins != null && newPrice != null) {
      await SupabaseService.instance.updateAdminCoinPackage(pkg.id, coinAmount: newCoins, priceUsd: newPrice);
      ref.invalidate(adminCoinPackagesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.green, content: Text('${pkg.name} updated successfully.')),
        );
      }
    }
  }

  Future<void> _editCommissionRule(CommissionRule rule) async {
    final creatorShareController = TextEditingController(text: '${rule.creatorSharePercentage}');
    final minWithdrawalController = TextEditingController(text: rule.minimumWithdrawalAmountUsd.toStringAsFixed(2));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Configure Commission Policy', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Creator Share (%):', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: creatorShareController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F0F1A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixText: '%',
              ),
            ),
            const SizedBox(height: 12),
            const Text('Minimum Payout Threshold (USD):', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: minWithdrawalController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F0F1A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixText: '\$ ',
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPink),
            child: const Text('Update Policy', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final newCreatorShare = double.tryParse(creatorShareController.text.trim());
    final newMinPayout = double.tryParse(minWithdrawalController.text.trim());

    if (newCreatorShare != null && newMinPayout != null) {
      final newPlatformShare = 100.0 - newCreatorShare;
      await SupabaseService.instance.updateAdminCommissionRule(
        ruleId: rule.id,
        creatorSharePercent: newCreatorShare,
        platformSharePercent: newPlatformShare,
        coinRateUsd: rule.coinConversionRateUsd,
        minWithdrawalUsd: newMinPayout,
      );
      ref.invalidate(adminCommissionRuleProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.green, content: Text('Commission policy updated.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final giftsAsync = ref.watch(adminGiftsProvider);
    final packagesAsync = ref.watch(adminCoinPackagesProvider);
    final commissionAsync = ref.watch(adminCommissionRuleProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section 1: Commission Split Policy Card
          _buildCommissionCard(commissionAsync),

          const SizedBox(height: 24),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'VIRTUAL GIFTS CATALOGUE',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Text('Live Pricing', style: TextStyle(color: AppColors.brandCyan, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),

          // Gifts List
          giftsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandPink)),
            error: (err, _) => Text('Error: $err', style: const TextStyle(color: Colors.redAccent)),
            data: (gifts) => ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: gifts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, index) => _buildGiftRow(gifts[index]),
            ),
          ),

          const SizedBox(height: 28),
          const Text(
            'COIN PACKAGES',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          // Packages List
          packagesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandPink)),
            error: (err, _) => Text('Error: $err', style: const TextStyle(color: Colors.redAccent)),
            data: (pkgs) => ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pkgs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, index) => _buildPackageRow(pkgs[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommissionCard(AsyncValue<CommissionRule> commissionAsync) {
    return commissionAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (rule) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.brandPink.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.tune_rounded, color: AppColors.brandPink, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Commission & Payout Policy',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => _editCommissionRule(rule),
                  child: const Text('Edit', style: TextStyle(color: AppColors.brandPink, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildPolicyItem(
                    label: 'Creator Share',
                    value: '${rule.creatorSharePercentage.toInt()}%',
                    color: Colors.greenAccent,
                  ),
                ),
                Expanded(
                  child: _buildPolicyItem(
                    label: 'Platform Cut',
                    value: '${rule.platformSharePercentage.toInt()}%',
                    color: AppColors.brandPink,
                  ),
                ),
                Expanded(
                  child: _buildPolicyItem(
                    label: 'Min Payout',
                    value: rule.formattedMinWithdrawal,
                    color: AppColors.coinGold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyItem({required String label, required String value, required Color color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildGiftRow(VirtualGift gift) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Text(gift.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gift.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Text(
                  '${gift.coinPrice} coins • \$${(gift.coinPrice * 0.002).toStringAsFixed(2)} gross value',
                  style: const TextStyle(color: AppColors.coinGold, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: AppColors.brandCyan, size: 18),
            onPressed: () => _editGift(gift),
            tooltip: 'Edit Coin Price',
          ),
        ],
      ),
    );
  }

  Widget _buildPackageRow(CoinPackage pkg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.coinGold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pkg.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Text('${pkg.coins} coins', style: const TextStyle(color: AppColors.coinGold, fontSize: 12)),
              ],
            ),
          ),
          Text(
            pkg.formattedPrice,
            style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: AppColors.brandCyan, size: 18),
            onPressed: () => _editPackage(pkg),
            tooltip: 'Edit Price & Coins',
          ),
        ],
      ),
    );
  }
}


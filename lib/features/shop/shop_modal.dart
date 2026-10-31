import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/coin_package.dart';
import '../../services/supabase_service.dart';
import '../auth/auth_modal.dart';
import '../moderation/age_consent_modal.dart';

class ShopModal extends ConsumerStatefulWidget {
  const ShopModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ShopModal(),
    );
  }

  @override
  ConsumerState<ShopModal> createState() => _ShopModalState();
}

class _ShopModalState extends ConsumerState<ShopModal> {
  bool _isProcessing = false;

  void _onPackageSelected(CoinPackage package) async {
    final isBlocked = await AgeConsentModal.isBlockedUnderage();
    if (!mounted) return;
    if (isBlocked) {
      Navigator.of(context).pop();
      AgeConsentModal.showUnderageBlockedDialog(context);
      return;
    }

    final isGuest = ref.read(isGuestProvider);

    // Login is strictly required to make purchases
    if (isGuest) {
      Navigator.of(context).pop();
      _promptLoginRequired(package);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      await SupabaseService.instance.processPurchase(
        packageId: package.id,
        coinsAdded: package.coins,
        priceRs: package.priceRs,
      );

      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.of(context).pop();
        _showSuccessDialog(package);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Purchase failed: $e'),
          ),
        );
      }
    }
  }

  void _promptLoginRequired(CoinPackage package) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.warning, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: AppColors.warning, size: 28),
            SizedBox(width: 10),
            Text('Login Required', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Anonymous guests cannot make purchases to protect payment security.',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Text(
                'Please sign in with Google to purchase "${package.title}" (${package.coins} Coins = ${package.minutes} mins). Your balance and VIP perks will be safely saved to your account.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              AuthModal.show(context, onAuthSuccess: () {
                ShopModal.show(context);
              });
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('G ', style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w900, fontSize: 16)),
                Text('Sign In with Google', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(CoinPackage package) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 48),
            ),
            const SizedBox(height: 16),
            const Text(
              'Recharge Successful!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              '+${package.coins} Coins added (${package.minutes} Minutes of Gender-Filtered Video Chat).',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Start Chatting!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userCoins = ref.watch(userCoinsProvider);
    final isGuest = ref.watch(isGuestProvider);

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.90),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
      decoration: BoxDecoration(
        color: AppColors.backgroundElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: const Border(top: BorderSide(color: AppColors.brandIndigo, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandIndigo.withOpacity(0.25),
            blurRadius: 30,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'Coins & VIP Packages',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.coinGold.withOpacity(0.2), AppColors.coinGoldDark.withOpacity(0.1)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.coinGold.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.circle, color: AppColors.coinGold, size: 10),
                    const SizedBox(width: 6),
                    Text(
                      '$userCoins Coins',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.coinGold, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Economy Rule Card: 20 Rs = 1 min
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.brandIndigo.withOpacity(0.15), AppColors.brandPink.withOpacity(0.08)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.brandIndigo.withOpacity(0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.bolt_rounded, color: AppColors.coinGold, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VIP Plan: 500 Rupees = 60 Minutes',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '1 Coin = 1 Second of Gender-Filtered Chat. Minimum deposit: 500 Rs (60 Minutes).',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Guest Warning Banner
          if (isGuest)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.warning.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_person_rounded, color: AppColors.warning, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Google Sign-In Required',
                          style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Sign in to purchase packages, unlock VIP gender filters, and secure your coins.',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      AuthModal.show(context, onAuthSuccess: () => ShopModal.show(context));
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Sign In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              itemCount: CoinPackage.availablePackages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final package = CoinPackage.availablePackages[index];
                return _buildPackageCard(package);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard(CoinPackage package) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.darkCardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: package.isPopular ? AppColors.coinGold : AppColors.surfaceBorder,
          width: package.isPopular ? 2 : 1,
        ),
        boxShadow: package.isPopular
            ? [
                BoxShadow(
                  color: AppColors.coinGold.withOpacity(0.2),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: package.isPopular
                  ? AppColors.vipGoldGradient
                  : LinearGradient(
                      colors: [AppColors.brandIndigo.withOpacity(0.2), AppColors.brandPink.withOpacity(0.15)],
                    ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              package.isPopular ? Icons.workspace_premium_rounded : Icons.stars_rounded,
              color: package.isPopular ? Colors.black87 : AppColors.coinGold,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      package.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                    ),
                    if (package.badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: package.isPopular ? AppColors.vipGoldGradient : AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          package.badge!,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: package.isPopular ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  package.description,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${package.minutes} Mins',
                      style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${package.coins} Coins)',
                      style: const TextStyle(color: AppColors.coinGold, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              gradient: package.isPopular ? AppColors.vipGoldGradient : AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: (package.isPopular ? AppColors.coinGold : AppColors.brandIndigo).withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isProcessing ? null : () => _onPackageSelected(package),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: package.isPopular ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                'Rs. ${package.priceRs}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

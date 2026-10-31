import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/coin_package.dart';
import '../../services/supabase_service.dart';
import '../auth/auth_modal.dart';
import '../moderation/age_consent_modal.dart';
import 'widgets/coin_package_card.dart';
import 'widgets/transaction_tile.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WalletScreen()),
    );
  }

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _processingPackageId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handlePurchase(CoinPackage package) async {
    final isBlocked = await AgeConsentModal.isBlockedUnderage();
    if (!mounted) return;
    if (isBlocked) {
      AgeConsentModal.showUnderageBlockedDialog(context);
      return;
    }

    final isGuest = ref.read(isGuestProvider);
    if (isGuest) {
      _promptLoginRequired(package);
      return;
    }

    setState(() => _processingPackageId = package.id);

    try {
      final success = await SupabaseService.instance.processPurchase(
        packageId: package.id,
        coinsAdded: package.coins,
        priceRs: package.priceRs,
        priceUsd: package.priceUsd,
      );

      if (mounted) {
        setState(() => _processingPackageId = null);
        if (success) {
          _showSuccessDialog(package);
          // Invalidate ledger to fetch latest entry
          ref.invalidate(walletLedgerProvider);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processingPackageId = null);
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
              'Anonymous guests cannot make purchases to protect financial payment security.',
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
                'Please sign in with Google to purchase "${package.title}". Your balance and perks will be safely preserved in your secure wallet.',
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
              AuthModal.show(context, onAuthSuccess: () {});
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
              'Coins Added to Wallet!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              '+${package.coins} Coins credited to your ledger (${package.minutes} Minutes of Gender-Filtered Video Chat).',
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
                child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coins = ref.watch(userCoinsProvider);
    final isGuest = ref.watch(isGuestProvider);
    final currentProfile = ref.watch(currentProfileProvider);
    final packagesAsync = ref.watch(coinPackagesProvider);
    final ledgerAsync = ref.watch(walletLedgerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('My Coin Wallet', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Hero Coin Card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF261D4E), Color(0xFF131528)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.brandIndigo.withOpacity(0.4), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandIndigo.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.coinGold.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 28),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Available Balance', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              Text(
                                '$coins Coins',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: currentProfile?.isVip ?? false
                              ? AppColors.coinGold.withOpacity(0.2)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: currentProfile?.isVip ?? false
                                ? AppColors.coinGold
                                : Colors.white24,
                          ),
                        ),
                        child: Text(
                          currentProfile?.isVip ?? false ? 'VIP MEMBER' : 'FREE TIER',
                          style: TextStyle(
                            color: currentProfile?.isVip ?? false
                                ? AppColors.coinGold
                                : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStat('Estimated VIP Call Time', '${(coins / 60).floor()} Mins'),
                        Container(width: 1, height: 24, color: Colors.white12),
                        _buildStat('Standard Video', 'Unlimited Free'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (isGuest)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'You are in Guest Mode. Log in with Google to purchase packages and keep coins.',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: () => AuthModal.show(context),
                        child: const Text('Log In', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),

            // Tab Bar: Buy Packages vs Transaction History
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: const [
                  Tab(icon: Icon(Icons.add_shopping_cart_rounded, size: 18), text: 'Buy Coins'),
                  Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'Transaction Ledger'),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Buy Packages
                  packagesAsync.when(
                    data: (packages) => ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: packages.length,
                      itemBuilder: (ctx, index) {
                        final pkg = packages[index];
                        return CoinPackageCard(
                          package: pkg,
                          isSelected: _processingPackageId == pkg.id,
                          isProcessing: _processingPackageId != null,
                          onTap: () => _handlePurchase(pkg),
                        );
                      },
                    ),
                    loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandCyan)),
                    error: (e, _) => Center(
                      child: Text('Error loading packages: $e', style: const TextStyle(color: AppColors.danger)),
                    ),
                  ),

                  // Tab 2: Transaction Ledger
                  ledgerAsync.when(
                    data: (entries) {
                      if (entries.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 48, color: Colors.white.withOpacity(0.2)),
                              const SizedBox(height: 12),
                              const Text('No transactions yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                              const SizedBox(height: 4),
                              const Text('Purchases and gift records will appear here.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: entries.length,
                        itemBuilder: (ctx, index) {
                          return TransactionTile(entry: entries[index]);
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandCyan)),
                    error: (e, _) => Center(
                      child: Text('Error loading ledger: $e', style: const TextStyle(color: AppColors.danger)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: AppColors.coinGold, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }
}

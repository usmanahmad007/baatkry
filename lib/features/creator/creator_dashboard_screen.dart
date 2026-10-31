import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/creator_earning_entry.dart';
import '../../models/creator_wallet.dart';
import 'widgets/earning_tile.dart';

class CreatorDashboardScreen extends ConsumerStatefulWidget {
  const CreatorDashboardScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreatorDashboardScreen()),
    );
  }

  @override
  ConsumerState<CreatorDashboardScreen> createState() => _CreatorDashboardScreenState();
}

class _CreatorDashboardScreenState extends ConsumerState<CreatorDashboardScreen> {
  String _selectedFilter = 'all'; // 'all', 'available', 'withdrawn'

  @override
  Widget build(BuildContext context) {
    final walletStream = ref.watch(creatorWalletStreamProvider);
    final walletAsync = ref.watch(creatorWalletProvider);
    final earningsAsync = ref.watch(creatorEarningsProvider);
    final ruleAsync = ref.watch(activeCommissionRuleProvider);

    final wallet = walletStream.valueOrNull ?? walletAsync.valueOrNull ?? CreatorWallet(
      id: 'local_wallet',
      creatorId: 'local',
      availableEarningsUsd: 0.0,
      lifetimeEarningsUsd: 0.0,
      withdrawnEarningsUsd: 0.0,
    );

    final rule = ruleAsync.valueOrNull;
    final minWithdrawal = rule?.minWithdrawalUsd ?? 20.00;
    final canWithdraw = wallet.availableEarningsUsd >= minWithdrawal;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Row(
          children: [
            Text('Creator Studio', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            SizedBox(width: 8),
            Icon(Icons.verified_rounded, color: AppColors.success, size: 20),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(creatorWalletProvider);
            ref.invalidate(creatorEarningsProvider);
            ref.invalidate(activeCommissionRuleProvider);
          },
          color: AppColors.brandIndigo,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Hero Real-Money Wallet Card
                _buildHeroWalletCard(wallet, canWithdraw, minWithdrawal),
                const SizedBox(height: 16),

                // 2. Commission & Exchange Policy Card
                _buildPolicyCard(rule),
                const SizedBox(height: 18),

                // 3. Itemized Earnings Header & Filters
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Gift Earnings History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        _filterChip('All', 'all'),
                        const SizedBox(width: 6),
                        _filterChip('Available', 'available'),
                        const SizedBox(width: 6),
                        _filterChip('Withdrawn', 'withdrawn'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 4. Itemized Earnings Ledger List
                earningsAsync.when(
                  data: (entries) {
                    final filtered = _filterEntries(entries);
                    if (filtered.isEmpty) {
                      return _buildEmptyEarningsCard();
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return EarningTile(entry: filtered[index]);
                      },
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(color: AppColors.brandIndigo),
                    ),
                  ),
                  error: (_, __) => _buildEmptyEarningsCard(),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroWalletCard(CreatorWallet wallet, bool canWithdraw, double minWithdrawal) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.success.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_open_rounded, color: AppColors.success, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'AVAILABLE CASH BALANCE',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('USD (\$)', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Big Balance Text
          Text(
            wallet.formattedAvailable,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 16),

          // Sub-balances row (Pending, Lifetime, Withdrawn)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statColumn('Pending', wallet.formattedPending, Colors.white70),
                Container(width: 1, height: 28, color: Colors.white12),
                _statColumn('Lifetime', wallet.formattedLifetime, AppColors.coinGold),
                Container(width: 1, height: 28, color: Colors.white12),
                _statColumn('Withdrawn', wallet.formattedWithdrawn, AppColors.brandBlue),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Request Withdrawal Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                if (!canWithdraw) {
                  _showWithdrawalThresholdDialog(minWithdrawal, wallet.availableEarningsUsd);
                } else {
                  _showWithdrawalNotice(wallet.availableEarningsUsd);
                }
              },
              icon: Icon(
                canWithdraw ? Icons.payments_rounded : Icons.lock_outline_rounded,
                size: 20,
                color: canWithdraw ? Colors.black : Colors.white70,
              ),
              label: Text(
                canWithdraw
                    ? 'Request Cash Payout'
                    : 'Withdrawal Threshold: \$${minWithdrawal.toStringAsFixed(2)} Min',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: canWithdraw ? Colors.black : Colors.white70,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: canWithdraw ? AppColors.coinGold : Colors.white12,
                foregroundColor: canWithdraw ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyCard(dynamic rule) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart_rounded, color: AppColors.coinGold, size: 20),
              SizedBox(width: 8),
              Text(
                'Financial Split & Accounting Policy',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _policyBox('Creator Share', '70%', AppColors.success),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _policyBox('Platform Share', '30%', AppColors.brandPink),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _policyBox('Exchange Rate', '500 = \$1.00', AppColors.coinGold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Coins received from gifts are automatically converted into withdrawable USD and stored safely in your creator financial wallet.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyEarningsCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: const Center(
        child: Column(
          children: [
            Icon(Icons.card_giftcard_rounded, color: Colors.white24, size: 48),
            SizedBox(height: 12),
            Text(
              'No gift earnings recorded yet',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 6),
            Text(
              'Start random video chats! When callers send you virtual gifts (Hearts, Roses, Diamonds, Crowns), your 70% cash earnings will appear here instantly.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _policyBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _statColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _filterChip(String label, String key) {
    final isSelected = _selectedFilter == key;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = key),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandIndigo : Colors.white10,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  List<CreatorEarningEntry> _filterEntries(List<CreatorEarningEntry> entries) {
    if (_selectedFilter == 'available') {
      return entries.where((e) => e.isAvailable).toList();
    } else if (_selectedFilter == 'withdrawn') {
      return entries.where((e) => e.isWithdrawn).toList();
    }
    return entries;
  }

  void _showWithdrawalThresholdDialog(double min, double available) {
    final diff = min - available;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.brandIndigo),
        ),
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.coinGold, size: 26),
            SizedBox(width: 10),
            Text('Minimum Threshold', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'You need at least \$${min.toStringAsFixed(2)} USD in available earnings to request a bank withdrawal.\n\nYou currently have \$${available.toStringAsFixed(2)} USD (need \$${diff.toStringAsFixed(2)} USD more).',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: AppColors.brandIndigo, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showWithdrawalNotice(double available) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.success),
        ),
        title: const Row(
          children: [
            Icon(Icons.account_balance_rounded, color: AppColors.success, size: 26),
            SizedBox(width: 10),
            Text('Withdrawal Payouts', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'You have \$${available.toStringAsFixed(2)} USD ready for payout!\n\nWithdrawal requests and beneficiary payout account management will be unlocked in the upcoming Withdrawal Phase.',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.black,
            ),
            child: const Text('Got It', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

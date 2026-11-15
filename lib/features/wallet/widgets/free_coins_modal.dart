import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/supabase_service.dart';
import '../../auth/auth_modal.dart';

/// 7-Day Free Coins Daily Reward Modal
///
/// Progressive Rewards:
/// Day 1: 50 coins
/// Day 2: 100 coins
/// Day 3: 150 coins
/// Day 4: 200 coins
/// Day 5: 250 coins
/// Day 6: 300 coins
/// Day 7: 350 coins
class FreeCoinsModal extends StatefulWidget {
  const FreeCoinsModal({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const FreeCoinsModal(),
    );
  }

  @override
  State<FreeCoinsModal> createState() => _FreeCoinsModalState();
}

class _FreeCoinsModalState extends State<FreeCoinsModal> {
  bool _isClaiming = false;
  String? _statusMessage;

  static const List<int> _rewards = [50, 100, 150, 200, 250, 300, 350];

  Future<void> _handleClaim() async {
    final service = SupabaseService.instance;
    final profile = service.currentProfile;

    if (profile == null || profile.isAnonymous) {
      Navigator.of(context).pop();
      AuthModal.show(context);
      return;
    }

    if (!profile.canClaimDailyReward) {
      setState(() {
        _statusMessage = 'You already claimed your reward today! Check back tomorrow.';
      });
      return;
    }

    setState(() => _isClaiming = true);

    try {
      final res = await service.claimDailyFreeCoins();
      if (!mounted) return;

      if (res['success'] == true) {
        setState(() {
          _isClaiming = false;
          _statusMessage = '🎉 Successfully claimed ${res['coins_awarded']} Coins!';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.brandIndigo,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.stars_rounded, color: AppColors.coinGold, size: 20),
                const SizedBox(width: 8),
                Text('Claimed Day ${res['day']} Reward: +${res['coins_awarded']} Coins!'),
              ],
            ),
          ),
        );
      } else {
        setState(() {
          _isClaiming = false;
          _statusMessage = res['message']?.toString() ?? 'Already claimed today.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isClaiming = false;
        _statusMessage = 'Error claiming reward: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final service = SupabaseService.instance;
    final profile = service.currentProfile;
    final isGuest = profile == null || profile.isAnonymous;

    final canClaim = !isGuest && profile.canClaimDailyReward;
    final activeDay = isGuest ? 1 : profile.nextDailyRewardDay;
    final streak = isGuest ? 0 : profile.dailyStreak;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B182B) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: const Color(0xFFFFD700).withOpacity(0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withOpacity(0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row: Title & Close Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          gradient: AppColors.vipGoldGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.card_giftcard_rounded, color: Colors.black, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '7-Day Free Coins',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'Claim up to 350 Coins daily!',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: isDark ? Colors.white60 : Colors.black45),
                    splashRadius: 20,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Streak Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF26213D) : const Color(0xFFF3F0FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.brandIndigo.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_fire_department_rounded, color: Colors.deepOrangeAccent, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isGuest ? 'Sign in to start streak' : 'Current Streak: $streak Day${streak == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            canClaim
                                ? 'Day $activeDay reward of ${_rewards[activeDay - 1]} Coins ready to claim!'
                                : (!isGuest
                                    ? 'Claimed today! Next reward unlocks tomorrow.'
                                    : 'Log in to claim your Day 1 50 Coins!'),
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 7 Days Grid / List
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 7,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.88,
                ),
                itemBuilder: (ctx, index) {
                  final day = index + 1;
                  final coins = _rewards[index];
                  final isClaimed = !isGuest && (canClaim ? day < activeDay : day <= streak);
                  final isCurrent = !isGuest && canClaim && day == activeDay;
                  final isMegaDay = day == 7;

                  Color cardBg;
                  Border border;

                  if (isCurrent) {
                    cardBg = isDark ? const Color(0xFF3B311B) : const Color(0xFFFFF9E6);
                    border = Border.all(color: const Color(0xFFFFD700), width: 2);
                  } else if (isClaimed) {
                    cardBg = isDark ? const Color(0xFF1B2E24) : const Color(0xFFE8F5E9);
                    border = Border.all(color: AppColors.success.withOpacity(0.5), width: 1.2);
                  } else {
                    cardBg = isDark ? const Color(0xFF221E36) : const Color(0xFFF7F7FA);
                    border = Border.all(
                      color: isMegaDay
                          ? const Color(0xFFFFD700).withOpacity(0.4)
                          : (isDark ? Colors.white10 : Colors.black12),
                      width: 1,
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: border,
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: const Color(0xFFFFD700).withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Day $day',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isCurrent
                                ? const Color(0xFFFFD700)
                                : (isDark ? Colors.white70 : Colors.black54),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (isClaimed)
                          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 24)
                        else if (isMegaDay)
                          const Text('🎁', style: TextStyle(fontSize: 22))
                        else
                          const Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 24),
                        const SizedBox(height: 4),
                        Text(
                          '+$coins',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: isClaimed
                                ? AppColors.success
                                : (isCurrent ? const Color(0xFFFFD700) : (isDark ? Colors.white : Colors.black87)),
                          ),
                        ),
                        if (isClaimed)
                          const Text(
                            'Claimed',
                            style: TextStyle(fontSize: 9, color: AppColors.success, fontWeight: FontWeight.bold),
                          )
                        else if (isCurrent)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD700),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'READY',
                              style: TextStyle(fontSize: 8, color: Colors.black, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              if (_statusMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.brandIndigo.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Primary Action Button
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isGuest
                        ? AppColors.brandIndigo
                        : (canClaim ? const Color(0xFFFFD700) : (isDark ? Colors.white12 : Colors.black12)),
                    foregroundColor: isGuest || !canClaim ? Colors.white : Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: canClaim ? 4 : 0,
                  ),
                  onPressed: _isClaiming
                      ? null
                      : (isGuest
                          ? () {
                              Navigator.of(context).pop();
                              AuthModal.show(context);
                            }
                          : (canClaim ? _handleClaim : null)),
                  child: _isClaiming
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(
                          isGuest
                              ? 'Sign In to Claim Daily Coins'
                              : (canClaim
                                  ? 'CLAIM DAY $activeDay (+${_rewards[activeDay - 1]} COINS)'
                                  : 'CLAIMED FOR TODAY • NEXT TOMORROW'),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

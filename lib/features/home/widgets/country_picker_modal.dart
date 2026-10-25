import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/country.dart';
import '../../../services/supabase_service.dart';
import '../../auth/auth_modal.dart';
import '../../shop/shop_modal.dart';

class CountryPickerModal {
  static void show({
    required BuildContext context,
    required String currentCountryCode,
    required void Function(AppCountry country, int coinsDeducted) onCountrySelected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final profile = SupabaseService.instance.currentProfile;
            final userCoins = profile?.coins ?? 0;

            final filteredCountries = kAllCountries.where((c) {
              if (searchQuery.isEmpty) return true;
              return c.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
                  c.code.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.78,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: AppColors.border(context), width: 1.5)),
              ),
              child: Column(
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header with Title & Close
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Country / Region',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.txtPrimary(context),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(modalCtx).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: AppColors.txtSecondary(context),
                      ),
                    ],
                  ),

                  // Coin Balance & Pricing Information Header
                  Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.coinGold.withOpacity(0.12),
                          AppColors.coinGoldDark.withOpacity(0.06),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.coinGold.withOpacity(0.28)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Balance: $userCoins Coins',
                              style: const TextStyle(
                                color: AppColors.coinGoldDark,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          currentCountryCode == 'ALL'
                              ? 'Specific: 10 Coins • Global: Free'
                              : 'Switch: 5 Coins • Global: Free',
                          style: TextStyle(
                            color: AppColors.txtSecondary(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Search Field
                  TextField(
                    onChanged: (val) => setModalState(() => searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search 200+ countries...',
                      hintStyle: TextStyle(color: AppColors.txtMuted(context), fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: AppColors.border(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: AppColors.border(context)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Country List
                  Expanded(
                    child: ListView.separated(
                      itemCount: filteredCountries.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: AppColors.border(context).withOpacity(0.4),
                      ),
                      itemBuilder: (_, index) {
                        final country = filteredCountries[index];
                        final isSelected = currentCountryCode.toUpperCase() == country.code.toUpperCase();
                        final isGlobalOption = country.code.toUpperCase() == 'ALL';

                        final cost = AppCountry.getSelectionCost(
                          currentCode: currentCountryCode,
                          targetCode: country.code,
                        );

                        return ListTile(
                          onTap: () async {
                            if (isSelected) {
                              Navigator.of(modalCtx).pop();
                              return;
                            }

                            if (cost == 0) {
                              // Returning to ALL (Global) is completely Free!
                              Navigator.of(modalCtx).pop();
                              onCountrySelected(country, 0);
                              return;
                            }

                            // 1. Without login, user cannot change the country from global to any country
                            final isGuest = SupabaseService.instance.isGuest;
                            if (isGuest) {
                              _showLoginRequiredForCountryDialog(
                                context: context,
                                modalContext: modalCtx,
                                targetCountry: country,
                              );
                              return;
                            }

                            // 2. Before signup user cannot use coins. If user used bonus coins, show "You need to add topup"
                            final freshCoins = SupabaseService.instance.currentProfile?.coins ?? 0;
                            if (freshCoins < cost) {
                              final hasUsedBonus = SupabaseService.instance.hasUsedJoiningBonus;
                              _showTopupRequiredDialog(
                                context: context,
                                modalContext: modalCtx,
                                requiredCoins: cost,
                                currentCoins: freshCoins,
                                targetCountry: country,
                                hasUsedBonus: hasUsedBonus,
                              );
                              return;
                            }

                            // User has enough coins - deduct and apply
                            final success = await SupabaseService.instance.deductCoins(cost);
                            if (success) {
                              if (modalCtx.mounted) {
                                Navigator.of(modalCtx).pop();
                              }
                              onCountrySelected(country, cost);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppColors.brandIndigo,
                                    duration: const Duration(seconds: 3),
                                    content: Row(
                                      children: [
                                        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            '$cost Coins deducted. Country set to ${country.flag} ${country.name}!',
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          leading: Text(country.flag, style: const TextStyle(fontSize: 24)),
                          title: Text(
                            country.name,
                            style: TextStyle(
                              color: isSelected ? AppColors.brandIndigo : AppColors.txtPrimary(context),
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSelected)
                                const Icon(Icons.check_circle_rounded, color: AppColors.brandIndigo, size: 20)
                              else if (isGlobalOption)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'FREE',
                                    style: TextStyle(
                                      color: AppColors.success,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.coinGold.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.coinGold.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 13),
                                      const SizedBox(width: 3),
                                      Text(
                                        '$cost Coins',
                                        style: const TextStyle(
                                          color: AppColors.coinGoldDark,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static void _showLoginRequiredForCountryDialog({
    required BuildContext context,
    required BuildContext modalContext,
    required AppCountry targetCountry,
  }) {
    showDialog(
      context: context,
      builder: (alertCtx) => AlertDialog(
        backgroundColor: AppColors.surfElevated(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.brandIndigo.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded, color: AppColors.brandIndigo, size: 24),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Sign In Required',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Without logging in, you cannot change from Global to any country.\n\nSign in with Google to unlock 200+ countries, receive bonus coins, and start chat filtering!',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.txtPrimary(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandIndigo.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.brandIndigo.withOpacity(0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.public_rounded, color: AppColors.brandIndigo, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Global (Worldwide) chat is always 100% Free with unlimited stranger calls!',
                      style: TextStyle(fontSize: 12, color: AppColors.brandIndigo, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(alertCtx).pop(),
            child: Text('Keep Free Global', style: TextStyle(color: AppColors.txtSecondary(context))),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(alertCtx).pop();
              Navigator.of(modalContext).pop();
              AuthModal.show(context);
            },
            icon: const Icon(Icons.login_rounded, size: 16),
            label: const Text('Sign In with Google', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandIndigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  static void _showTopupRequiredDialog({
    required BuildContext context,
    required BuildContext modalContext,
    required int requiredCoins,
    required int currentCoins,
    required AppCountry targetCountry,
    required bool hasUsedBonus,
  }) {
    showDialog(
      context: context,
      builder: (alertCtx) => AlertDialog(
        backgroundColor: AppColors.surfElevated(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.coinGold.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 24),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Top-up Required',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasUsedBonus
                  ? 'You have already used your starter joining bonus. You need to add topup to filter by ${targetCountry.flag} ${targetCountry.name}.\n\nRequired: $requiredCoins Coins • Your Balance: $currentCoins Coins.'
                  : 'Filtering by ${targetCountry.flag} ${targetCountry.name} requires $requiredCoins Coins.\n\nYour current balance: $currentCoins Coins. Please add topup to proceed.',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.txtPrimary(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withOpacity(0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.public_rounded, color: AppColors.success, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Global (Worldwide) Random Chat is always 100% Free with unlimited calls!',
                      style: TextStyle(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(alertCtx).pop(),
            child: Text('Keep Free Global', style: TextStyle(color: AppColors.txtSecondary(context))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(alertCtx).pop();
              Navigator.of(modalContext).pop();
              ShopModal.show(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coinGold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Add Topup', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

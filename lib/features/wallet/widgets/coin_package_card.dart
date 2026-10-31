import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/coin_package.dart';

class CoinPackageCard extends StatelessWidget {
  final CoinPackage package;
  final bool isSelected;
  final bool isProcessing;
  final VoidCallback onTap;

  const CoinPackageCard({
    super.key,
    required this.package,
    this.isSelected = false,
    this.isProcessing = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasBadge = package.badge != null && package.badge!.isNotEmpty;
    final isPopular = package.isPopular || package.badge == 'POPULAR';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isPopular ? AppColors.brandIndigo.withOpacity(0.12) : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? AppColors.coinGold
              : isPopular
                  ? AppColors.brandIndigo.withOpacity(0.5)
                  : AppColors.surfaceBorder,
          width: isSelected || isPopular ? 1.5 : 1.0,
        ),
        boxShadow: isPopular
            ? [
                BoxShadow(
                  color: AppColors.brandIndigo.withOpacity(0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: isProcessing ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon Avatar
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: isPopular
                        ? AppColors.primaryGradient
                        : LinearGradient(
                            colors: [AppColors.coinGold.withOpacity(0.2), AppColors.coinGoldDark.withOpacity(0.1)],
                          ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 28),
                  ),
                ),
                const SizedBox(width: 14),

                // Package Title, Coins & Minutes
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              package.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hasBadge) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: isPopular ? AppColors.vipGoldGradient : AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                package.badge!,
                                style: TextStyle(
                                  color: isPopular ? Colors.black87 : Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${package.coins} Coins',
                            style: const TextStyle(
                              color: AppColors.coinGold,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('•', style: TextStyle(color: AppColors.textMuted)),
                          const SizedBox(width: 6),
                          Text(
                            '${package.minutes} mins VIP',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Price Button
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: isProcessing && isSelected
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\$${package.priceUsd.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            if (package.priceRs > 0)
                              Text(
                                'Rs. ${package.priceRs}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.75),
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

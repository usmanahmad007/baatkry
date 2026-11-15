import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reusable avatar widget that visually distinguishes a VIP user from a Normal user.
///
/// For VIP users:
/// - A glowing golden/amber circular ring surrounds their profile picture.
/// - A prominent "VIP" badge is stamped on the circle.
///
/// For Normal users:
/// - A standard, clean border without the VIP golden ring or badge.
class VipAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String nickname;
  final double radius;
  final bool isVip;
  final bool showVipBadge;
  final VoidCallback? onTap;

  const VipAvatar({
    super.key,
    this.avatarUrl,
    this.nickname = 'User',
    this.radius = 24,
    this.isVip = false,
    this.showVipBadge = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ringWidth = (radius * 0.10).clamp(2.0, 3.5);
    final badgeFontSize = (radius * 0.36).clamp(7.5, 11.0);

    Widget avatarCore = CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.brandIndigo,
      backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
          ? NetworkImage(avatarUrl!)
          : null,
      onBackgroundImageError: (avatarUrl != null && avatarUrl!.isNotEmpty)
          ? (_, __) {}
          : null,
      child: (avatarUrl == null || avatarUrl!.isEmpty)
          ? Text(
              nickname.isNotEmpty ? nickname[0].toUpperCase() : 'B',
              style: TextStyle(
                fontSize: radius * 0.75,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            )
          : null,
    );

    Widget wrappedAvatar;
    if (isVip) {
      wrappedAvatar = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 1. VIP Golden Shimmering Ring
          Container(
            padding: EdgeInsets.all(ringWidth),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFFDF00),
                  Color(0xFFFFA500),
                  Color(0xFFFFD700),
                  Color(0xFFFFE082),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD700).withOpacity(0.55),
                  blurRadius: radius * 0.40,
                  spreadRadius: 1.0,
                ),
              ],
            ),
            child: avatarCore,
          ),

          // 2. VIP Stamp / Badge directly on the profile circle
          if (showVipBadge)
            Positioned(
              bottom: -2,
              right: -2,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: (radius * 0.20).clamp(3.5, 6.0),
                  vertical: 1.0,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFF59E0B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black, width: 1.2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('👑', style: TextStyle(fontSize: 8)),
                    const SizedBox(width: 2),
                    Text(
                      'VIP',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: badgeFontSize,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    } else {
      // Normal User: Standard Clean Avatar
      wrappedAvatar = Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1.2),
        ),
        child: avatarCore,
      );
    }

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius + 4),
        child: wrappedAvatar,
      );
    }

    return wrappedAvatar;
  }
}

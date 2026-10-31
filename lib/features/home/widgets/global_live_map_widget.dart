import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';

class GlobalLiveMapWidget extends ConsumerStatefulWidget {
  final String selectedCountry;
  final String selectedCountryCode;
  final String selectedCountryFlag;
  final VoidCallback onOpenCountryPicker;

  const GlobalLiveMapWidget({
    super.key,
    required this.selectedCountry,
    required this.selectedCountryCode,
    required this.selectedCountryFlag,
    required this.onOpenCountryPicker,
  });

  @override
  ConsumerState<GlobalLiveMapWidget> createState() => _GlobalLiveMapWidgetState();
}

class _GlobalLiveMapWidgetState extends ConsumerState<GlobalLiveMapWidget> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  int get totalLiveCount => ref.watch(currentLiveUsersCountProvider);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGlobal = widget.selectedCountryCode == 'ALL';

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.cardGrad(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border(context), width: 1.2),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Live Users count in numbers
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Animated pulsing green Live dot
                        AnimatedBuilder(
                          animation: _animController,
                          builder: (_, __) {
                            final pulse = (math.sin(_animController.value * math.pi * 2) + 1) / 2;
                            return Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.success,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.success.withOpacity(0.4 + 0.5 * pulse),
                                    blurRadius: 6 + 6 * pulse,
                                    spreadRadius: 1 + 2 * pulse,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'LIVE GLOBAL USERS',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w800,
                            color: isDark ? AppColors.brandPink : AppColors.brandIndigo,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${totalLiveCount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} Online Now',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: AppColors.txtPrimary(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
                // Current Mode Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isGlobal
                        ? AppColors.success.withOpacity(0.12)
                        : AppColors.coinGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isGlobal
                          ? AppColors.success.withOpacity(0.3)
                          : AppColors.coinGold.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isGlobal ? '🌍 Worldwide' : '${widget.selectedCountryFlag} Filtered',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isGlobal ? AppColors.success : AppColors.coinGoldDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Interactive / Animated World Map Canvas
          GestureDetector(
            onTap: widget.onOpenCountryPicker,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                height: 185,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
                  ),
                ),
                child: Stack(
                  children: [
                    // Canvas with Continents, Hubs, and Arcs
                    AnimatedBuilder(
                      animation: _animController,
                      builder: (ctx, _) {
                        return CustomPaint(
                          size: const Size(double.infinity, 185),
                          painter: WorldMapPainter(
                            animationProgress: _animController.value,
                            isDark: isDark,
                            selectedCountryCode: widget.selectedCountryCode,
                          ),
                        );
                      },
                    ),

                    // Overlay Map Badge indicating live traffic
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.black : Colors.white).withOpacity(0.75),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border(context).withOpacity(0.4)),
                        ),
                        child: Text(
                          'Active across 195+ Countries',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.txtSecondary(context),
                          ),
                        ),
                      ),
                    ),

                    // Selected Country Pin overlay if specific country is picked
                    if (!isGlobal)
                      Positioned(
                        bottom: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.brandIndigo.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.brandIndigo.withOpacity(0.4),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(widget.selectedCountryFlag, style: const TextStyle(fontSize: 13)),
                              const SizedBox(width: 5),
                              Text(
                                widget.selectedCountry,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Tap to Switch prompt on bottom right of map
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.black : Colors.white).withOpacity(0.8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.touch_app_rounded, size: 12, color: AppColors.txtMuted(context)),
                            const SizedBox(width: 4),
                            Text(
                              'Tap map to change',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.txtMuted(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Bottom Quick Country Switcher Pill & Coin Cost details
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: InkWell(
              onTap: widget.onOpenCountryPicker,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfElevated(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: Row(
                  children: [
                    Text(widget.selectedCountryFlag, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.selectedCountry,
                            style: TextStyle(
                              color: AppColors.txtPrimary(context),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            isGlobal
                                ? 'Worldwide Queue • Free Unlimited Matches'
                                : 'Filtered by Country • Coins Applied',
                            style: TextStyle(
                              color: AppColors.txtSecondary(context),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Action button with cost indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.brandIndigo.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.brandIndigo.withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isGlobal ? 'Select (10 🪙)' : 'Switch (5 🪙)',
                            style: const TextStyle(
                              color: AppColors.brandIndigo,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: AppColors.brandIndigo),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// World Map Custom Painter
// Renders continents, active hubs with pulsating radar rings, and live arcs
// ---------------------------------------------------------------------------
class WorldMapPainter extends CustomPainter {
  final double animationProgress;
  final bool isDark;
  final String selectedCountryCode;

  WorldMapPainter({
    required this.animationProgress,
    required this.isDark,
    required this.selectedCountryCode,
  });

  // Global regional hubs (normalized x: 0..1, y: 0..1, name)
  static const List<MapHub> hubs = [
    MapHub('North America East', 'US', 0.26, 0.36),
    MapHub('North America West', 'US', 0.16, 0.38),
    MapHub('South America', 'BR', 0.32, 0.68),
    MapHub('Europe West', 'GB', 0.48, 0.28),
    MapHub('Europe Central', 'DE', 0.53, 0.29),
    MapHub('Middle East', 'AE', 0.61, 0.43),
    MapHub('South Asia (PK/IN)', 'PK', 0.68, 0.44),
    MapHub('East Asia (JP/KR)', 'JP', 0.84, 0.36),
    MapHub('Southeast Asia', 'ID', 0.78, 0.58),
    MapHub('Australia', 'AU', 0.86, 0.76),
    MapHub('North Africa', 'EG', 0.55, 0.42),
    MapHub('South Africa', 'ZA', 0.56, 0.74),
  ];

  // Intercontinental connection pairs for live arcs
  static const List<List<int>> connectionPairs = [
    [0, 3], // US East -> Europe West
    [3, 5], // Europe West -> Middle East
    [5, 6], // Middle East -> South Asia
    [6, 7], // South Asia -> East Asia
    [1, 7], // US West -> East Asia (Pacific connection)
    [0, 2], // US East -> South America
    [3, 10], // Europe -> North Africa
    [6, 8], // South Asia -> Southeast Asia
    [8, 9], // Southeast Asia -> Australia
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Draw subtle background dotted grid
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.04)
      ..style = PaintingStyle.fill;

    for (double gx = 16; gx < w; gx += 20) {
      for (double gy = 14; gy < h; gy += 18) {
        canvas.drawCircle(Offset(gx, gy), 1.0, gridPaint);
      }
    }

    // 2. Draw continent landmass silhouettes
    _drawContinents(canvas, size);

    // 3. Draw curved live connection arcs between continents
    _drawConnectionArcs(canvas, size);

    // 4. Draw regional hubs with animated radar ripples
    _drawHubs(canvas, size);
  }

  void _drawContinents(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final continentPaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1)
      ..style = PaintingStyle.fill;

    // North America
    final naPath = Path()
      ..moveTo(w * 0.10, h * 0.18)
      ..lineTo(w * 0.28, h * 0.18)
      ..lineTo(w * 0.32, h * 0.24)
      ..lineTo(w * 0.27, h * 0.42)
      ..lineTo(w * 0.22, h * 0.50)
      ..lineTo(w * 0.17, h * 0.42)
      ..lineTo(w * 0.12, h * 0.32)
      ..close();
    canvas.drawPath(naPath, continentPaint);

    // Greenland
    final glPath = Path()
      ..moveTo(w * 0.34, h * 0.12)
      ..lineTo(w * 0.39, h * 0.13)
      ..lineTo(w * 0.37, h * 0.19)
      ..lineTo(w * 0.33, h * 0.17)
      ..close();
    canvas.drawPath(glPath, continentPaint);

    // South America
    final saPath = Path()
      ..moveTo(w * 0.25, h * 0.54)
      ..lineTo(w * 0.33, h * 0.57)
      ..lineTo(w * 0.36, h * 0.67)
      ..lineTo(w * 0.32, h * 0.84)
      ..lineTo(w * 0.28, h * 0.82)
      ..lineTo(w * 0.26, h * 0.66)
      ..close();
    canvas.drawPath(saPath, continentPaint);

    // Europe
    final euPath = Path()
      ..moveTo(w * 0.46, h * 0.24)
      ..lineTo(w * 0.54, h * 0.23)
      ..lineTo(w * 0.55, h * 0.34)
      ..lineTo(w * 0.45, h * 0.36)
      ..lineTo(w * 0.44, h * 0.30)
      ..close();
    canvas.drawPath(euPath, continentPaint);

    // Africa
    final afPath = Path()
      ..moveTo(w * 0.45, h * 0.40)
      ..lineTo(w * 0.58, h * 0.40)
      ..lineTo(w * 0.60, h * 0.54)
      ..lineTo(w * 0.56, h * 0.77)
      ..lineTo(w * 0.52, h * 0.76)
      ..lineTo(w * 0.46, h * 0.56)
      ..close();
    canvas.drawPath(afPath, continentPaint);

    // Asia
    final asPath = Path()
      ..moveTo(w * 0.56, h * 0.20)
      ..lineTo(w * 0.84, h * 0.20)
      ..lineTo(w * 0.85, h * 0.38)
      ..lineTo(w * 0.78, h * 0.52)
      ..lineTo(w * 0.68, h * 0.48)
      ..lineTo(w * 0.60, h * 0.36)
      ..close();
    canvas.drawPath(asPath, continentPaint);

    // Australia
    final auPath = Path()
      ..moveTo(w * 0.81, h * 0.69)
      ..lineTo(w * 0.89, h * 0.70)
      ..lineTo(w * 0.88, h * 0.81)
      ..lineTo(w * 0.82, h * 0.80)
      ..close();
    canvas.drawPath(auPath, continentPaint);
  }

  void _drawConnectionArcs(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    for (int i = 0; i < connectionPairs.length; i++) {
      final pair = connectionPairs[i];
      final hubA = hubs[pair[0]];
      final hubB = hubs[pair[1]];

      final p1 = Offset(hubA.x * w, hubA.y * h);
      final p2 = Offset(hubB.x * w, hubB.y * h);

      // Quadratic curve bending upwards
      final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2 - 16);

      final arcPath = Path()
        ..moveTo(p1.dx, p1.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, p2.dx, p2.dy);

      // Base faint arc line
      final arcPaint = Paint()
        ..color = (isDark ? AppColors.brandIndigo : const Color(0xFF6366F1)).withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawPath(arcPath, arcPaint);

      // Animated traveling light pulse along the arc
      final t = (animationProgress + i * 0.15) % 1.0;
      // Evaluate quadratic Bezier point at t
      final curX = (1 - t) * (1 - t) * p1.dx + 2 * (1 - t) * t * mid.dx + t * t * p2.dx;
      final curY = (1 - t) * (1 - t) * p1.dy + 2 * (1 - t) * t * mid.dy + t * t * p2.dy;

      final pulsePaint = Paint()
        ..color = isDark ? AppColors.brandPink : AppColors.brandIndigo
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(curX, curY), 2.0, pulsePaint);
    }
  }

  void _drawHubs(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    for (final hub in hubs) {
      final center = Offset(hub.x * w, hub.y * h);
      final isCountryTarget = selectedCountryCode.toUpperCase() == hub.countryCode;

      // Animated radar ripple rings
      final rippleRadius = 4.0 + 12.0 * animationProgress;
      final rippleAlpha = (1.0 - animationProgress).clamp(0.0, 1.0);

      final ripplePaint = Paint()
        ..color = (isCountryTarget
                ? AppColors.coinGold
                : (isDark ? AppColors.brandIndigo : const Color(0xFF6366F1)))
            .withOpacity(0.4 * rippleAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isCountryTarget ? 2.0 : 1.2;
      canvas.drawCircle(center, rippleRadius, ripplePaint);

      // Center solid hub dot
      final dotPaint = Paint()
        ..color = isCountryTarget
            ? AppColors.coinGold
            : (isDark ? Colors.white : AppColors.brandIndigo)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, isCountryTarget ? 4.5 : 2.8, dotPaint);

      // Glowing outer ring for targeted country
      if (isCountryTarget) {
        final targetRing = Paint()
          ..color = AppColors.coinGold.withOpacity(0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(center, 7.0, targetRing);
      }
    }
  }

  @override
  bool shouldRepaint(covariant WorldMapPainter oldDelegate) {
    return oldDelegate.animationProgress != animationProgress ||
        oldDelegate.selectedCountryCode != selectedCountryCode ||
        oldDelegate.isDark != isDark;
  }
}

class MapHub {
  final String name;
  final String countryCode;
  final double x;
  final double y;

  const MapHub(this.name, this.countryCode, this.x, this.y);
}

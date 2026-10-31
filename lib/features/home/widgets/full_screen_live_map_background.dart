import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/supabase_service.dart';

class FullScreenLiveUsersMapBackground extends ConsumerStatefulWidget {
  const FullScreenLiveUsersMapBackground({super.key});

  @override
  ConsumerState<FullScreenLiveUsersMapBackground> createState() => _FullScreenLiveUsersMapBackgroundState();
}

class _FullScreenLiveUsersMapBackgroundState extends ConsumerState<FullScreenLiveUsersMapBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final countryCounts = ref.watch(currentCountryCountsProvider);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: FullScreenWorldMapPainter(
              animationProgress: _animController.value,
              isDark: isDark,
              countryCounts: countryCounts,
            ),
          );
        },
      ),
    );
  }
}

class FullScreenWorldMapPainter extends CustomPainter {
  final double animationProgress;
  final bool isDark;
  final Map<String, int> countryCounts;

  FullScreenWorldMapPainter({
    required this.animationProgress,
    required this.isDark,
    this.countryCounts = const {},
  });

  // Global regional hubs (normalized x: 0..1, y: 0..1, name, live user load)
  static const List<LiveHub> hubs = [
    LiveHub('North America East', 'US', 0.22, 0.32),
    LiveHub('North America West', 'US', 0.14, 0.35),
    LiveHub('South America', 'BR', 0.29, 0.68),
    LiveHub('Europe West', 'GB', 0.47, 0.27),
    LiveHub('Europe Central', 'DE', 0.52, 0.26),
    LiveHub('Middle East', 'AE', 0.60, 0.40),
    LiveHub('South Asia (PK/IN)', 'PK', 0.67, 0.42),
    LiveHub('East Asia (JP/KR)', 'JP', 0.82, 0.33),
    LiveHub('Southeast Asia', 'ID', 0.77, 0.56),
    LiveHub('Australia', 'AU', 0.85, 0.75),
    LiveHub('North Africa', 'EG', 0.54, 0.40),
    LiveHub('South Africa', 'ZA', 0.55, 0.73),
  ];

  // Intercontinental connection pairs for animated live arcs
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
    [10, 11], // North Africa -> South Africa
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Deep atmospheric background
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.2,
        colors: isDark
            ? [
                const Color(0xFF0F172A),
                const Color(0xFF0A0F1D),
                const Color(0xFF030712),
              ]
            : [
                const Color(0xFFF8FAFC),
                const Color(0xFFF1F5F9),
                const Color(0xFFE2E8F0),
              ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    // 2. High-tech global coordinate dotted grid spanning full screen
    final gridDotPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.04)
      ..style = PaintingStyle.fill;

    const stepX = 28.0;
    const stepY = 28.0;
    for (double x = 14; x < w; x += stepX) {
      for (double y = 14; y < h; y += stepY) {
        canvas.drawCircle(Offset(x, y), 0.85, gridDotPaint);
      }
    }

    // 3. Draw continent landmass silhouettes (proportional across viewport)
    _drawContinents(canvas, size);

    // 4. Draw curved live connection arcs between continents with traveling particles
    _drawConnectionArcs(canvas, size);

    // 5. Draw live hubs with pulsing radar ripples and authentic live user markers
    _drawHubs(canvas, size);

    // 6. Subtle corner vignette gradient for high foreground readability
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [
          Colors.transparent,
          Colors.transparent,
          (isDark ? Colors.black : Colors.white).withOpacity(0.35),
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), vignettePaint);
  }

  void _drawContinents(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final continentPaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B).withOpacity(0.45) : const Color(0xFFCBD5E1).withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = isDark ? const Color(0xFF334155).withOpacity(0.6) : const Color(0xFF94A3B8).withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    void drawRegion(List<Offset> points) {
      if (points.length < 3) return;
      final path = Path()..moveTo(points[0].dx * w, points[0].dy * h);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx * w, points[i].dy * h);
      }
      path.close();
      canvas.drawPath(path, continentPaint);
      canvas.drawPath(path, borderPaint);
    }

    // North America
    drawRegion([
      const Offset(0.08, 0.20),
      const Offset(0.16, 0.16),
      const Offset(0.24, 0.18),
      const Offset(0.28, 0.28),
      const Offset(0.23, 0.40),
      const Offset(0.18, 0.44),
      const Offset(0.15, 0.36),
      const Offset(0.09, 0.32),
    ]);

    // South America
    drawRegion([
      const Offset(0.25, 0.48),
      const Offset(0.32, 0.52),
      const Offset(0.34, 0.65),
      const Offset(0.29, 0.82),
      const Offset(0.24, 0.76),
      const Offset(0.23, 0.58),
    ]);

    // Europe
    drawRegion([
      const Offset(0.44, 0.18),
      const Offset(0.54, 0.17),
      const Offset(0.56, 0.26),
      const Offset(0.50, 0.32),
      const Offset(0.45, 0.29),
      const Offset(0.43, 0.24),
    ]);

    // Africa
    drawRegion([
      const Offset(0.45, 0.36),
      const Offset(0.58, 0.36),
      const Offset(0.60, 0.50),
      const Offset(0.56, 0.72),
      const Offset(0.51, 0.74),
      const Offset(0.45, 0.58),
      const Offset(0.43, 0.44),
    ]);

    // Asia
    drawRegion([
      const Offset(0.57, 0.16),
      const Offset(0.82, 0.18),
      const Offset(0.88, 0.30),
      const Offset(0.82, 0.45),
      const Offset(0.74, 0.46),
      const Offset(0.68, 0.52),
      const Offset(0.62, 0.42),
      const Offset(0.58, 0.30),
    ]);

    // Australia
    drawRegion([
      const Offset(0.79, 0.64),
      const Offset(0.88, 0.63),
      const Offset(0.90, 0.74),
      const Offset(0.85, 0.82),
      const Offset(0.78, 0.76),
    ]);
  }

  void _drawConnectionArcs(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    for (int i = 0; i < connectionPairs.length; i++) {
      final pair = connectionPairs[i];
      final h1 = hubs[pair[0]];
      final h2 = hubs[pair[1]];

      final p1 = Offset(h1.x * w, h1.y * h);
      final p2 = Offset(h2.x * w, h2.y * h);

      // Quadratic curve bending upwards
      final mid = Offset((p1.dx + p2.dx) / 2, math.min(p1.dy, p2.dy) - 35);
      final arcPath = Path()
        ..moveTo(p1.dx, p1.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, p2.dx, p2.dy);

      final arcPaint = Paint()
        ..color = (isDark ? AppColors.brandIndigo : const Color(0xFF6366F1))
            .withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawPath(arcPath, arcPaint);

      // Moving photon/light pulse along the arc
      final t = (animationProgress + i * 0.12) % 1.0;
      final curX = (1 - t) * (1 - t) * p1.dx + 2 * (1 - t) * t * mid.dx + t * t * p2.dx;
      final curY = (1 - t) * (1 - t) * p1.dy + 2 * (1 - t) * t * mid.dy + t * t * p2.dy;

      final pulsePaint = Paint()
        ..color = isDark ? AppColors.brandPink : AppColors.brandIndigo
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(curX, curY), 2.4, pulsePaint);
    }
  }

  void _drawHubs(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final myCountryCode = (SupabaseService.instance.currentProfile?.countryCode ?? 'ALL').toUpperCase();

    for (final hub in hubs) {
      final center = Offset(hub.x * w, hub.y * h);
      final rawCount = countryCounts[hub.countryCode] ?? 0;
      final isMyCountry = hub.countryCode == myCountryCode;
      final hubLiveCount = rawCount > 0 ? rawCount : (isMyCountry ? 1 : 0);
      final hasLiveUsers = hubLiveCount > 0;

      // Expanding radar ripple rings for hubs with live users
      if (hasLiveUsers) {
        final rippleRadius = 5.0 + 16.0 * animationProgress;
        final rippleAlpha = (1.0 - animationProgress).clamp(0.0, 1.0);

        final ripplePaint = Paint()
          ..color = (isDark ? AppColors.brandIndigo : const Color(0xFF6366F1))
              .withOpacity(0.35 * rippleAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawCircle(center, rippleRadius, ripplePaint);
      }

      // Core pulsating hub dot
      final corePaint = Paint()
        ..color = hasLiveUsers
            ? (isDark ? Colors.white : AppColors.brandIndigo)
            : (isDark ? Colors.white.withOpacity(0.3) : Colors.black.withOpacity(0.2));
      canvas.drawCircle(center, hasLiveUsers ? 3.2 : 2.0, corePaint);

      if (hasLiveUsers) {
        // Inner glow
        final glowPaint = Paint()
          ..color = (isDark ? AppColors.brandPink : AppColors.brandIndigo).withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawCircle(center, 5.5, glowPaint);

        // Authentic live user badge near hub
        final textSpan = TextSpan(
          children: [
            TextSpan(
              text: '${hub.countryCode} ',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: '• $hubLiveCount live',
              style: TextStyle(
                color: isDark ? AppColors.brandPink : AppColors.brandIndigo,
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
        final tp = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        final pillRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(center.dx + 8, center.dy - 7, tp.width + 8, tp.height + 4),
          const Radius.circular(6),
        );
        final pillPaint = Paint()
          ..color = (isDark ? Colors.black : Colors.white).withOpacity(0.65);
        canvas.drawRRect(pillRect, pillPaint);
        tp.paint(canvas, Offset(center.dx + 12, center.dy - 5));
      }
    }
  }

  @override
  bool shouldRepaint(covariant FullScreenWorldMapPainter oldDelegate) {
    return oldDelegate.animationProgress != animationProgress ||
        oldDelegate.isDark != isDark ||
        oldDelegate.countryCounts != countryCounts;
  }
}

class LiveHub {
  final String name;
  final String countryCode;
  final double x;
  final double y;

  const LiveHub(this.name, this.countryCode, this.x, this.y);
}

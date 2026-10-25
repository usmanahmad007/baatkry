import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class FullScreenLiveUsersMapBackground extends StatefulWidget {
  const FullScreenLiveUsersMapBackground({super.key});

  @override
  State<FullScreenLiveUsersMapBackground> createState() => _FullScreenLiveUsersMapBackgroundState();
}

class _FullScreenLiveUsersMapBackgroundState extends State<FullScreenLiveUsersMapBackground>
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

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: FullScreenWorldMapPainter(
              animationProgress: _animController.value,
              isDark: isDark,
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

  FullScreenWorldMapPainter({
    required this.animationProgress,
    required this.isDark,
  });

  // Global regional hubs (normalized x: 0..1, y: 0..1, name, live user load)
  static const List<LiveHub> hubs = [
    LiveHub('North America East', 'US', 0.22, 0.32, 5420),
    LiveHub('North America West', 'US', 0.14, 0.35, 3890),
    LiveHub('South America', 'BR', 0.29, 0.68, 2750),
    LiveHub('Europe West', 'GB', 0.47, 0.27, 6180),
    LiveHub('Europe Central', 'DE', 0.52, 0.26, 4320),
    LiveHub('Middle East', 'AE', 0.60, 0.40, 2140),
    LiveHub('South Asia (PK/IN)', 'PK', 0.67, 0.42, 4890),
    LiveHub('East Asia (JP/KR)', 'JP', 0.82, 0.33, 3210),
    LiveHub('Southeast Asia', 'ID', 0.77, 0.56, 2980),
    LiveHub('Australia', 'AU', 0.85, 0.75, 1120),
    LiveHub('North Africa', 'EG', 0.54, 0.40, 1450),
    LiveHub('South Africa', 'ZA', 0.55, 0.73, 980),
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

    // 5. Draw live hubs with pulsing radar ripples and live user markers
    _drawHubs(canvas, size);

    // 6. Subtle corner vignette gradient for high foreground readability
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: [
          Colors.transparent,
          (isDark ? Colors.black : Colors.white).withOpacity(0.45),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), vignettePaint);
  }

  void _drawContinents(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final continentPaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B).withOpacity(0.85) : const Color(0xFFCBD5E1).withOpacity(0.85)
      ..style = PaintingStyle.fill;

    // North America
    final naPath = Path()
      ..moveTo(w * 0.08, h * 0.14)
      ..lineTo(w * 0.28, h * 0.14)
      ..lineTo(w * 0.31, h * 0.22)
      ..lineTo(w * 0.25, h * 0.40)
      ..lineTo(w * 0.19, h * 0.48)
      ..lineTo(w * 0.14, h * 0.40)
      ..lineTo(w * 0.09, h * 0.28)
      ..close();
    canvas.drawPath(naPath, continentPaint);

    // Greenland
    final glPath = Path()
      ..moveTo(w * 0.32, h * 0.08)
      ..lineTo(w * 0.38, h * 0.09)
      ..lineTo(w * 0.36, h * 0.16)
      ..lineTo(w * 0.31, h * 0.14)
      ..close();
    canvas.drawPath(glPath, continentPaint);

    // South America
    final saPath = Path()
      ..moveTo(w * 0.23, h * 0.52)
      ..lineTo(w * 0.31, h * 0.55)
      ..lineTo(w * 0.34, h * 0.65)
      ..lineTo(w * 0.30, h * 0.84)
      ..lineTo(w * 0.26, h * 0.82)
      ..lineTo(w * 0.24, h * 0.65)
      ..close();
    canvas.drawPath(saPath, continentPaint);

    // Europe
    final euPath = Path()
      ..moveTo(w * 0.45, h * 0.20)
      ..lineTo(w * 0.54, h * 0.19)
      ..lineTo(w * 0.55, h * 0.32)
      ..lineTo(w * 0.44, h * 0.34)
      ..lineTo(w * 0.43, h * 0.26)
      ..close();
    canvas.drawPath(euPath, continentPaint);

    // Africa
    final afPath = Path()
      ..moveTo(w * 0.43, h * 0.38)
      ..lineTo(w * 0.57, h * 0.38)
      ..lineTo(w * 0.59, h * 0.53)
      ..lineTo(w * 0.55, h * 0.77)
      ..lineTo(w * 0.50, h * 0.76)
      ..lineTo(w * 0.44, h * 0.55)
      ..close();
    canvas.drawPath(afPath, continentPaint);

    // Asia
    final asPath = Path()
      ..moveTo(w * 0.55, h * 0.16)
      ..lineTo(w * 0.86, h * 0.16)
      ..lineTo(w * 0.87, h * 0.38)
      ..lineTo(w * 0.77, h * 0.52)
      ..lineTo(w * 0.66, h * 0.48)
      ..lineTo(w * 0.58, h * 0.35)
      ..close();
    canvas.drawPath(asPath, continentPaint);

    // Australia & Oceania
    final auPath = Path()
      ..moveTo(w * 0.80, h * 0.68)
      ..lineTo(w * 0.89, h * 0.69)
      ..lineTo(w * 0.88, h * 0.82)
      ..lineTo(w * 0.81, h * 0.80)
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

      // Arc bending height proportional to distance
      final dist = (p2 - p1).distance;
      final bend = math.min(dist * 0.22, 35.0);
      final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2 - bend);

      final arcPath = Path()
        ..moveTo(p1.dx, p1.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, p2.dx, p2.dy);

      // Glowing curved arc line
      final arcPaint = Paint()
        ..color = (isDark ? AppColors.brandIndigo : const Color(0xFF6366F1)).withOpacity(0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
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

    for (final hub in hubs) {
      final center = Offset(hub.x * w, hub.y * h);

      // Expanding radar ripple rings
      final rippleRadius = 5.0 + 16.0 * animationProgress;
      final rippleAlpha = (1.0 - animationProgress).clamp(0.0, 1.0);

      final ripplePaint = Paint()
        ..color = (isDark ? AppColors.brandIndigo : const Color(0xFF6366F1))
            .withOpacity(0.35 * rippleAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(center, rippleRadius, ripplePaint);

      // Core pulsating hub dot
      final corePaint = Paint()
        ..color = isDark ? Colors.white : AppColors.brandIndigo
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 3.2, corePaint);

      // Inner glow
      final glowPaint = Paint()
        ..color = (isDark ? AppColors.brandPink : AppColors.brandIndigo).withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(center, 5.5, glowPaint);

      // Live user badge near hub
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
            text: '• ${(hub.liveUsers / 1000).toStringAsFixed(1)}k live',
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

  @override
  bool shouldRepaint(covariant FullScreenWorldMapPainter oldDelegate) {
    return oldDelegate.animationProgress != animationProgress || oldDelegate.isDark != isDark;
  }
}

class LiveHub {
  final String name;
  final String countryCode;
  final double x;
  final double y;
  final int liveUsers;

  const LiveHub(this.name, this.countryCode, this.x, this.y, this.liveUsers);
}

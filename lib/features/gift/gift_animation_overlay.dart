import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../models/gift_transaction.dart';
import '../../services/livekit_service.dart';
import '../../services/supabase_service.dart';

/// 7 specification animation themes matching catalogue gifts
enum GiftThemeType {
  heart,
  rose,
  coffee,
  star,
  diamond,
  crown,
  superGift,
  custom,
}

/// Visual and physics profile for a specific gift type
class GiftAnimationTheme {
  final GiftThemeType type;
  final String title;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final List<Color> gradientColors;
  final List<String> particleEmojis;
  final int baseParticleCount;
  final bool hasShockwave;
  final double shockwaveRadius;
  final double heroScale;

  const GiftAnimationTheme({
    required this.type,
    required this.title,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.gradientColors,
    required this.particleEmojis,
    required this.baseParticleCount,
    required this.hasShockwave,
    this.shockwaveRadius = 180.0,
    this.heroScale = 1.0,
  });

  /// Factory resolving gift by ID and display name
  factory GiftAnimationTheme.fromGift({
    required String giftId,
    required String giftName,
  }) {
    final lowerId = giftId.toLowerCase();
    final lowerName = giftName.toLowerCase();

    if (lowerId.contains('heart') || lowerName.contains('heart')) {
      return const GiftAnimationTheme(
        type: GiftThemeType.heart,
        title: 'Heart',
        primaryColor: Color(0xFFFF2D55),
        secondaryColor: Color(0xFFFF69B4),
        accentColor: Color(0xFFFFB6C1),
        gradientColors: [Color(0xFFFF2D55), Color(0xFFFF7597), Color(0xFFFFC2D1)],
        particleEmojis: ['❤️', '💖', '💕', '✨', '💗'],
        baseParticleCount: 28,
        hasShockwave: false,
        heroScale: 1.0,
      );
    } else if (lowerId.contains('rose') || lowerName.contains('rose')) {
      return const GiftAnimationTheme(
        type: GiftThemeType.rose,
        title: 'Rose',
        primaryColor: Color(0xFFE63946),
        secondaryColor: Color(0xFFC1121F),
        accentColor: Color(0xFFFFB4A2),
        gradientColors: [Color(0xFFE63946), Color(0xFFFF4D6D), Color(0xFFFDC500)],
        particleEmojis: ['🌹', '🥀', '🌸', '✨', '🌺'],
        baseParticleCount: 32,
        hasShockwave: false,
        heroScale: 1.05,
      );
    } else if (lowerId.contains('coffee') || lowerName.contains('coffee')) {
      return const GiftAnimationTheme(
        type: GiftThemeType.coffee,
        title: 'Coffee',
        primaryColor: Color(0xFFB08968),
        secondaryColor: Color(0xFF7F4F24),
        accentColor: Color(0xFFEDE0D4),
        gradientColors: [Color(0xFFD4A373), Color(0xFFB08968), Color(0xFF582F0E)],
        particleEmojis: ['☕', '☕️', '🧋', '✨', '🥐'],
        baseParticleCount: 26,
        hasShockwave: false,
        heroScale: 1.0,
      );
    } else if (lowerId.contains('star') || lowerName.contains('star')) {
      return const GiftAnimationTheme(
        type: GiftThemeType.star,
        title: 'Star',
        primaryColor: Color(0xFFFFD700),
        secondaryColor: Color(0xFFFFA500),
        accentColor: Color(0xFFFFF3B0),
        gradientColors: [Color(0xFFFFD700), Color(0xFFFF9E00), Color(0xFFFFF8E7)],
        particleEmojis: ['⭐', '✨', '🌟', '💫', '⚡'],
        baseParticleCount: 44,
        hasShockwave: true,
        shockwaveRadius: 200.0,
        heroScale: 1.15,
      );
    } else if (lowerId.contains('diamond') || lowerName.contains('diamond')) {
      return const GiftAnimationTheme(
        type: GiftThemeType.diamond,
        title: 'Diamond',
        primaryColor: Color(0xFF00E5FF),
        secondaryColor: Color(0xFF0091EA),
        accentColor: Color(0xFFE0F7FA),
        gradientColors: [Color(0xFF00E5FF), Color(0xFF2979FF), Color(0xFFE1F5FE)],
        particleEmojis: ['💎', '✨', '🔷', '❄️', '💠'],
        baseParticleCount: 50,
        hasShockwave: true,
        shockwaveRadius: 220.0,
        heroScale: 1.2,
      );
    } else if (lowerId.contains('crown') || lowerName.contains('crown')) {
      return const GiftAnimationTheme(
        type: GiftThemeType.crown,
        title: 'Royal Crown',
        primaryColor: Color(0xFFFFD700),
        secondaryColor: Color(0xFF8A2BE2),
        accentColor: Color(0xFFFFE066),
        gradientColors: [Color(0xFFFFD700), Color(0xFF8A2BE2), Color(0xFF4A00E0)],
        particleEmojis: ['👑', '✨', '⭐', '💎', '🎉'],
        baseParticleCount: 60,
        hasShockwave: true,
        shockwaveRadius: 240.0,
        heroScale: 1.3,
      );
    } else if (lowerId.contains('super') ||
        lowerName.contains('super') ||
        lowerId.contains('rocket') ||
        lowerName.contains('rocket')) {
      return const GiftAnimationTheme(
        type: GiftThemeType.superGift,
        title: 'Super Gift',
        primaryColor: Color(0xFFFF007F),
        secondaryColor: Color(0xFF7928CA),
        accentColor: Color(0xFFFFD700),
        gradientColors: [Color(0xFFFF007F), Color(0xFF7928CA), Color(0xFFFFD700), Color(0xFF00E5FF)],
        particleEmojis: ['🚀', '💥', '✨', '🔥', '👑', '🎉', '🌟'],
        baseParticleCount: 75,
        hasShockwave: true,
        shockwaveRadius: 300.0,
        heroScale: 1.4,
      );
    }

    // Default generic fallback
    return const GiftAnimationTheme(
      type: GiftThemeType.custom,
      title: 'Gift',
      primaryColor: AppColors.brandPink,
      secondaryColor: AppColors.coinGold,
      accentColor: Colors.white,
      gradientColors: [AppColors.brandPink, AppColors.coinGold],
      particleEmojis: ['🎁', '✨', '🎉', '⭐'],
      baseParticleCount: 30,
      hasShockwave: false,
      heroScale: 1.0,
    );
  }
}

/// Particle model representing sparks and floating emojis
class GiftParticle {
  final double x;
  final double y;
  final double vx;
  final double vy;
  final double scale;
  final double rotation;
  final double rotationSpeed;
  final String emoji;
  final Color sparkColor;
  final double sparkRadius;
  final bool isEmoji;

  GiftParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.scale,
    required this.rotation,
    required this.rotationSpeed,
    required this.emoji,
    required this.sparkColor,
    required this.sparkRadius,
    required this.isEmoji,
  });
}

/// Canvas-based painter rendering spark particles and glowing shockwave rings
class GiftParticlesPainter extends CustomPainter {
  final List<GiftParticle> particles;
  final double progress;
  final GiftAnimationTheme theme;
  final int comboCount;

  GiftParticlesPainter({
    required this.particles,
    required this.progress,
    required this.theme,
    required this.comboCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (particles.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);

    // Shockwave ripple ring
    if (theme.hasShockwave || comboCount >= 3) {
      final ringProgress = Curves.easeOutCubic.transform(progress);
      final currentRadius = theme.shockwaveRadius * ringProgress * (1.0 + (comboCount - 1) * 0.15);
      final alpha = ((1.0 - ringProgress) * 0.85).clamp(0.0, 1.0);

      if (alpha > 0.01) {
        final shockPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (5.0 * (1.0 - ringProgress)).clamp(1.0, 5.0)
          ..shader = RadialGradient(
            colors: [
              theme.primaryColor.withOpacity(alpha),
              theme.secondaryColor.withOpacity(alpha * 0.5),
              Colors.transparent,
            ],
            stops: const [0.7, 0.9, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: currentRadius + 10));

        canvas.drawCircle(center, currentRadius, shockPaint);

        // Secondary inner shockwave for Super Gift or 5x+ Combo
        if (theme.type == GiftThemeType.superGift || comboCount >= 5) {
          final innerRadius = currentRadius * 0.65;
          final innerPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0
            ..color = theme.accentColor.withOpacity(alpha * 0.7);
          canvas.drawCircle(center, innerRadius, innerPaint);
        }
      }
    }

    // Spark particles
    final sparkPaint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      if (p.isEmoji) continue;

      final curX = size.width * (p.x + p.vx * progress * 0.5);
      final curY = size.height * (p.y + p.vy * progress * 0.7);
      final opacity = ((1.0 - progress) * 0.9).clamp(0.0, 1.0);

      sparkPaint.color = p.sparkColor.withOpacity(opacity);
      canvas.drawCircle(Offset(curX, curY), p.sparkRadius * p.scale, sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GiftParticlesPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.particles != particles;
  }
}

/// High-performance gift celebration animation overlay with combo tracking and FIFO queue
class GiftAnimationOverlay extends StatefulWidget {
  final Widget child;

  const GiftAnimationOverlay({super.key, required this.child});

  @override
  State<GiftAnimationOverlay> createState() => _GiftAnimationOverlayState();
}

class _GiftAnimationOverlayState extends State<GiftAnimationOverlay>
    with SingleTickerProviderStateMixin {
  StreamSubscription<GiftEvent>? _giftSub;
  GiftEvent? _activeGift;
  GiftAnimationTheme _activeTheme = GiftAnimationTheme.fromGift(giftId: '', giftName: '');

  // FIFO Animation Queue for incoming gift storm
  final List<GiftEvent> _giftQueue = [];

  // Combo Streak Multiplier
  int _comboCount = 1;
  String? _lastGiftId;
  String? _lastSenderId;
  DateTime? _lastGiftTime;

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _comboScaleAnimation;

  final List<GiftParticle> _particles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.25).chain(CurveTween(curve: Curves.elasticOut)), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0).chain(CurveTween(curve: Curves.easeInOutBack)), weight: 25),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35).chain(CurveTween(curve: Curves.easeInBack)), weight: 25),
    ]).animate(_animController);

    _comboScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.3).chain(CurveTween(curve: Curves.bounceOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 30),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 30),
    ]).animate(CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.1, 0.5, curve: Curves.linear),
    ));

    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 65),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_animController);

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (!mounted) return;
        _handleAnimationCompletion();
      }
    });

    _giftSub = LiveKitService.instance.giftEventStream.listen((event) {
      if (mounted) {
        _onGiftReceived(event);
      }
    });
  }

  @override
  void dispose() {
    _giftSub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _onGiftReceived(GiftEvent event) {
    final now = DateTime.now();

    // Check combo criteria: same gift + same sender within 3.5 seconds
    final isCombo = _lastGiftId == event.giftId &&
        _lastSenderId == event.senderId &&
        _lastGiftTime != null &&
        now.difference(_lastGiftTime!).inMilliseconds <= 3500;

    if (isCombo) {
      _comboCount++;
    } else {
      _comboCount = 1;
    }

    _lastGiftId = event.giftId;
    _lastSenderId = event.senderId;
    _lastGiftTime = now;

    // Trigger haptic feedback
    _triggerHaptics(event);

    if (_activeGift != null && _animController.isAnimating) {
      if (isCombo) {
        // Fast consecutive combo refresh: immediately reset animation to burst
        _activeGift = event;
        _activeTheme = GiftAnimationTheme.fromGift(giftId: event.giftId, giftName: event.giftName);
        _generateParticles(_activeTheme, _comboCount);
        _animController.forward(from: 0.15);
        setState(() {});
      } else {
        // Different gift or new sender during active celebration: queue via FIFO
        if (_giftQueue.length < 10) {
          _giftQueue.add(event);
        }
      }
    } else {
      _playGiftAnimation(event);
    }
  }

  void _playGiftAnimation(GiftEvent event) {
    _activeGift = event;
    _activeTheme = GiftAnimationTheme.fromGift(giftId: event.giftId, giftName: event.giftName);
    _generateParticles(_activeTheme, _comboCount);

    setState(() {});
    _animController.forward(from: 0.0);
  }

  void _handleAnimationCompletion() {
    if (_giftQueue.isNotEmpty) {
      final nextEvent = _giftQueue.removeAt(0);
      _playGiftAnimation(nextEvent);
    } else {
      setState(() {
        _activeGift = null;
        _particles.clear();
      });
    }
  }

  void _triggerHaptics(GiftEvent event) {
    try {
      if (_comboCount >= 3 || _activeTheme.type == GiftThemeType.superGift || event.coins >= 1000) {
        HapticFeedback.heavyImpact();
      } else if (_comboCount == 2 || event.coins >= 100) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    } catch (_) {
      // Gracefully silent on platforms or environments without vibration hardware
    }
  }

  void _generateParticles(GiftAnimationTheme theme, int combo) {
    _particles.clear();

    // Calculate dynamic particle count based on theme and combo streak
    final totalCount = (theme.baseParticleCount * (1.0 + (combo - 1) * 0.25))
        .toInt()
        .clamp(20, 100);

    // Half emoji floating particles, half canvas sparks
    final emojiCount = totalCount ~/ 2;
    final sparkCount = totalCount - emojiCount;

    // 1. Emoji particles
    for (int i = 0; i < emojiCount; i++) {
      final emoji = theme.particleEmojis[_random.nextInt(theme.particleEmojis.length)];
      _particles.add(
        GiftParticle(
          x: 0.15 + _random.nextDouble() * 0.7,
          y: 0.35 + _random.nextDouble() * 0.35,
          vx: (_random.nextDouble() - 0.5) * 1.8,
          vy: -0.6 - _random.nextDouble() * 1.5,
          scale: 0.7 + _random.nextDouble() * 0.6,
          rotation: _random.nextDouble() * 2 * math.pi,
          rotationSpeed: (_random.nextDouble() - 0.5) * 3.0,
          emoji: emoji,
          sparkColor: Colors.transparent,
          sparkRadius: 0.0,
          isEmoji: true,
        ),
      );
    }

    // 2. High performance sparks for canvas painter
    for (int i = 0; i < sparkCount; i++) {
      final color = theme.gradientColors[_random.nextInt(theme.gradientColors.length)];
      _particles.add(
        GiftParticle(
          x: 0.2 + _random.nextDouble() * 0.6,
          y: 0.4 + _random.nextDouble() * 0.3,
          vx: (_random.nextDouble() - 0.5) * 2.2,
          vy: (_random.nextDouble() - 0.5) * 2.2,
          scale: 0.8 + _random.nextDouble() * 0.8,
          rotation: 0,
          rotationSpeed: 0,
          emoji: '',
          sparkColor: color,
          sparkRadius: 3.0 + _random.nextDouble() * 4.0,
          isEmoji: false,
        ),
      );
    }
  }

  String _getComboLabel(int count) {
    if (count <= 1) return '';
    if (count == 2) return '🔥 2x COMBO!';
    if (count == 3) return '🔥 3x COMBO!';
    if (count == 4) return '⚡ 4x SUPER COMBO!';
    return '💥 ${count}x MEGA COMBO!';
  }

  @override
  Widget build(BuildContext context) {
    final myId = SupabaseService.instance.currentProfile?.id ?? '';
    final isFromMe = _activeGift?.senderId == myId;

    return Stack(
      children: [
        widget.child,

        if (_activeGift != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _animController,
                builder: (context, _) {
                  final progress = _animController.value;

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Ambient darkening vignette during active gift display
                      Container(
                        color: Colors.black.withOpacity(0.3 * _fadeAnimation.value),
                      ),

                      // Canvas-based performance sparks and shockwaves
                      Positioned.fill(
                        child: CustomPaint(
                          painter: GiftParticlesPainter(
                            particles: _particles,
                            progress: progress,
                            theme: _activeTheme,
                            comboCount: _comboCount,
                          ),
                        ),
                      ),

                      // Floating celebratory emojis with rotation and scale
                      ..._particles.where((p) => p.isEmoji).map((p) {
                        final curX = p.x + p.vx * progress * 0.45;
                        final curY = p.y + p.vy * progress * 0.7;
                        final particleOpacity = (1.0 - progress).clamp(0.0, 1.0);

                        return Positioned(
                          left: MediaQuery.of(context).size.width * curX,
                          top: MediaQuery.of(context).size.height * curY,
                          child: Opacity(
                            opacity: particleOpacity,
                            child: Transform.rotate(
                              angle: p.rotation + p.rotationSpeed * progress,
                              child: Transform.scale(
                                scale: p.scale,
                                child: Text(p.emoji, style: const TextStyle(fontSize: 32)),
                              ),
                            ),
                          ),
                        );
                      }),

                      // Center Hero Gift Element & Radiating Aura
                      Center(
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: ScaleTransition(
                            scale: _scaleAnimation,
                            child: Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    _activeTheme.primaryColor.withOpacity(0.45),
                                    _activeTheme.secondaryColor.withOpacity(0.2),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.35, 0.7, 1.0],
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Hero Emoji / Icon
                                  Transform.scale(
                                    scale: _activeTheme.heroScale,
                                    child: Text(
                                      _activeGift!.emoji,
                                      style: TextStyle(
                                        fontSize: 92,
                                        shadows: [
                                          Shadow(
                                            color: _activeTheme.primaryColor.withOpacity(0.8),
                                            blurRadius: 28,
                                            offset: const Offset(0, 6),
                                          ),
                                          const Shadow(
                                            color: Colors.black54,
                                            blurRadius: 18,
                                            offset: Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // Coin Value Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: _activeTheme.gradientColors,
                                      ),
                                      borderRadius: BorderRadius.circular(24),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _activeTheme.primaryColor.withOpacity(0.6),
                                          blurRadius: 18,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text('🪙', style: TextStyle(fontSize: 14)),
                                        const SizedBox(width: 5),
                                        Text(
                                          '+${_activeGift!.coins} Coins',
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Combo Badge (Displayed when comboCount >= 2)
                                  if (_comboCount >= 2) ...[
                                    const SizedBox(height: 10),
                                    ScaleTransition(
                                      scale: _comboScaleAnimation,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFFFF3D00), Color(0xFFFF9100)],
                                          ),
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFFF3D00).withOpacity(0.7),
                                              blurRadius: 14,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                          border: Border.all(color: Colors.white, width: 1.5),
                                        ),
                                        child: Text(
                                          _getComboLabel(_comboCount),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                            fontStyle: FontStyle.italic,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Top Celebratory Toast Banner
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 50,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, -0.6),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: _animController,
                              curve: const Interval(0.0, 0.25, curve: Curves.easeOutBack),
                            )),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                              decoration: BoxDecoration(
                                gradient: isFromMe
                                    ? AppColors.primaryGradient
                                    : LinearGradient(
                                        colors: [
                                          _activeTheme.primaryColor.withOpacity(0.9),
                                          _activeTheme.secondaryColor.withOpacity(0.9),
                                        ],
                                      ),
                                borderRadius: BorderRadius.circular(26),
                                border: Border.all(color: Colors.white38, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isFromMe ? AppColors.brandPink : _activeTheme.primaryColor).withOpacity(0.55),
                                    blurRadius: 22,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_activeGift!.emoji, style: const TextStyle(fontSize: 24)),
                                  const SizedBox(width: 10),
                                  Text(
                                    isFromMe
                                        ? 'You sent ${_activeGift!.giftName} to ${_activeGift!.receiverName}!'
                                        : '${_activeGift!.senderName} sent you a ${_activeGift!.giftName}!',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (_comboCount >= 2) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black38,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${_comboCount}x',
                                        style: const TextStyle(
                                          color: Color(0xFFFFD700),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

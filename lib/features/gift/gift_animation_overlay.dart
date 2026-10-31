import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/gift_transaction.dart';
import '../../services/livekit_service.dart';
import '../../services/supabase_service.dart';

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
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  final List<_Particle> _particles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.2).chain(CurveTween(curve: Curves.elasticOut)), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4).chain(CurveTween(curve: Curves.easeIn)), weight: 40),
    ]).animate(_animController);

    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
    ]).animate(_animController);

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) {
          setState(() {
            _activeGift = null;
            _particles.clear();
          });
        }
      }
    });

    _giftSub = LiveKitService.instance.giftEventStream.listen((event) {
      if (mounted) {
        _triggerAnimation(event);
      }
    });
  }

  @override
  void dispose() {
    _giftSub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _triggerAnimation(GiftEvent event) {
    _particles.clear();
    // Generate 24 floating particles
    for (int i = 0; i < 24; i++) {
      _particles.add(
        _Particle(
          x: 0.2 + _random.nextDouble() * 0.6,
          y: 0.4 + _random.nextDouble() * 0.4,
          vx: (_random.nextDouble() - 0.5) * 1.5,
          vy: -0.8 - _random.nextDouble() * 1.4,
          scale: 0.6 + _random.nextDouble() * 0.8,
          rotation: _random.nextDouble() * 2 * math.pi,
          emoji: event.emoji,
        ),
      );
    }

    setState(() {
      _activeGift = event;
    });

    _animController.forward(from: 0.0);
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
                      // Dark subtle vignette during gift celebration
                      Container(
                        color: Colors.black.withOpacity(0.25 * _fadeAnimation.value),
                      ),

                      // Floating celebratory particles
                      ..._particles.map((p) {
                        final curX = p.x + p.vx * progress * 0.4;
                        final curY = p.y + p.vy * progress * 0.7;
                        final particleOpacity = (1.0 - progress).clamp(0.0, 1.0);

                        return Positioned(
                          left: MediaQuery.of(context).size.width * curX,
                          top: MediaQuery.of(context).size.height * curY,
                          child: Opacity(
                            opacity: particleOpacity,
                            child: Transform.rotate(
                              angle: p.rotation + progress * math.pi,
                              child: Transform.scale(
                                scale: p.scale,
                                child: Text(p.emoji, style: const TextStyle(fontSize: 28)),
                              ),
                            ),
                          ),
                        );
                      }),

                      // Center Hero Gift Element
                      Center(
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: ScaleTransition(
                            scale: _scaleAnimation,
                            child: Container(
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    AppColors.coinGold.withOpacity(0.4),
                                    AppColors.brandPink.withOpacity(0.2),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.3, 0.7, 1.0],
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _activeGift!.emoji,
                                    style: const TextStyle(
                                      fontSize: 84,
                                      shadows: [
                                        Shadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 8)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                    decoration: BoxDecoration(
                                      gradient: AppColors.vipGoldGradient,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.coinGold.withOpacity(0.5),
                                          blurRadius: 16,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      '+${_activeGift!.coins} Coins',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Top Celebratory Banner
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 50,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, -0.5),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: _animController,
                              curve: const Interval(0.0, 0.25, curve: Curves.easeOutBack),
                            )),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                gradient: isFromMe
                                    ? AppColors.primaryGradient
                                    : AppColors.vipGoldGradient,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white38, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isFromMe ? AppColors.brandPink : AppColors.coinGold).withOpacity(0.5),
                                    blurRadius: 20,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_activeGift!.emoji, style: const TextStyle(fontSize: 22)),
                                  const SizedBox(width: 8),
                                  Text(
                                    isFromMe
                                        ? 'You sent ${_activeGift!.giftName} to ${_activeGift!.receiverName}!'
                                        : '${_activeGift!.senderName} sent you a ${_activeGift!.giftName}!',
                                    style: TextStyle(
                                      color: isFromMe ? Colors.white : Colors.black87,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
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

class _Particle {
  final double x;
  final double y;
  final double vx;
  final double vy;
  final double scale;
  final double rotation;
  final String emoji;

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.scale,
    required this.rotation,
    required this.emoji,
  });
}

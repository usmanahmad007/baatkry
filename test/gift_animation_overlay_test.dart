import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/features/gift/gift_animation_overlay.dart';
import 'package:monkey_omegle_app/models/gift_transaction.dart';
import 'package:monkey_omegle_app/services/livekit_service.dart';

void main() {
  group('GiftAnimationTheme Specification Tests', () {
    test('Heart gift maps to GiftThemeType.heart with crimson tones and heart emojis', () {
      final theme = GiftAnimationTheme.fromGift(giftId: 'gift_heart', giftName: 'Heart');

      expect(theme.type, equals(GiftThemeType.heart));
      expect(theme.title, equals('Heart'));
      expect(theme.primaryColor, equals(const Color(0xFFFF2D55)));
      expect(theme.particleEmojis, contains('❤️'));
      expect(theme.hasShockwave, isFalse);
      expect(theme.baseParticleCount, equals(28));
    });

    test('Rose gift maps to GiftThemeType.rose with deep velvet red and floral petals', () {
      final theme = GiftAnimationTheme.fromGift(giftId: 'gift_rose', giftName: 'Rose');

      expect(theme.type, equals(GiftThemeType.rose));
      expect(theme.title, equals('Rose'));
      expect(theme.primaryColor, equals(const Color(0xFFE63946)));
      expect(theme.particleEmojis, contains('🌹'));
      expect(theme.hasShockwave, isFalse);
      expect(theme.baseParticleCount, equals(32));
    });

    test('Coffee gift maps to GiftThemeType.coffee with warm caramel palette', () {
      final theme = GiftAnimationTheme.fromGift(giftId: 'gift_coffee', giftName: 'Coffee');

      expect(theme.type, equals(GiftThemeType.coffee));
      expect(theme.title, equals('Coffee'));
      expect(theme.primaryColor, equals(const Color(0xFFB08968)));
      expect(theme.particleEmojis, contains('☕'));
      expect(theme.hasShockwave, isFalse);
      expect(theme.baseParticleCount, equals(26));
    });

    test('Star gift maps to GiftThemeType.star with gold palette and shockwave', () {
      final theme = GiftAnimationTheme.fromGift(giftId: 'gift_star', giftName: 'Star');

      expect(theme.type, equals(GiftThemeType.star));
      expect(theme.title, equals('Star'));
      expect(theme.primaryColor, equals(const Color(0xFFFFD700)));
      expect(theme.particleEmojis, contains('⭐'));
      expect(theme.hasShockwave, isTrue);
      expect(theme.baseParticleCount, equals(44));
    });

    test('Diamond gift maps to GiftThemeType.diamond with electric cyan crystalline prism', () {
      final theme = GiftAnimationTheme.fromGift(giftId: 'gift_diamond', giftName: 'Diamond');

      expect(theme.type, equals(GiftThemeType.diamond));
      expect(theme.title, equals('Diamond'));
      expect(theme.primaryColor, equals(const Color(0xFF00E5FF)));
      expect(theme.particleEmojis, contains('💎'));
      expect(theme.hasShockwave, isTrue);
      expect(theme.baseParticleCount, equals(50));
    });

    test('Crown gift maps to GiftThemeType.crown with imperial gold & purple velvet', () {
      final theme = GiftAnimationTheme.fromGift(giftId: 'gift_crown', giftName: 'Royal Crown');

      expect(theme.type, equals(GiftThemeType.crown));
      expect(theme.title, equals('Royal Crown'));
      expect(theme.primaryColor, equals(const Color(0xFFFFD700)));
      expect(theme.secondaryColor, equals(const Color(0xFF8A2BE2)));
      expect(theme.particleEmojis, contains('👑'));
      expect(theme.hasShockwave, isTrue);
      expect(theme.baseParticleCount, equals(60));
    });

    test('Super Gift maps to GiftThemeType.superGift with supernova chromatic blast', () {
      final theme = GiftAnimationTheme.fromGift(giftId: 'gift_super', giftName: 'Super Gift');

      expect(theme.type, equals(GiftThemeType.superGift));
      expect(theme.title, equals('Super Gift'));
      expect(theme.particleEmojis, contains('🚀'));
      expect(theme.hasShockwave, isTrue);
      expect(theme.shockwaveRadius, greaterThanOrEqualTo(280.0));
      expect(theme.baseParticleCount, equals(75));
    });

    test('Unknown gift maps to default custom gift theme', () {
      final theme = GiftAnimationTheme.fromGift(giftId: 'mystery_99', giftName: 'Mystery Token');

      expect(theme.type, equals(GiftThemeType.custom));
      expect(theme.title, equals('Gift'));
      expect(theme.particleEmojis, contains('🎁'));
      expect(theme.baseParticleCount, equals(30));
    });
  });

  group('GiftParticlesPainter Tests', () {
    test('shouldRepaint returns true when progress differs', () {
      final theme = GiftAnimationTheme.fromGift(giftId: 'gift_star', giftName: 'Star');
      final p1 = GiftParticlesPainter(
        particles: [],
        progress: 0.2,
        theme: theme,
        comboCount: 1,
      );
      final p2 = GiftParticlesPainter(
        particles: [],
        progress: 0.5,
        theme: theme,
        comboCount: 1,
      );

      expect(p2.shouldRepaint(p1), isTrue);
    });

    test('shouldRepaint returns false when identical', () {
      final theme = GiftAnimationTheme.fromGift(giftId: 'gift_star', giftName: 'Star');
      final list = <GiftParticle>[];
      final p1 = GiftParticlesPainter(
        particles: list,
        progress: 0.3,
        theme: theme,
        comboCount: 1,
      );
      final p2 = GiftParticlesPainter(
        particles: list,
        progress: 0.3,
        theme: theme,
        comboCount: 1,
      );

      expect(p2.shouldRepaint(p1), isFalse);
    });
  });

  group('GiftAnimationOverlay Widget & Stream Tests', () {
    testWidgets('renders child widget normally before gifts arrive', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GiftAnimationOverlay(
              child: Center(child: Text('Active Video Call Screen')),
            ),
          ),
        ),
      );

      expect(find.text('Active Video Call Screen'), findsOneWidget);
      expect(find.text('+10 Coins'), findsNothing);
    });

    testWidgets('reacts to incoming LiveKit gift event and renders celebration UI', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GiftAnimationOverlay(
              child: Center(child: Text('Active Video Call Screen')),
            ),
          ),
        ),
      );

      // Trigger gift event via LiveKitService
      final giftEvent = GiftEvent(
        giftId: 'gift_crown',
        giftName: 'Royal Crown',
        coins: 1000,
        senderId: 'user_alex',
        senderName: 'Alex',
        receiverId: 'user_me',
        receiverName: 'Me',
        emoji: '👑',
        timestamp: DateTime.now(),
      );

      await LiveKitService.instance.sendGiftEvent(giftEvent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Active Video Call Screen'), findsOneWidget);
      expect(find.text('+1000 Coins'), findsOneWidget);
      expect(find.text('Alex sent you a Royal Crown!'), findsOneWidget);
    });
  });
}

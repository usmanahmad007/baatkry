import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/core/providers/app_providers.dart';
import 'package:monkey_omegle_app/core/theme/app_theme.dart';
import 'package:monkey_omegle_app/core/widgets/vip_avatar.dart';
import 'package:monkey_omegle_app/features/creator/creator_dashboard_screen.dart';
import 'package:monkey_omegle_app/features/profile/my_profile_drawer.dart';
import 'package:monkey_omegle_app/features/shop/widgets/vip_comparison_modal.dart';
import 'package:monkey_omegle_app/models/creator_earning_entry.dart';
import 'package:monkey_omegle_app/models/creator_wallet.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/models/wallet_ledger_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'local_user_coins': 250,
      'local_user_coins_test_user_profile': 250,
      'app_theme_mode': 'dark',
    });
  });

  group('MyProfileDrawer Widget & Functional Tests', () {
    testWidgets('Renders all profile sections according to design specs (Free Tier)', (tester) async {
      const testProfile = UserProfile(
        id: '117705886-test-uuid',
        isAnonymous: false,
        nickname: 'XLR8 Music',
        coins: 250,
        isVip: false,
        birthDate: '2001-01-19',
        gender: 'men',
        country: 'Shekhupura',
      );

      final container = ProviderContainer(
        overrides: [
          currentProfileProvider.overrideWithValue(testProfile),
          userCoinsProvider.overrideWithValue(250),
          isGuestProvider.overrideWithValue(false),
          themeModeProvider.overrideWith((ref) => ThemeModeNotifier()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(
              body: MyProfileDrawer(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Header
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // 2. Identity Card
      expect(find.text('XLR8 Music'), findsOneWidget);
      expect(find.textContaining('ID: 117705886'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);

      // 3. Baatkry Plus VIP Banner
      expect(find.text('Baatkry Plus'), findsOneWidget);
      expect(find.text('Get More Gender Filters'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);

      // 4. Single Unified Balance (VIP Calls & Gifts)
      expect(find.text('Coin Balance (Calls & Gifts)'), findsOneWidget);
      expect(find.text('250 Coins'), findsOneWidget);
      expect(find.text('Top Up'), findsOneWidget);

      // 5. Personal Info: Birthday, Gender, Location
      expect(find.text('Birthday'), findsOneWidget);
      expect(find.text('2001-01-19'), findsOneWidget);
      expect(find.text('Gender'), findsOneWidget);
      expect(find.text('Male 👨'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Shekhupura'), findsOneWidget);

      // 6. Navigation Actions: Creator Studio & Buy Premium Membership
      expect(find.text('Creator Studio'), findsOneWidget);
      expect(find.text('Earn 70% cash on virtual gifts'), findsOneWidget);
      expect(find.text('Buy Premium Membership'), findsOneWidget);

      // 7. Settings Theme Switcher
      expect(find.text('App Theme Settings'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);

      // 8. Sign Out
      expect(find.text('Sign Out'), findsOneWidget);
    });

    testWidgets('Renders VIP-specific active banner, perks button, and VIP badge for VIP member', (tester) async {
      const testVipProfile = UserProfile(
        id: 'vip-user-999',
        isAnonymous: false,
        nickname: 'VIP Star',
        coins: 1500,
        isVip: true,
        birthDate: '1998-05-20',
        gender: 'women',
        country: 'Global',
      );

      final container = ProviderContainer(
        overrides: [
          currentProfileProvider.overrideWithValue(testVipProfile),
          userCoinsProvider.overrideWithValue(1500),
          isGuestProvider.overrideWithValue(false),
          themeModeProvider.overrideWith((ref) => ThemeModeNotifier()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(
              body: MyProfileDrawer(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // VIP text elements
      expect(find.text('Baatkry Plus'), findsOneWidget);
      expect(find.text('VIP Active: Unlimited Filters'), findsOneWidget);
      expect(find.text('Perks'), findsOneWidget);
      expect(find.text('VIP Star'), findsOneWidget);
      expect(find.text('VIP Membership (Active 👑)'), findsOneWidget);
      expect(find.text('VIP'), findsWidgets);
      expect(find.text('👑'), findsWidgets);
    });

    testWidgets('Renders Guest identity with guest#9329887 and hidden personal attributes when unauthenticated', (tester) async {
      const guestProfile = UserProfile(
        id: 'guest_9329887',
        isAnonymous: true,
        nickname: 'guest#9329887',
        coins: 0,
        isVip: false,
      );

      final container = ProviderContainer(
        overrides: [
          currentProfileProvider.overrideWithValue(guestProfile),
          userCoinsProvider.overrideWithValue(0),
          isGuestProvider.overrideWithValue(true),
          themeModeProvider.overrideWith((ref) => ThemeModeNotifier()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(
              body: MyProfileDrawer(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Guest nickname format
      expect(find.text('guest#9329887'), findsOneWidget);
      expect(find.textContaining('ID: 9329887'), findsOneWidget);

      // Birthday & Gender protected for guest
      expect(find.text('Sign in to view'), findsOneWidget);
      expect(find.text('Sign in to set'), findsOneWidget);

      // Balances separation
      expect(find.text('Coin Balance (Calls & Gifts)'), findsOneWidget);
      expect(find.text('Non-withdrawable'), findsOneWidget);
      expect(find.text('0 Coins'), findsOneWidget);
      expect(find.text('Gift Earnings'), findsOneWidget);
      expect(find.text('Withdrawable 💸'), findsOneWidget);
      expect(find.text('\$0.00'), findsOneWidget);
    });

    testWidgets('Tapping Theme mode chips updates application theme', (tester) async {
      const testProfile = UserProfile(
        id: 'theme_test_user',
        isAnonymous: false,
        nickname: 'Theme Tester',
        coins: 100,
      );

      final container = ProviderContainer(
        overrides: [
          currentProfileProvider.overrideWithValue(testProfile),
          userCoinsProvider.overrideWithValue(100),
          isGuestProvider.overrideWithValue(false),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(
              body: MyProfileDrawer(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Light Theme
      await tester.ensureVisible(find.text('Light'));
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(container.read(themeModeProvider), equals(ThemeMode.light));

      // Tap Dark Theme
      await tester.ensureVisible(find.text('Dark'));
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(container.read(themeModeProvider), equals(ThemeMode.dark));

      // Tap System Theme
      await tester.ensureVisible(find.text('System'));
      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(container.read(themeModeProvider), equals(ThemeMode.system));
    });
  });

  group('CreatorDashboard Mobile Overflow Prevention Tests', () {
    testWidgets('Renders Gift Earnings tab and filter chips on 360px mobile screen without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockWallet = CreatorWallet(
        id: 'cw_123',
        creatorId: 'creator_123',
        pendingEarningsUsd: 15.0,
        availableEarningsUsd: 45.0,
        withdrawnEarningsUsd: 10.0,
        lifetimeEarningsUsd: 70.0,
      );

      final container = ProviderContainer(
        overrides: [
          creatorWalletProvider.overrideWith((ref) => Future.value(mockWallet)),
          creatorEarningsProvider.overrideWith((ref) => Future.value([
            CreatorEarningEntry(
              id: 'earn_1',
              creatorId: 'creator_123',
              giftTransactionId: 'gtx_1',
              grossAmountUsd: 10.0,
              platformCommissionUsd: 3.0,
              netEarningUsd: 7.0,
              status: 'available',
              giftName: 'Rose',
              senderName: 'Alice',
              coins: 50,
            ),
          ])),
          creatorMyWithdrawalsProvider.overrideWith((ref) => Future.value([])),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const CreatorDashboardScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify no overflow occurred
      expect(tester.takeException(), isNull);

      // Verify tabs and filter chips are present
      expect(find.text('Gift Earnings'), findsOneWidget);
      expect(find.text('Payout Requests'), findsOneWidget);
      expect(find.text('All Earnings'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Withdrawn'), findsNWidgets(2));

      // Tap Payout Requests tab
      await tester.tap(find.text('Payout Requests'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Tap back to Gift Earnings tab
      await tester.tap(find.text('Gift Earnings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Wallet Ledger Transaction Type Tests', () {
    test('LedgerTransactionType recognizes gift_received and gift_sent', () {
      expect(LedgerTransactionType.fromString('gift_received'), equals(LedgerTransactionType.giftReceived));
      expect(LedgerTransactionType.fromString('gift_sent'), equals(LedgerTransactionType.giftSent));
      expect(LedgerTransactionType.giftReceived.isCredit, isTrue);
      expect(LedgerTransactionType.giftSent.isCredit, isFalse);
      expect(LedgerTransactionType.giftReceived.displayName, equals('Gift Received'));
      expect(LedgerTransactionType.giftSent.displayName, equals('Gift Sent'));
    });
  });

  group('VIP Avatar and Comparison Modal Tests', () {
    testWidgets('VipAvatar displays golden border and VIP badge for VIP user', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VipAvatar(
                nickname: 'Alex',
                isVip: true,
                radius: 30,
              ),
            ),
          ),
        ),
      );

      expect(find.text('VIP'), findsOneWidget);
      expect(find.text('👑'), findsOneWidget);
    });

    testWidgets('VipAvatar does not display VIP badge or golden ring for normal user', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VipAvatar(
                nickname: 'Sam',
                isVip: false,
                radius: 30,
              ),
            ),
          ),
        ),
      );

      expect(find.text('VIP'), findsNothing);
      expect(find.text('👑'), findsNothing);
      expect(find.text('S'), findsOneWidget);
    });

    testWidgets('VipComparisonModal displays side-by-side comparison features', (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentProfileProvider.overrideWithValue(const UserProfile(
            id: 'test-user',
            isAnonymous: false,
            nickname: 'Tester',
            isVip: false,
          )),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: VipComparisonModal(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Free User vs VIP Member'), findsOneWidget);
      expect(find.text('Normal User'), findsOneWidget);
      expect(find.text('VIP Member'), findsOneWidget);
      expect(find.text('Gender Filtering (Women/Men)'), findsOneWidget);
      expect(find.text('Profile Picture VIP Circle'), findsOneWidget);
      expect(find.text('Matchmaking Speed'), findsOneWidget);
    });
  });
}

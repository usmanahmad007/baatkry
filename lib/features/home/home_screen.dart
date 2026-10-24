import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../../services/guest_session_service.dart';
import '../../services/livekit_service.dart';
import '../../services/permission_service.dart';
import '../../services/supabase_service.dart';
import '../auth/auth_modal.dart';
import '../matchmaking/radar_screen.dart';
import '../moderation/age_consent_modal.dart';
import '../moderation/eula_modal.dart';
import '../shop/shop_modal.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Gender filters: 'everyone', 'men', 'women', 'transgender'
  String _selectedGenderFilter = 'everyone';
  // User's own gender: 'men', 'women', 'transgender', 'unspecified'
  String _myGender = 'unspecified';

  LocalVideoTrack? _previewTrack;
  StreamSubscription<UserProfile?>? _profileSub;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _profile = SupabaseService.instance.currentProfile;
    _myGender = _profile?.gender ?? 'unspecified';

    _profileSub = SupabaseService.instance.profileStream.listen((p) {
      if (mounted) {
        setState(() {
          _profile = p;
          _myGender = p?.gender ?? 'unspecified';
        });
      }
    });

    // Check only if previously blocked as underage (no popups on website load)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final isBlocked = await AgeConsentModal.isBlockedUnderage();
      if (isBlocked && mounted) {
        AgeConsentModal.showUnderageBlockedDialog(context);
      }
    });
  }

  void _showOneTimePermissionDialog({required VoidCallback onAllowed}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: isDark ? AppColors.brandIndigo : AppColors.brandIndigo.withOpacity(0.4),
            width: 1.2,
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Camera & Mic Access',
                      style: TextStyle(
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Baatkry connects you face-to-face with people worldwide for live video chat.',
                style: TextStyle(
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? AppColors.darkSurfaceBorder : AppColors.lightSurfaceBorder,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_rounded, color: AppColors.success, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Asked once and saved. You will not be asked again.',
                        style: TextStyle(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        PermissionService.instance.markPermissionHandled(granted: true);
                        onAllowed();
                      },
                      child: const Text('Allow & Continue', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    LiveKitService.instance.stopLocalPreview();
    super.dispose();
  }

  void _onStartMatching() {
    // 1. Consent Gate: Prompt user to verify 18+ and enter Date of Birth (from birth certificate)
    AgeConsentModal.checkAndShow(context, onVerified: () async {
      // 2. Check guest trial talk time limit
      final isGuest = _profile?.isAnonymous ?? true;
      if (isGuest) {
        final remaining = await GuestSessionService.instance.getGuestSecondsRemaining();
        if (remaining <= 0) {
          if (mounted) _showGuestTrialExhaustedDialog();
          return;
        }
      }

      if (!mounted) return;

      // 3. One-time Camera & Mic Permission check right before moving to chat
      _checkPermissionAndProceed();
    });
  }

  void _checkPermissionAndProceed() {
    final hasRequested = PermissionService.instance.hasRequested;

    if (!hasRequested) {
      // Prompt permission only once when entering chat
      _showOneTimePermissionDialog(
        onAllowed: () {
          _proceedToMatchingScreen();
        },
      );
    } else {
      // Already granted, move directly to matching without asking again
      _proceedToMatchingScreen();
    }
  }

  void _proceedToMatchingScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RadarScreen(
          profile: _profile ?? const UserProfile(id: 'temp_guest'),
          genderFilter: _selectedGenderFilter,
        ),
      ),
    );
  }

  void _showGuestTrialExhaustedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: AppColors.brandIndigo, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.timer_off_rounded, color: AppColors.warning, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Guest Trial Ended (3 Mins)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have used your 3 minutes of free guest talk time (with 30s per-person limit).',
              style: TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              'Sign in with Google to get 100% UNLIMITED free random video chat and unlock VIP gender filters!',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                AuthModal.show(context);
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('G ', style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w900, fontSize: 16)),
                  Text('Sign In for Unlimited', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onSelectGenderFilter(String filter) {
    if (filter != 'everyone') {
      final isGuest = _profile?.isAnonymous ?? true;

      // 1. STRICT REQUIREMENT: If guest, Google login is required first
      if (isGuest) {
        _promptLoginForFilter(filter);
        return;
      }

      // 2. STRICT REQUIREMENT: Even if logged in with Google/Gmail,
      // user cannot chat with specific gender unless they purchase a coin package!
      final coins = _profile?.coins ?? 0;
      final isVip = _profile?.isVip ?? false;
      if (coins <= 0 && !isVip) {
        _promptPackageRequiredForGender(filter);
        return;
      }
    }

    setState(() => _selectedGenderFilter = filter);
  }

  void _promptPackageRequiredForGender(String filter) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.coinGold, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.workspace_premium_rounded, color: AppColors.coinGold, size: 28),
            SizedBox(width: 10),
            Text('Package Required', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Google account gives you Unlimited Free Random Chat!\n\nTo filter specifically by ${filter.toUpperCase()}, you must buy a coin package.',
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: const Text(
                'Rate: 1 Coin = 1 Second of Gender-Filtered Video Chat.\nStarter Pack: 500 Rs = 60 Minutes (3,600 Coins).',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Free Random', style: TextStyle(color: AppColors.textMuted)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.vipGoldGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                ShopModal.show(context);
              },
              child: const Text('View Packages (Shop)', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _promptLoginForFilter(String filter) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.coinGold, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.star_rounded, color: AppColors.coinGold, size: 28),
            SizedBox(width: 10),
            Text('VIP Gender Filter', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Free users get unlimited random matching. To filter by gender (Men, Women, or Transgender), please sign in with Google.',
              style: TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: const Text(
                'Plan: 500 Rupees = 60 Minutes (1 Coin = 1 Second of gender-filtered chat). Min deposit: 500 Rs (60 Mins).',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              AuthModal.show(context, onAuthSuccess: () {
                setState(() => _selectedGenderFilter = filter);
              });
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('G ', style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w900, fontSize: 16)),
                Text('Sign In with Google', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _updateMyGender(String gender) async {
    setState(() => _myGender = gender);
    await SupabaseService.instance.updateProfile(gender: gender);
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = _profile?.isAnonymous ?? true;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.meshGrad(context),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Navigation Bar with modern pills
              _buildTopNavBar(isGuest),

              // Scrollable Centered Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 540),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Modern Camera Preview Card
                          _buildCameraPreviewCard(),

                          const SizedBox(height: 18),

                          // Dynamic Trial / Account Status Banner
                          _buildTrialStatusBanner(isGuest),

                          const SizedBox(height: 14),

                          // Gender Filter Selector (Everyone free vs Paid VIP categories)
                          _buildGenderFilterSection(),

                          const SizedBox(height: 16),

                          // User's own gender selection
                          _buildMyGenderSection(),

                          const SizedBox(height: 16),

                          // Interests section
                          _buildInterestsSection(),

                          const SizedBox(height: 24),

                          // Big Glowing Gradient Start Video Chat Button
                          _buildStartButton(),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrialStatusBanner(bool isGuest) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isGuest) {
      final remaining = GuestSessionService.instance.cachedSecondsRemaining;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.brandIndigo.withOpacity(isDark ? 0.5 : 0.3)),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.brandIndigo.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.timer_outlined, color: AppColors.brandPink, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Guest Mode: ',
                        style: TextStyle(color: AppColors.txtPrimary(context), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: remaining <= 30 ? AppColors.danger : AppColors.brandIndigo,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${remaining}s left',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '3 mins total • 30s per stranger • Matches 60% girls',
                    style: TextStyle(color: AppColors.txtSecondary(context), fontSize: 11),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => AuthModal.show(context),
              style: TextButton.styleFrom(
                backgroundColor: isDark ? Colors.white : AppColors.brandIndigo,
                foregroundColor: isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Get Unlimited', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.success.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.all_inclusive_rounded, color: AppColors.success, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Google Account Verified',
                    style: TextStyle(color: AppColors.txtPrimary(context), fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  Text(
                    '100% Unlimited Free Random Chat • VIP filter requires coins',
                    style: TextStyle(color: AppColors.txtSecondary(context), fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Top Navigation Bar (Modern glassmorphic pills with System Theme toggle)
  // ---------------------------------------------------------------------------
  Widget _buildTopNavBar(bool isGuest) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Safety Lab, Coin Balance, and Theme Switcher (System / Black / White)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildNavPill(
                icon: Icons.shield_rounded,
                label: 'Safety Lab',
                onTap: () => EulaModal.checkAndShow(context, onAccepted: () {}),
              ),
              _buildNavPill(
                icon: Icons.monetization_on_rounded,
                label: '${_profile?.coins ?? 120}',
                accentColor: AppColors.coinGold,
                onTap: () => ShopModal.show(context),
              ),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: AppTheme.themeModeNotifier,
                builder: (context, mode, _) {
                  final icon = mode == ThemeMode.system
                      ? Icons.brightness_auto_rounded
                      : (mode == ThemeMode.dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded);
                  final label = mode == ThemeMode.system
                      ? 'System'
                      : (mode == ThemeMode.dark ? 'Black' : 'White');
                  return _buildNavPill(
                    icon: icon,
                    label: label,
                    onTap: () => AppTheme.cycleThemeMode(),
                  );
                },
              ),
            ],
          ),

          // Right: Google Sign-In or User Profile Pill
          if (isGuest)
            InkWell(
              onTap: () => AuthModal.show(context),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Text('G', style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w900, fontSize: 14)),
                    SizedBox(width: 8),
                    Text(
                      'Sign In',
                      style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                gradient: AppColors.cardGrad(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border(context)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.brandIndigo,
                    child: Text(
                      _profile?.nickname.isNotEmpty == true ? _profile!.nickname[0].toUpperCase() : 'U',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _profile?.nickname ?? 'User',
                    style: TextStyle(
                      color: AppColors.txtPrimary(context),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNavPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? accentColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pillBg = isDark ? AppColors.darkSurface.withOpacity(0.85) : Colors.white;
    final pillBorder = isDark ? AppColors.darkSurfaceBorder : AppColors.lightSurfaceBorder;
    final textColor = accentColor ?? (isDark ? Colors.white : AppColors.lightTextPrimary);
    final iconColor = accentColor ?? (isDark ? Colors.white70 : AppColors.lightTextSecondary);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: pillBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accentColor != null ? accentColor.withOpacity(0.4) : pillBorder,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Camera Preview Card (Sleek portrait with glowing border)
  // ---------------------------------------------------------------------------
  Widget _buildCameraPreviewCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 350,
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? AppColors.brandIndigo.withOpacity(0.6) : AppColors.brandIndigo.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandIndigo.withOpacity(isDark ? 0.25 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Live Video Preview
          if (_previewTrack != null)
            VideoTrackRenderer(
              _previewTrack!,
              fit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              mirrorMode: VideoViewMirrorMode.mirror,
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: isDark
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF14172B), Color(0xFF0F1222)],
                      )
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
                      ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.brandIndigo.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.videocam_rounded, size: 44, color: AppColors.brandPink),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Ready to Video Chat',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppColors.lightTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap Start Video Chat to allow camera & connect',
                      style: TextStyle(
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Top Left Status Badge
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white).withOpacity(0.85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? Colors.white12 : AppColors.lightSurfaceBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    color: _previewTrack != null ? AppColors.success : AppColors.brandCyan,
                    size: 8,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _previewTrack != null ? 'Camera Active' : 'Ready to Connect',
                    style: TextStyle(
                      color: isDark ? Colors.white : AppColors.lightTextPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Top Right Camera Flip Button (Only when preview is active)
          if (_previewTrack != null)
            Positioned(
              top: 14,
              right: 14,
              child: InkWell(
                onTap: () async {
                  await LiveKitService.instance.flipCamera();
                  setState(() {});
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Gender Filter Selector (Free vs Paid VIP Categories)
  // ---------------------------------------------------------------------------
  Widget _buildGenderFilterSection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.cardGrad(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: AppColors.isDark(context)
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'I want to talk to:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.txtPrimary(context)),
              ),
              const Flexible(
                child: Text(
                  'VIP unlocks specific gender',
                  style: TextStyle(fontSize: 11, color: AppColors.coinGold, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildFilterOption('everyone', 'Random', 'Free', isVip: false),
              const SizedBox(width: 8),
              _buildFilterOption('women', 'Women', 'VIP 👑', isVip: true),
              const SizedBox(width: 8),
              _buildFilterOption('men', 'Men', 'VIP 👑', isVip: true),
              const SizedBox(width: 8),
              _buildFilterOption('transgender', 'Trans', 'VIP 👑', isVip: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterOption(String key, String title, String badge, {required bool isVip}) {
    final isSelected = _selectedGenderFilter == key;
    return Expanded(
      child: InkWell(
        onTap: () => _onSelectGenderFilter(key),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected ? AppColors.primaryGradient : null,
            color: isSelected ? null : AppColors.surfElevated(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? Colors.white.withOpacity(0.8)
                  : (isVip ? AppColors.coinGold.withOpacity(0.35) : AppColors.border(context)),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.brandIndigo.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.txtPrimary(context),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                badge,
                style: TextStyle(
                  color: isSelected ? Colors.white : (isVip ? AppColors.coinGold : AppColors.success),
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // User's Own Gender Selection
  // ---------------------------------------------------------------------------
  Widget _buildMyGenderSection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.cardGrad(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: AppColors.isDark(context)
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'I am a:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.txtPrimary(context)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildMyGenderChip('men', 'Men'),
              const SizedBox(width: 8),
              _buildMyGenderChip('women', 'Women'),
              const SizedBox(width: 8),
              _buildMyGenderChip('transgender', 'Transgender'),
              const SizedBox(width: 8),
              _buildMyGenderChip('unspecified', "Don't show"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyGenderChip(String key, String label) {
    final isSelected = _myGender == key;
    return Expanded(
      child: InkWell(
        onTap: () => _updateMyGender(key),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: isSelected ? AppColors.cyanBlueGradient : null,
            color: isSelected ? null : AppColors.surfElevated(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? Colors.white : AppColors.border(context),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.txtSecondary(context),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Interest Tags Section
  // ---------------------------------------------------------------------------
  Widget _buildInterestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Topics & Interests:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.txtPrimary(context), fontSize: 14)),
            Flexible(
              child: Text(
                'Shared tags match faster',
                style: TextStyle(color: AppColors.txtMuted(context), fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AppConfig.availableInterests.map((interest) {
            final isSelected = _profile?.interests.contains(interest) ?? false;
            return FilterChip(
              selected: isSelected,
              label: Text('#$interest'),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppColors.txtSecondary(context),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              backgroundColor: AppColors.surfElevated(context),
              selectedColor: AppColors.brandIndigo,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isSelected ? AppColors.brandIndigo : AppColors.border(context),
                ),
              ),
              onSelected: (selected) {
                final currentList = List<String>.from(_profile?.interests ?? []);
                if (selected) {
                  currentList.add(interest);
                } else {
                  currentList.remove(interest);
                }
                SupabaseService.instance.updateProfile(interests: currentList);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Big Glowing Gradient Start Video Chat Button
  // ---------------------------------------------------------------------------
  Widget _buildStartButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandIndigo.withOpacity(0.5),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _onStartMatching,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bolt_rounded, size: 28, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'START VIDEO CHAT',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../../models/wallet.dart';
import '../../services/guest_session_service.dart';
import '../../services/livekit_service.dart';
import '../../services/network_service.dart';
import '../../services/supabase_service.dart';
import '../admin/admin_dashboard_screen.dart';
import '../auth/auth_modal.dart';
import '../../core/widgets/vip_avatar.dart';
import '../friends/friends_screen.dart';
import '../matchmaking/radar_screen.dart';
import '../moderation/age_consent_modal.dart';
import '../moderation/eula_modal.dart';
import '../profile/complete_profile_modal.dart';
import '../profile/my_profile_drawer.dart';
import '../shop/shop_modal.dart';
import '../shop/widgets/vip_comparison_modal.dart';
import '../wallet/wallet_screen.dart';
import '../wallet/widgets/free_coins_modal.dart';
import 'widgets/country_picker_modal.dart';
import 'widgets/full_screen_live_map_background.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  // Gender filters (I want to meet): 'everyone', 'men', 'women', 'transgender'
  String _selectedGenderFilter = 'everyone';
  // Pending selection before permanent lock
  String _pendingMyGender = 'men';
  // Country filter
  String _selectedCountry = 'Global (Worldwide)';
  String _selectedCountryCode = 'ALL';
  String _selectedCountryFlag = '🌍';
  bool _isTheaterMode = false;
  bool _showBottomAdBanner = true;
  bool _isProfileCompletionModalOpen = false;

  LocalVideoTrack? _previewTrack;
  UserProfile? _profile;
  StreamSubscription<UserProfile?>? _profileSub;
  StreamSubscription<UserWallet?>? _walletSub;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Real-time live online users counter for start screen display
  late AnimationController _livePulseController;

  @override
  void initState() {
    super.initState();
    _profile = SupabaseService.instance.currentProfile;
    if (_profile != null && _profile!.isGenderSet) {
      _pendingMyGender = _profile!.gender;
    }

    // Real-time balance and profile listener: updates coin pill and VIP perks everywhere live
    _profileSub = SupabaseService.instance.profileStream.listen((p) {
      if (mounted && p != null) {
        setState(() {
          _profile = p;
        });

        // Mandatory profile completion on signup or login for users lacking username or DOB:
        if (!p.isAnonymous && p.needsProfileCompletion && !_isProfileCompletionModalOpen) {
          _isProfileCompletionModalOpen = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            final prefs = await SharedPreferences.getInstance();
            final alreadyCompleted = prefs.getBool('local_profile_completed_${p.id}') ?? false;
            if (!alreadyCompleted && p.needsProfileCompletion && mounted) {
              await CompleteProfileModal.show(context, dismissible: false);
            }
            _isProfileCompletionModalOpen = false;
          });
        }
      }
    });

    _walletSub = SupabaseService.instance.walletStream.listen((w) {
      if (mounted && w != null && _profile != null) {
        setState(() {
          _profile = _profile!.copyWith(coins: w.balance);
        });
      }
    });

    // By default, if the user has not selected any specific country, always select Worldwide
    if (_selectedCountryCode == 'ALL' ||
        _selectedCountry.toLowerCase().contains('global') ||
        _selectedCountry.toLowerCase().contains('worldwide')) {
      _selectedCountry = 'Global (Worldwide)';
      _selectedCountryCode = 'ALL';
      _selectedCountryFlag = '🌍';
    }

    _livePulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Check only if previously blocked as underage (no popups on website load)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final isBlocked = await AgeConsentModal.isBlockedUnderage();
      if (isBlocked && mounted) {
        AgeConsentModal.showUnderageBlockedDialog(context);
        return;
      }

      // Mandatory profile completion for signed-in users missing username or DOB
      final profile = SupabaseService.instance.currentProfile;
      if (mounted && profile != null && !profile.isAnonymous && profile.needsProfileCompletion && !_isProfileCompletionModalOpen) {
        final prefs = await SharedPreferences.getInstance();
        final alreadyCompleted = prefs.getBool('local_profile_completed_${profile.id}') ?? false;
        if (!alreadyCompleted && profile.needsProfileCompletion && mounted) {
          _isProfileCompletionModalOpen = true;
          await CompleteProfileModal.show(context, dismissible: false);
          _isProfileCompletionModalOpen = false;
        }
      }
    });

    // Initialize persistent local camera for instant display on start screen
    LiveKitService.instance.getOrCreateLocalCamera().then((track) {
      if (mounted && track != null) {
        setState(() => _previewTrack = track);
      }
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _walletSub?.cancel();
    _livePulseController.dispose();
    super.dispose();
  }

  int get totalLiveUsersCount => ref.read(currentLiveUsersCountProvider);

  String get _currentGuestNumber {
    if (_profile != null && _profile!.nickname.startsWith('guest#')) {
      return _profile!.nickname.replaceFirst('guest#', '');
    }
    return _profile?.displayId ?? '9329887';
  }

  String _getEffectiveNickname(bool isGuest) {
    if (isGuest) {
      return 'guest#$_currentGuestNumber';
    }
    return _profile?.nickname ?? 'User';
  }

  String? _getEffectiveAvatarUrl(bool isGuest) {
    if (isGuest) return null;
    return _profile?.avatarUrl;
  }

  void _onStartMatching() async {
    // 0. Internet Connectivity Gate: Check internet connection before starting video chat
    final hasInternet = await NetworkService.instance.verifyConnectionWithPrompt(context);
    if (!hasInternet || !mounted) return;

    // 0B. Moderation Gate: Check account moderation status (Admin Ban / Restrict / Cooldown)
    final modStatus = await SupabaseService.instance.checkAccountModerationStatus();
    if (modStatus['isBanned'] == true) {
      if (mounted) {
        _showAccountBannedDialog(modStatus['banReason']?.toString() ?? 'Community guidelines violation');
      }
      return;
    }
    if (modStatus['isRestricted'] == true) {
      if (mounted) {
        _showAccountRestrictedDialog(
          modStatus['restrictionType']?.toString() ?? 'Account Restriction',
          modStatus['restrictionReason']?.toString() ?? 'Administrative moderation action',
          modStatus['restrictedUntil']?.toString(),
        );
      }
      return;
    }

    final isGuest = _profile?.isAnonymous ?? true;

    // GUEST FLOW: Do not prompt or ask anything from unauthenticated users!
    // Directly proceed to matching in Random ("Both") mode with guest trial.
    if (isGuest) {
      final remaining = await GuestSessionService.instance.getGuestSecondsRemaining();
      if (remaining <= 0) {
        if (mounted) _showGuestTrialExhaustedDialog();
        return;
      }
      _proceedToMatchingScreen();
      return;
    }

    // SIGNED IN USER FLOW:
    // 1. Mandatory Profile Completion Gate: Must have unique username and verified 18+ DOB!
    // User cannot proceed further without completing username and date of birth.
    if (_profile != null && !_profile!.isAnonymous && _profile!.needsProfileCompletion) {
      final prefs = await SharedPreferences.getInstance();
      final alreadyCompleted = prefs.getBool('local_profile_completed_${_profile!.id}') ?? false;
      if (!alreadyCompleted && mounted) {
        CompleteProfileModal.show(context, dismissible: false);
        return;
      }
    }

    // 2. One-time Age & DOB Gate: If DOB not verified yet, prompt for Date of Birth!
    final hasVerifiedAge = await AgeConsentModal.isAgeVerified();
    if (!hasVerifiedAge || _profile?.birthDate == null) {
      if (!mounted) return;
      AgeConsentModal.checkAndShow(context, onVerified: () async {
        if (!mounted) return;
        // After verifying DOB, verify gender
        if (_profile == null || !_profile!.isGenderSet) {
          _showFirstTimeGenderDialog(onConfirmed: () {
            if (mounted) _proceedToMatchingScreen();
          });
          return;
        }
        _proceedToMatchingScreen();
      });
      return;
    }

    // 2. One-time Gender Lock Gate: If gender not chosen yet, prompt to lock gender!
    if (_profile == null || !_profile!.isGenderSet) {
      _showFirstTimeGenderDialog(onConfirmed: () {
        if (mounted) _proceedToMatchingScreen();
      });
      return;
    }

    // Both verified and saved! Move directly into matching
    _proceedToMatchingScreen();
  }

  void _proceedToMatchingScreen() {
    final coins = _profile?.coins ?? 0;
    final isVip = _profile?.isVip ?? false;
    final effectiveFilter = (coins <= 0 && !isVip) ? 'everyone' : _selectedGenderFilter;
    if (effectiveFilter != _selectedGenderFilter && mounted) {
      setState(() => _selectedGenderFilter = 'everyone');
    }

    final effectiveCountry = (_selectedCountryCode == 'ALL' ||
            _selectedCountry.toLowerCase().contains('global') ||
            _selectedCountry.toLowerCase().contains('worldwide'))
        ? 'Global (Worldwide)'
        : _selectedCountry;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RadarScreen(
          profile: _profile ?? const UserProfile(id: 'temp_guest'),
          genderFilter: effectiveFilter,
          countryFilter: effectiveCountry,
        ),
      ),
    );
  }

  void _showAccountBannedDialog(String reason) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B2F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.block_rounded, color: AppColors.danger, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Account Suspended',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'An administrator has placed an active suspension on your account.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.danger.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'REASON PROVIDED BY ADMIN:',
                    style: TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reason,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Action taken: Account Banned / Suspended from matchmaking & video chat.',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Understood', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAccountRestrictedDialog(String type, String reason, String? until) {
    DateTime? untilDate;
    if (until != null) {
      untilDate = DateTime.tryParse(until);
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B2F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.orange.shade700, width: 1.5),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade400, size: 28),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Account Restricted',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'An administrator has placed a moderation restriction on your account.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MODERATION ACTION: ${type.toUpperCase()}',
                    style: TextStyle(color: Colors.orange.shade300, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 4),
                  const Text('Reason:', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  Text(
                    reason,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  if (untilDate != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Restricted until: ${untilDate.toLocal().toString().split('.').first}',
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Matchmaking and messaging features are temporarily limited.',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Understood', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
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

      // 2. STRICT REQUIREMENT: Even if logged in, VIP gender requires coins
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
    final hasUsedBonus = SupabaseService.instance.hasUsedJoiningBonus;
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
              hasUsedBonus
                  ? 'You have already used your starter joining bonus.\n\nYou need to add topup to filter specifically by ${filter.toUpperCase()}.'
                  : 'Your Google account gives you Unlimited Free Random Chat!\n\nTo filter specifically by ${filter.toUpperCase()}, you must buy a coin package.',
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
              child: const Text('Add Topup (Shop)', style: TextStyle(fontWeight: FontWeight.bold)),
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
              'Free users get unlimited random matching. Before signup or login, user cannot use coins or VIP filters. Please sign in with Google.',
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
                'Sign in with Google to receive your 120 Starter Coins and unlock gender filters!',
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

  void _onTapCountryFilter() {
    final isGuest = _profile?.isAnonymous ?? true;
    if (isGuest) {
      _showLoginRequiredForCountry();
    } else {
      _showCountryPickerModal();
    }
  }

  void _showLoginRequiredForCountry() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfElevated(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.brandIndigo.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded, color: AppColors.brandIndigo, size: 24),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Sign In Required',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Without login, user cannot change the country from Global to any country.\n\nSign in with Google to unlock 200+ countries, country filters, and your starter coins!',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.txtPrimary(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandIndigo.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.brandIndigo.withOpacity(0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.public_rounded, color: AppColors.brandIndigo, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Global (Worldwide) random matching is 100% free and unlimited for all users!',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: AppColors.txtSecondary(context))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              AuthModal.show(context);
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

  Future<void> _lockMyGender(String gender) async {
    if (_profile != null && _profile!.isGenderSet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.brandIndigo,
          content: Text('Your gender is already permanently set and locked.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final success = await SupabaseService.instance.setPermanentGender(gender);
    if (success && mounted) {
      setState(() {
        _pendingMyGender = gender;
        _profile = SupabaseService.instance.currentProfile;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Row(
            children: [
              const Icon(Icons.lock_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gender permanently locked as ${_profile?.genderDisplayName ?? gender}!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showFirstTimeGenderDialog({VoidCallback? onConfirmed}) {
    String tempSelected = _pendingMyGender;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: AppColors.brandIndigo, width: 1.5),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_person_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Your Gender',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text(
                        'One-time setup • Cannot be changed 🔒',
                        style: TextStyle(fontSize: 12, color: AppColors.brandPink, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Please select your real gender. Once confirmed, your gender will be permanently saved to your profile and cannot be modified.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : AppColors.lightTextSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildModalGenderOption(
                      label: 'Male 👨',
                      key: 'men',
                      isSelected: tempSelected == 'men',
                      onTap: () => setModalState(() => tempSelected = 'men'),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildModalGenderOption(
                      label: 'Female 👩',
                      key: 'women',
                      isSelected: tempSelected == 'women',
                      onTap: () => setModalState(() => tempSelected = 'women'),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildModalGenderOption(
                      label: 'Other ⚧',
                      key: 'transgender',
                      isSelected: tempSelected == 'transgender',
                      onTap: () => setModalState(() => tempSelected = 'transgender'),
                      isDark: isDark,
                    ),
                  ],
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
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _lockMyGender(tempSelected);
                    onConfirmed?.call();
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text('Confirm & Lock', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildModalGenderOption({
    required String label,
    required String key,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: isSelected ? AppColors.primaryGradient : null,
            color: isSelected ? null : (isDark ? AppColors.darkSurface : Colors.black12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.brandPink : Colors.white24,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : (isDark ? Colors.white : Colors.black87),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: AppColors.border(context)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout_rounded, color: AppColors.danger, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              'Sign Out',
              style: TextStyle(color: AppColors.txtPrimary(context), fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to log out of your account? You will return to anonymous guest mode.',
          style: TextStyle(color: AppColors.txtSecondary(context), fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: AppColors.txtSecondary(context))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await SupabaseService.instance.signOut();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: AppColors.brandIndigo,
                    content: Text('Logged out successfully. Reverted to Guest Mode.'),
                  ),
                );
              }
            },
            child: const Text('Log Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCountryPickerModal() {
    CountryPickerModal.show(
      context: context,
      currentCountryCode: _selectedCountryCode,
      onCountrySelected: (country, coinsDeducted) {
        setState(() {
          _selectedCountry = country.name;
          _selectedCountryCode = country.code;
          _selectedCountryFlag = country.flag;
        });
        SupabaseService.instance.updateProfile(
          country: country.name,
          countryCode: country.code,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _profile = ref.watch(currentProfileProvider);
    final isGuest = _profile?.isAnonymous ?? true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: const MyProfileDrawer(),
      backgroundColor: isMobile
          ? (isDark ? const Color(0xFF070B14) : const Color(0xFFF1F5F9))
          : const Color(0xFF6C47FF),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Full-screen World Map on Backside showing live users around the world
          const Positioned.fill(
            child: FullScreenLiveUsersMapBackground(),
          ),

          // 2. Translucent Ambient Overlay ensuring high foreground readability
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          Colors.black.withOpacity(0.50),
                          Colors.black.withOpacity(0.35),
                          Colors.black.withOpacity(0.65),
                        ]
                      : [
                          Colors.white.withOpacity(0.70),
                          Colors.white.withOpacity(0.50),
                          Colors.white.withOpacity(0.78),
                        ],
                ),
              ),
            ),
          ),

          // 3. Responsive Native Mobile Layout vs Desktop Dashboard
          SafeArea(
            child: isMobile
                ? _buildMobileNativeLayout(isGuest, isDark)
                : _buildWebDesktopLayout(isGuest, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildWebDesktopLayout(bool isGuest, bool isDark) {
    return Column(
      children: [
        // Top Modern Glassmorphic Navigation Bar
        _buildTopNavBar(isGuest),

        if (!isGuest && (_profile?.needsProfileCompletion ?? false))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
            child: _buildProfileCompletionBanner(isDark),
          ),

        // Split Desktop Screen: Camera on Left 50%, Controls & Gender on Right 50%
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // LEFT 50%: Immersive Camera Hero Card (100% width if theater mode)
                Expanded(
                  flex: _isTheaterMode ? 10 : 5,
                  child: _buildWebCameraHeroCard(isGuest, isDark),
                ),
                if (!_isTheaterMode) ...[
                  const SizedBox(width: 24),
                  // RIGHT 50%: Modern Controls Hub
                  Expanded(
                    flex: 5,
                    child: _buildWebControlsHub(isGuest, isDark),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Bottom Ad Banner (Matches Reference UI)
        _buildWebBottomAdBanner(),
      ],
    );
  }

  Widget _buildWebBottomAdBanner() {
    if (!_showBottomAdBanner) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(28, 0, 28, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Ad', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFD700), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => VipComparisonModal.show(context),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enjoy with Baatkry Plus',
                    style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    'Select your preference to meet people you like',
                    style: TextStyle(color: Colors.black54, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const Icon(Icons.bolt_rounded, color: AppColors.brandPink, size: 20),
          const SizedBox(width: 10),
          InkWell(
            onTap: () => setState(() => _showBottomAdBanner = false),
            child: const Icon(Icons.close_rounded, color: Colors.black45, size: 18),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile-Native Layout (Engineered specifically for smartphone screens)
  // ---------------------------------------------------------------------------
  Widget _buildMobileNativeLayout(bool isGuest, bool isDark) {
    final coins = _profile?.coins ?? 0;

    return Column(
      children: [
        // 1. Mobile Native App Bar
        _buildMobileTopBar(isGuest, isDark, coins),

        // 2. Scrollable Mobile Content with Stacked Fixed Bottom Dock
        Expanded(
          child: Stack(
            children: [
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isGuest) ...[
                      _buildTrialStatusBanner(true),
                      const SizedBox(height: 10),
                    ],

                    if (!isGuest && (_profile?.needsProfileCompletion ?? false)) ...[
                      _buildProfileCompletionBanner(isDark),
                      const SizedBox(height: 10),
                    ],

                    // Advanced Mobile Hero Camera Preview Card
                    _buildMobileHeroCameraCard(isGuest, isDark),

                    const SizedBox(height: 14),

                    // First-Time Gender Lock Card / Permanent Locked Gender Badge
                    _buildMobileGenderLockCard(isDark),

                    const SizedBox(height: 14),

                    // Mobile Horizontal Target Gender Selection Rail (I want to meet)
                    _buildMobileGenderRail(isDark),

                    const SizedBox(height: 12),

                    // Mobile Horizontal Country Selection Rail
                    _buildMobileCountryRail(isGuest, isDark),

                    const SizedBox(height: 12),

                    // Mobile Interests Hashtags Rail
                    _buildMobileInterestsRail(isDark),

                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // 3. Fixed Bottom Mobile Action Dock (Large, thumb-friendly start button)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildMobileBottomDock(isGuest, isDark),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWebCameraHeroCard(bool isGuest, bool isDark) {
    final nickname = _getEffectiveNickname(isGuest);
    final avatarUrl = _getEffectiveAvatarUrl(isGuest);
    final isVerified = _profile?.isAgeVerified ?? false;
    final isGenderSet = _profile?.isGenderSet ?? false;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.brandIndigo.withOpacity(0.55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandIndigo.withOpacity(0.25),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Live Camera Feed
          if (_previewTrack != null && !_previewTrack!.isDisposed)
            VideoTrackRenderer(
              _previewTrack!,
              key: ValueKey('web_preview_${_previewTrack!.sid ?? _previewTrack!.mediaStreamTrack.id}'),
              fit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              mirrorMode: VideoViewMirrorMode.mirror,
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF131629), Color(0xFF0C0E1A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 46,
                      backgroundColor: AppColors.brandIndigo.withOpacity(0.3),
                      child: const Icon(Icons.videocam_rounded, size: 48, color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      nickname,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Camera is active and ready to connect',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

          // Top Left Status Badge: Camera Live & HD
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    color: _previewTrack != null ? AppColors.success : AppColors.brandCyan,
                    size: 8,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _previewTrack != null ? 'CAMERA LIVE • 30 FPS • HD' : 'CAMERA READY',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
          ),

          // Top Right Camera Flip Button
          if (_previewTrack != null)
            Positioned(
              top: 16,
              right: 16,
              child: InkWell(
                onTap: () async {
                  await LiveKitService.instance.flipCamera();
                  if (mounted) {
                    setState(() => _previewTrack = LiveKitService.instance.localCameraTrack);
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),

          // Bottom Floating User Identity & Gender Pill
          Positioned(
            bottom: 18,
            left: 18,
            right: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.80),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  VipAvatar(
                    nickname: nickname,
                    avatarUrl: avatarUrl,
                    radius: 20,
                    isVip: _profile?.isVip ?? false,
                    showVipBadge: true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                nickname,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_profile?.isVip ?? false) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: AppColors.vipGoldGradient,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('👑', style: TextStyle(fontSize: 8)),
                                    SizedBox(width: 2),
                                    Text(
                                      'VIP',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(width: 8),
                            if (isVerified)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.success.withOpacity(0.6)),
                                ),
                                child: const Text(
                                  '18+ Verified',
                                  style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isGenderSet
                              ? 'My Gender: ${_profile?.genderDisplayName} 🔒'
                              : 'Gender: Not Set (Select on right)',
                          style: TextStyle(
                            color: isGenderSet ? AppColors.brandCyan : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: isGenderSet ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebControlsHub(bool isGuest, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF6542ED) : const Color(0xFF7551FF),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withOpacity(0.18),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7551FF).withOpacity(0.35),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),

            // Baatkry App Icon & Title Centerpiece (1-on-1 Live Video Chat)
            Center(
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C47FF), Color(0xFFFF2A85)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF2A85).withOpacity(0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.video_chat_rounded, color: Colors.white, size: 40),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Baatkry',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Make new friends face-to-face',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 3. Gender Selector Button (Matches Reference UI)
            Center(
              child: InkWell(
                onTap: _showGenderSelectionSheet,
                borderRadius: BorderRadius.circular(25),
                child: Container(
                  width: 280,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _selectedGenderFilter == 'female'
                            ? '👩 Girls Only'
                            : (_selectedGenderFilter == 'male' ? '👨 Guys Only' : '👫 Both'),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black54, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 4. Yellow Start Video Chat Button (Matches Reference UI)
            Center(
              child: SizedBox(
                width: 280,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFEB3B),
                    foregroundColor: Colors.black,
                    elevation: 4,
                    shadowColor: Colors.black.withOpacity(0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  onPressed: _onStartMatching,
                  child: const Text(
                    'START VIDEO CHAT',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 5. Expandable / Auxiliary Controls (Live Traffic, Permanent Gender, Country, Interests)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: true,
                tilePadding: EdgeInsets.zero,
                collapsedIconColor: Colors.white70,
                iconColor: Colors.white,
                title: const Row(
                  children: [
                    Icon(Icons.tune_rounded, color: Colors.white70, size: 16),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'More Filters & Preferences',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                children: [
                  const SizedBox(height: 8),
                  // Target Gender Filter ("I Want to Meet")
                  _buildGenderFilterSection(),
                  const SizedBox(height: 12),
                  // Permanent Gender lock status
                  _buildPermanentGenderSection(isDark),
                  const SizedBox(height: 12),
                  // Country filter
                  _buildCountryFilterBar(isGuest),
                  const SizedBox(height: 12),
                  // Topics & interests
                  _buildInterestsSection(),
                  const SizedBox(height: 12),
                  // Traffic count
                  _buildLiveGlobalTrafficBanner(),
                  const SizedBox(height: 12),
                  _buildFooterCaption(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGenderSelectionSheet() {
    final isVip = _profile?.isVipActive ?? false;
    final isGuest = _profile?.isAnonymous ?? true;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1B2F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Gender Preference',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose who you want to meet in video chat.',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _buildGenderOptionTile(
              label: '👫 Both (Everyone)',
              subtitle: 'Free for all users • Fastest matchmaking',
              filterKey: 'everyone',
              isVipOnly: false,
              onTap: () {
                setState(() => _selectedGenderFilter = 'everyone');
                Navigator.of(ctx).pop();
              },
            ),
            const SizedBox(height: 10),
            _buildGenderOptionTile(
              label: '👩 Girls Only',
              subtitle: isVip ? 'VIP Filter Active 👑' : 'Requires VIP Membership or Coins',
              filterKey: 'female',
              isVipOnly: true,
              onTap: () {
                if (!isVip && isGuest) {
                  Navigator.of(ctx).pop();
                  AuthModal.show(context);
                } else if (!isVip) {
                  Navigator.of(ctx).pop();
                  VipComparisonModal.show(context);
                } else {
                  setState(() => _selectedGenderFilter = 'female');
                  Navigator.of(ctx).pop();
                }
              },
            ),
            const SizedBox(height: 10),
            _buildGenderOptionTile(
              label: '👨 Guys Only',
              subtitle: isVip ? 'VIP Filter Active 👑' : 'Requires VIP Membership or Coins',
              filterKey: 'male',
              isVipOnly: true,
              onTap: () {
                if (!isVip && isGuest) {
                  Navigator.of(ctx).pop();
                  AuthModal.show(context);
                } else if (!isVip) {
                  Navigator.of(ctx).pop();
                  VipComparisonModal.show(context);
                } else {
                  setState(() => _selectedGenderFilter = 'male');
                  Navigator.of(ctx).pop();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderOptionTile({
    required String label,
    required String subtitle,
    required String filterKey,
    required bool isVipOnly,
    required VoidCallback onTap,
  }) {
    final isSelected = _selectedGenderFilter == filterKey;
    final isVip = _profile?.isVipActive ?? false;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandIndigo.withOpacity(0.2) : Colors.white10,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.brandIndigo : Colors.white12,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      if (isVipOnly && !isVip) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            gradient: AppColors.vipGoldGradient,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('VIP', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 9)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: AppColors.brandIndigo, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileTopBar(bool isGuest, bool isDark, int coins) {
    final nickname = _getEffectiveNickname(isGuest);
    final avatarUrl = _getEffectiveAvatarUrl(isGuest);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: App Logo & Live Pulsing Online Count
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.video_chat_rounded, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'BaatKry',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.circle, color: AppColors.success, size: 6),
                          const SizedBox(width: 3),
                          Text(
                            '${totalLiveUsersCount.clamp(1200, 99999)} Online',
                            style: TextStyle(
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Right: Coins Pill + Theme Toggle + User Avatar
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Coins Pill
              InkWell(
                onTap: isGuest ? _showGuestCoinInfoDialog : () => WalletScreen.show(context),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.coinGold.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.monetization_on_rounded, size: 13, color: AppColors.coinGold),
                      const SizedBox(width: 3),
                      Text(
                        isGuest ? '0' : '$coins',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.coinGold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // Friends & Chats Button
              IconButton(
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(
                  Icons.people_alt_rounded,
                  color: AppColors.brandPink,
                ),
                tooltip: 'Friends & Chats',
                onPressed: () => FriendsScreen.show(context),
              ),
              const SizedBox(width: 4),

              // Theme Toggle Icon
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
              ),
              const SizedBox(width: 4),

              // User Avatar with VIP circle distinction
              VipAvatar(
                onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                radius: 17,
                nickname: nickname,
                avatarUrl: avatarUrl,
                isVip: _profile?.isVip ?? false,
                showVipBadge: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileHeroCameraCard(bool isGuest, bool isDark) {
    final nickname = _getEffectiveNickname(isGuest);
    final avatarUrl = _getEffectiveAvatarUrl(isGuest);
    final isVerified = _profile?.isAgeVerified ?? false;

    return Container(
      height: 310,
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? AppColors.brandIndigo.withOpacity(0.55) : AppColors.brandIndigo.withOpacity(0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandIndigo.withOpacity(isDark ? 0.30 : 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Live Video Feed
          if (_previewTrack != null && !_previewTrack!.isDisposed)
            VideoTrackRenderer(
              _previewTrack!,
              key: ValueKey('mob_preview_${_previewTrack!.sid ?? _previewTrack!.mediaStreamTrack.id}'),
              fit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              mirrorMode: VideoViewMirrorMode.mirror,
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF14172B), const Color(0xFF0F1222)]
                      : [const Color(0xFFF8FAFC), const Color(0xFFF1F5F9)],
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
                      child: const Icon(Icons.videocam_rounded, size: 40, color: AppColors.brandPink),
                    ),
                    const SizedBox(height: 10),
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
                      'Camera is active and ready',
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
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
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
                    _previewTrack != null ? 'Camera Ready' : 'Ready',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

          // Top Right Camera Flip Button
          Positioned(
            top: 12,
            right: 12,
            child: InkWell(
              onTap: () async {
                await LiveKitService.instance.flipCamera();
                if (mounted) {
                  setState(() => _previewTrack = LiveKitService.instance.localCameraTrack);
                }
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 16),
              ),
            ),
          ),

          // Bottom Left: User Identity Overlay
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VipAvatar(
                    radius: 12,
                    nickname: nickname,
                    avatarUrl: avatarUrl,
                    isVip: _profile?.isVip ?? false,
                    showVipBadge: true,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    nickname,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  if (_profile?.isVip ?? false) ...[
                    const SizedBox(width: 4),
                    const Text('👑', style: TextStyle(fontSize: 10)),
                  ],
                  if (isVerified) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('18+', style: TextStyle(color: AppColors.success, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Bottom Right: Country Location Pill
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  Text(_selectedCountryFlag, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 5),
                  Text(
                    _selectedCountry.length > 15 ? '${_selectedCountry.substring(0, 13)}...' : _selectedCountry,
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileGenderRail(bool isDark) {
    final options = [
      {'key': 'everyone', 'label': 'Everyone (Free)', 'icon': '🌍', 'vip': false},
      {'key': 'women', 'label': 'Women 👑', 'icon': '👩', 'vip': true},
      {'key': 'men', 'label': 'Men 👑', 'icon': '👨', 'vip': true},
      {'key': 'transgender', 'label': 'Trans 👑', 'icon': '⚧', 'vip': true},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'I WANT TO MEET 🎯',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isDark ? Colors.white : AppColors.lightTextPrimary,
              ),
            ),
            Flexible(
              child: Text(
                _selectedGenderFilter == 'everyone' ? 'Free Unlimited' : 'VIP Coins Mode',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _selectedGenderFilter == 'everyone' ? AppColors.success : AppColors.coinGold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: options.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final opt = options[index];
              final key = opt['key'] as String;
              final isSelected = _selectedGenderFilter == key;
              final isVip = opt['vip'] as bool;

              return InkWell(
                onTap: () => _onSelectGenderFilter(key),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? (isVip ? AppColors.vipGoldGradient : AppColors.primaryGradient)
                        : null,
                    color: isSelected
                        ? null
                        : (isDark ? AppColors.darkSurface : Colors.white),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? (isVip ? AppColors.coinGold : AppColors.brandPink)
                          : (isDark ? Colors.white12 : Colors.black12),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(opt['icon'] as String, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(
                        opt['label'] as String,
                        style: TextStyle(
                          color: isSelected
                              ? (isVip ? Colors.black : Colors.white)
                              : (isDark ? Colors.white : AppColors.lightTextPrimary),
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMobileCountryRail(bool isGuest, bool isDark) {
    final topCountries = [
      {'code': 'ALL', 'name': 'Global (Worldwide)', 'flag': '🌍'},
      {'code': 'US', 'name': 'United States', 'flag': '🇺🇸'},
      {'code': 'GB', 'name': 'United Kingdom', 'flag': '🇬🇧'},
      {'code': 'IN', 'name': 'India', 'flag': '🇮🇳'},
      {'code': 'PK', 'name': 'Pakistan', 'flag': '🇵🇰'},
      {'code': 'DE', 'name': 'Germany', 'flag': '🇩🇪'},
      {'code': 'CA', 'name': 'Canada', 'flag': '🇨🇦'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Country Location 🌍',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isDark ? Colors.white : AppColors.lightTextPrimary,
              ),
            ),
            InkWell(
              onTap: _onTapCountryFilter,
              child: const Text(
                'View All 🌐',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.brandIndigo),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: topCountries.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == topCountries.length) {
                // More countries button
                return InkWell(
                  onTap: _onTapCountryFilter,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.brandIndigo.withOpacity(0.5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.add_rounded, size: 16, color: AppColors.brandIndigo),
                        SizedBox(width: 4),
                        Text('More', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.brandIndigo)),
                      ],
                    ),
                  ),
                );
              }

              final c = topCountries[index];
              final code = c['code']!;
              final isSelected = _selectedCountryCode == code;

              return InkWell(
                onTap: () {
                  if (code != 'ALL' && isGuest) {
                    _onTapCountryFilter();
                    return;
                  }
                  setState(() {
                    _selectedCountryCode = code;
                    _selectedCountry = c['name']!;
                    _selectedCountryFlag = c['flag']!;
                  });
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.brandIndigo : (isDark ? AppColors.darkSurface : Colors.white),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppColors.brandIndigo : (isDark ? Colors.white12 : Colors.black12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(c['flag']!, style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 6),
                      Text(
                        c['name']!.split(' ').first,
                        style: TextStyle(
                          color: isSelected ? Colors.white : (isDark ? Colors.white : AppColors.lightTextPrimary),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMobileGenderLockCard(bool isDark) {
    final isLocked = _profile?.isGenderSet ?? false;
    final genderDisplay = _profile?.genderDisplayName ?? 'Not Set';

    if (isLocked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A).withOpacity(0.85) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.brandIndigo.withOpacity(0.35),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'MY GENDER',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: isDark ? Colors.white54 : AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 10, color: AppColors.success),
                            SizedBox(width: 3),
                            Text(
                              'PERMANENT',
                              style: TextStyle(
                                color: AppColors.success,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    genderDisplay,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.lightTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: 'Gender is permanently set and cannot be changed',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 12, color: AppColors.brandIndigo),
                    SizedBox(width: 4),
                    Text('Locked', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.brandIndigo)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // First-Time Setup card: Lock gender permanently
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brandIndigo.withOpacity(isDark ? 0.25 : 0.12),
            AppColors.brandCyan.withOpacity(isDark ? 0.15 : 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.brandIndigo.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_clock_rounded, size: 16, color: AppColors.brandCyan),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'My Gender (One-Time Setup)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.lightTextPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Choose your gender once. This is permanent and cannot be changed.',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white70 : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildGenderSelectOption('men', 'Male 👨', isDark),
              const SizedBox(width: 6),
              _buildGenderSelectOption('women', 'Female 👩', isDark),
              const SizedBox(width: 6),
              _buildGenderSelectOption('transgender', 'Other ⚧', isDark),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _lockMyGender(_pendingMyGender),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandIndigo,
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Confirm & Lock Gender (${_pendingMyGender == 'men' ? 'Male 👨' : (_pendingMyGender == 'women' ? 'Female 👩' : 'Other ⚧')})',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderSelectOption(String key, String label, bool isDark) {
    final isSelected = _pendingMyGender == key;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _pendingMyGender = key),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.brandIndigo
                : (isDark ? AppColors.darkSurface : Colors.white),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? Colors.white38 : (isDark ? Colors.white12 : Colors.black12),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : (isDark ? Colors.white70 : AppColors.lightTextPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileInterestsRail(bool isDark) {
    final userInterests = _profile?.interests ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Topics & Interests 🏷️',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : AppColors.lightTextPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Shared tags',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: AppConfig.availableInterests.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final interest = AppConfig.availableInterests[index];
              final isSelected = userInterests.contains(interest);
              return FilterChip(
                selected: isSelected,
                label: Text('#$interest'),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : (isDark ? Colors.white70 : AppColors.lightTextPrimary),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 11,
                ),
                backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
                selectedColor: AppColors.brandIndigo,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? AppColors.brandIndigo : (isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
                onSelected: (selected) {
                  final currentList = List<String>.from(userInterests);
                  if (selected) {
                    currentList.add(interest);
                  } else {
                    currentList.remove(interest);
                  }
                  SupabaseService.instance.updateProfile(interests: currentList);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPermanentGenderSection(bool isDark) {
    final isLocked = _profile?.isGenderSet ?? false;
    final genderDisplay = _profile?.genderDisplayName ?? 'Not Set';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.darkSurface : Colors.white).withOpacity(isDark ? 0.70 : 0.90),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withOpacity(isDark ? 0.08 : 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      isLocked ? Icons.lock_rounded : Icons.lock_clock_rounded,
                      size: 16,
                      color: isLocked ? AppColors.success : AppColors.brandIndigo,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'My Gender',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? Colors.white : AppColors.lightTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isLocked
                      ? AppColors.success.withOpacity(0.18)
                      : AppColors.brandIndigo.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isLocked ? 'PERMANENT 🔒' : 'SETUP',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isLocked ? AppColors.success : AppColors.brandIndigo,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isLocked) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.brandIndigo.withOpacity(0.15),
                    AppColors.brandCyan.withOpacity(0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.brandIndigo.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      genderDisplay,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.lightTextPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Immutable profile attribute',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              'Select your gender once. This cannot be edited or changed later:',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white70 : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildGenderSelectOption('men', 'Male 👨', isDark),
                const SizedBox(width: 8),
                _buildGenderSelectOption('women', 'Female 👩', isDark),
                const SizedBox(width: 8),
                _buildGenderSelectOption('transgender', 'Other ⚧', isDark),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _lockMyGender(_pendingMyGender),
                icon: const Icon(Icons.lock_outline_rounded, size: 16, color: Colors.white),
                label: Text(
                  'Lock Gender as ${_pendingMyGender == 'men' ? 'Male 👨' : (_pendingMyGender == 'women' ? 'Female 👩' : 'Other ⚧')}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandIndigo,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileBottomDock(bool isGuest, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF0F172A) : Colors.white).withOpacity(0.95),
        border: Border(
          top: BorderSide(
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 52,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandPink.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: _onStartMatching,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.video_call_rounded, size: 24, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'START VIDEO CHAT',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isGuest
                ? '⏳ 3 minutes free trial (30s per person) • Sign in for unlimited'
                : '✨ 100% Free Unlimited Video Chat • Authentic Live Users',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Live Global Users Counter in Numbers
  // ---------------------------------------------------------------------------
  Widget _buildLiveGlobalTrafficBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: (isDark ? Colors.black : Colors.white).withOpacity(isDark ? 0.65 : 0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: (isDark ? AppColors.brandPink : AppColors.brandIndigo).withOpacity(0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated Pulsing Green Radar Dot
                  AnimatedBuilder(
                    animation: _livePulseController,
                    builder: (_, __) {
                      final pulse = (math.sin(_livePulseController.value * math.pi * 2) + 1) / 2;
                      return Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.success,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.success.withOpacity(0.4 + 0.6 * pulse),
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
                    totalLiveUsersCount == 1
                        ? '1 Live User Online Worldwide'
                        : '${totalLiveUsersCount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} Live Users Online Worldwide',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }



  // ---------------------------------------------------------------------------
  // Top Navigation Bar
  // ---------------------------------------------------------------------------
  Widget _buildTopNavBar(bool isGuest) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Safety Lab, Theater Mode, Free Coins
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildNavPill(
                  icon: Icons.verified_user_rounded,
                  label: 'Safety Lab',
                  accentColor: AppColors.success,
                  onTap: () => EulaModal.checkAndShow(context, onAccepted: () {}),
                ),
                _buildNavPill(
                  icon: _isTheaterMode ? Icons.fullscreen_exit_rounded : Icons.aspect_ratio_rounded,
                  label: 'Theater Mode',
                  accentColor: _isTheaterMode ? AppColors.brandCyan : null,
                  onTap: () => setState(() => _isTheaterMode = !_isTheaterMode),
                ),
                _buildNavPill(
                  icon: Icons.card_giftcard_rounded,
                  label: 'Free Coins',
                  accentColor: AppColors.coinGold,
                  onTap: () => FreeCoinsModal.show(context),
                ),
                if (ref.watch(isAdminProvider).value == true)
                  _buildNavPill(
                    icon: Icons.admin_panel_settings_rounded,
                    label: 'Admin',
                    accentColor: AppColors.brandPink,
                    onTap: () => AdminDashboardScreen.show(context),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Right Icons: # (Interests), 😊 (Vibe), 🕒 (History), 🤍 (Friends), Profile Avatar
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // # Interests button
              _buildTopNavIconButton(
                label: '#',
                tooltip: 'Interests & Hashtags',
                onTap: _showInterestsModal,
              ),
              const SizedBox(width: 6),
              // 😊 Vibe button
              _buildTopNavIconButton(
                icon: Icons.sentiment_satisfied_alt_rounded,
                tooltip: 'Vibe & Feelings',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Vibe check: Ready to chat! 😊'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              const SizedBox(width: 6),
              // 🕒 History button
              _buildTopNavIconButton(
                icon: Icons.schedule_rounded,
                tooltip: 'Call History',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Call history synced.'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              const SizedBox(width: 6),
              // 🤍 Friends & Direct Chat button
              _buildTopNavIconButton(
                icon: Icons.favorite_border_rounded,
                tooltip: 'Friends & Direct Chats',
                accentColor: AppColors.brandPink,
                onTap: () => FriendsScreen.show(context),
              ),
              const SizedBox(width: 10),

              // User Avatar Button -> Opens My Profile Drawer
              InkWell(
                onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      VipAvatar(
                        radius: 13,
                        nickname: _getEffectiveNickname(isGuest),
                        avatarUrl: _getEffectiveAvatarUrl(isGuest),
                        isVip: isGuest ? false : (_profile?.isVipActive ?? false),
                        showVipBadge: !isGuest && (_profile?.isVipActive ?? false),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _getEffectiveNickname(isGuest),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      if (!isGuest && (_profile?.isVipActive ?? false)) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            gradient: AppColors.vipGoldGradient,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            '👑 VIP',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (!isGuest) ...[
                const SizedBox(width: 8),
                _buildTopNavIconButton(
                  icon: Icons.logout_rounded,
                  tooltip: 'Log Out',
                  accentColor: AppColors.danger,
                  onTap: _confirmLogout,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopNavIconButton({
    IconData? icon,
    String? label,
    required String tooltip,
    Color? accentColor,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black26,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white12),
          ),
          alignment: Alignment.center,
          child: label != null
              ? Text(
                  label,
                  style: TextStyle(
                    color: accentColor ?? Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                )
              : Icon(
                  icon,
                  color: accentColor ?? Colors.white,
                  size: 18,
                ),
        ),
      ),
    );
  }

  void _showInterestsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1B2F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Hashtags & Interests #',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 6),
            const Text(
              'Select topics you love to meet people with shared passions!',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _buildInterestsSection(),
          ],
        ),
      ),
    );
  }

  void _showGuestCoinInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfElevated(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 26),
            SizedBox(width: 10),
            Text('Coin Balance (Guest)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Before signup or login, users cannot use coins. All random chat on Global (Worldwide) is 100% free!',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              'Sign in with Google to receive your 120 Starter Coins, unlock country selection (10 Coins), and gender filters!',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              AuthModal.show(context);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('G ', style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w900)),
                Text('Sign In with Google', style: TextStyle(fontWeight: FontWeight.bold)),
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



  Widget _buildProfileCompletionBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brandPink.withOpacity(0.18),
            AppColors.brandIndigo.withOpacity(0.18),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandPink.withOpacity(0.4), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.brandPink.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.badge_rounded, color: AppColors.brandPink, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set Your @Username & Date of Birth',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Choose a unique username and verify 18+ to unlock chats, calls & gifts.',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => CompleteProfileModal.show(context, dismissible: false),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Trial / Account Status Banner
  // ---------------------------------------------------------------------------
  Widget _buildTrialStatusBanner(bool isGuest) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isGuest) {
      final remaining = GuestSessionService.instance.cachedSecondsRemaining;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surf(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.brandIndigo.withOpacity(isDark ? 0.45 : 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.brandIndigo.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.timer_outlined, color: AppColors.brandPink, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 5,
                    runSpacing: 2,
                    children: [
                      Text(
                        'Guest Mode: ',
                        style: TextStyle(color: AppColors.txtPrimary(context), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
                    '30s per stranger • Matches 60% girls',
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.success.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.all_inclusive_rounded, color: AppColors.success, size: 20),
            const SizedBox(width: 10),
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
  // Country Filter Bar (Without login, user cannot change country from Global)
  // ---------------------------------------------------------------------------
  Widget _buildCountryFilterBar(bool isGuest) {
    final isGlobal = _selectedCountryCode == 'ALL';

    return InkWell(
      onTap: _onTapCountryFilter,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: AppColors.cardGrad(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isGlobal
                ? AppColors.border(context)
                : AppColors.coinGold.withOpacity(0.4),
            width: isGlobal ? 1 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Text(_selectedCountryFlag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _selectedCountry,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.txtPrimary(context),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isGuest) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_rounded, size: 10, color: Colors.orange),
                              SizedBox(width: 3),
                              Text(
                                'Locked',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isGuest
                        ? 'Sign in with Google to select country (10 Coins)'
                        : (isGlobal ? 'Worldwide queue • Free • Tap to filter specific country' : 'Filtered queue • Tap to switch'),
                    style: TextStyle(
                      fontSize: 11,
                      color: isGuest ? AppColors.brandPink : AppColors.txtSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isGuest ? Icons.lock_outline_rounded : Icons.keyboard_arrow_down_rounded,
              color: isGuest ? Colors.orange : AppColors.txtSecondary(context),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Gender Filter Selector (Free vs Paid VIP Categories)
  // ---------------------------------------------------------------------------
  Widget _buildGenderFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGrad(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'I want to talk to:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.txtPrimary(context)),
              ),
              const Flexible(
                child: Text(
                  'VIP unlocks gender',
                  style: TextStyle(fontSize: 11, color: AppColors.coinGold, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildFilterOption('everyone', 'Random', 'Free', isVip: false),
              const SizedBox(width: 6),
              _buildFilterOption('women', 'Women', 'VIP 👑', isVip: true),
              const SizedBox(width: 6),
              _buildFilterOption('men', 'Men', 'VIP 👑', isVip: true),
              const SizedBox(width: 6),
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
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            gradient: isSelected ? AppColors.primaryGradient : null,
            color: isSelected ? null : AppColors.surfElevated(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? Colors.white.withOpacity(0.8)
                  : (isVip ? AppColors.coinGold.withOpacity(0.35) : AppColors.border(context)),
              width: isSelected ? 1.5 : 1,
            ),
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
  // Interest Tags Section
  // ---------------------------------------------------------------------------
  Widget _buildInterestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Topics & Interests:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.txtPrimary(context), fontSize: 13)),
            Flexible(
              child: Text(
                'Shared tags match faster',
                style: TextStyle(color: AppColors.txtMuted(context), fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: AppConfig.availableInterests.map((interest) {
            final isSelected = _profile?.interests.contains(interest) ?? false;
            return FilterChip(
              selected: isSelected,
              label: Text('#$interest'),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppColors.txtSecondary(context),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 11,
              ),
              backgroundColor: AppColors.surfElevated(context),
              selectedColor: AppColors.brandIndigo,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
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

  Widget _buildFooterCaption() {
    return Center(
      child: Text(
        'baatkry.com • 100% Free & Anonymous • 18+ Only',
        style: TextStyle(
          color: AppColors.txtMuted(context),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

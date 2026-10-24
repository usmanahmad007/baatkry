import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../../services/livekit_service.dart';
import '../../services/permission_service.dart';
import '../../services/supabase_service.dart';
import '../auth/auth_modal.dart';
import '../matchmaking/radar_screen.dart';
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

    _checkAndInitPermissions();
  }

  /// Request permission only one time. Never bother the user repeatedly!
  Future<void> _checkAndInitPermissions() async {
    final hasRequested = PermissionService.instance.hasRequested;

    if (!hasRequested) {
      // Defer slightly until UI mounts
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showOneTimePermissionDialog();
      });
    } else {
      _startCameraPreview();
    }
  }

  void _showOneTimePermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: AppColors.brandIndigo, width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Camera & Mic Access',
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
              'Baatkry connects you face-to-face with people around the world for live video chatting.',
              style: TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_rounded, color: AppColors.success, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Permission is asked only once and saved. You will not be asked again.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandIndigo.withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                PermissionService.instance.markPermissionHandled(granted: true);
                _startCameraPreview();
              },
              child: const Text('Allow & Continue', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startCameraPreview() async {
    final track = await LiveKitService.instance.startLocalPreview();
    if (mounted) {
      setState(() => _previewTrack = track);
    }
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    LiveKitService.instance.stopLocalPreview();
    super.dispose();
  }

  void _onStartMatching() {
    EulaModal.checkAndShow(context, onAccepted: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RadarScreen(
            profile: _profile ?? const UserProfile(id: 'temp_guest'),
            genderFilter: _selectedGenderFilter,
          ),
        ),
      );
    });
  }

  void _onSelectGenderFilter(String filter) {
    if (filter != 'everyone') {
      final isGuest = _profile?.isAnonymous ?? true;

      // STRICT REQUIREMENT: If guest, Google login is required
      if (isGuest) {
        _promptLoginForFilter(filter);
        return;
      }

      // Check if user has sufficient coins (1 coin = 1 sec, min 60 coins needed) or VIP
      final coins = _profile?.coins ?? 0;
      final isVip = _profile?.isVip ?? false;
      if (coins < 60 && !isVip) {
        ShopModal.show(context);
        return;
      }
    }

    setState(() => _selectedGenderFilter = filter);
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
                'Rate: 20 Rupees = 1 Minute (1 Coin = 1 Second of gender-filtered chat). Min deposit: 500 Rs (25 Mins).',
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
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.meshBackgroundGradient,
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

  // ---------------------------------------------------------------------------
  // Top Navigation Bar (Modern glassmorphic pills)
  // ---------------------------------------------------------------------------
  Widget _buildTopNavBar(bool isGuest) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Safety Lab & Coin Balance Pill
          Row(
            children: [
              _buildNavPill(
                icon: Icons.shield_rounded,
                label: 'Safety Lab',
                onTap: () => EulaModal.checkAndShow(context, onAccepted: () {}),
              ),
              const SizedBox(width: 10),
              _buildNavPill(
                icon: Icons.monetization_on_rounded,
                label: '${_profile?.coins ?? 50} Coins',
                accentColor: AppColors.coinGold,
                onTap: () => ShopModal.show(context),
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
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.2),
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
                gradient: AppColors.darkCardGradient,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.brandIndigo.withOpacity(0.5)),
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
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accentColor != null ? accentColor.withOpacity(0.4) : AppColors.surfaceBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: accentColor ?? Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: accentColor ?? Colors.white,
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
  // Camera Preview Card (Sleek portrait with gradient glowing border)
  // ---------------------------------------------------------------------------
  Widget _buildCameraPreviewCard() {
    return Container(
      height: 350,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.brandIndigo.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandIndigo.withOpacity(0.25),
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
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF14172B), Color(0xFF0F1222)],
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.videocam_rounded, size: 48, color: AppColors.brandIndigo),
                    SizedBox(height: 8),
                    Text('Camera Active', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
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
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.circle, color: AppColors.success, size: 8),
                  SizedBox(width: 6),
                  Text('Camera Active', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),

          // Top Right Camera Flip Button
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
        gradient: AppColors.darkCardGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'I want to talk to:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
              Flexible(
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
            color: isSelected ? null : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? Colors.white.withOpacity(0.8)
                  : (isVip ? AppColors.coinGold.withOpacity(0.35) : AppColors.surfaceBorder),
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
                style: const TextStyle(
                  color: Colors.white,
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
        gradient: AppColors.darkCardGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'I am a:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
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
            color: isSelected ? null : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? Colors.white : AppColors.surfaceBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.textSecondary,
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
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Topics & Interests:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
            Flexible(
              child: Text(
                'Shared tags match faster',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
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
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              backgroundColor: AppColors.surfaceElevated,
              selectedColor: AppColors.brandIndigo,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isSelected ? AppColors.brandIndigo : AppColors.surfaceBorder,
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/vip_avatar.dart';
import '../../models/user_profile.dart';
import '../../services/supabase_service.dart';
import '../auth/auth_modal.dart';
import '../creator/creator_status_modal.dart';
import '../friends/friends_screen.dart';
import '../shop/widgets/vip_comparison_modal.dart';
import '../wallet/wallet_screen.dart';
import '../wallet/widgets/free_coins_modal.dart';
import 'complete_profile_modal.dart';

class MyProfileDrawer extends ConsumerStatefulWidget {
  final VoidCallback? onEditProfile;

  const MyProfileDrawer({super.key, this.onEditProfile});

  @override
  ConsumerState<MyProfileDrawer> createState() => _MyProfileDrawerState();
}

class _MyProfileDrawerState extends ConsumerState<MyProfileDrawer> {
  void _copyUserId(String id) {
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.brandIndigo,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('User ID $id copied to clipboard!'),
          ],
        ),
      ),
    );
  }

  void _showBlockedUsersSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => FutureBuilder<List<UserProfile>>(
          future: SupabaseService.instance.fetchBlockedUsersList(),
          builder: (context, snapshot) {
            final blockedList = snapshot.data ?? [];
            return Container(
              height: MediaQuery.of(context).size.height * 0.65,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.block_rounded, color: AppColors.danger, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Blocked Accounts',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            Text(
                              'Users you have blocked cannot message or call you.',
                              style: TextStyle(
                                color: isDark ? Colors.white60 : Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: snapshot.connectionState == ConnectionState.waiting
                        ? const Center(child: CircularProgressIndicator(color: AppColors.brandPink))
                        : (blockedList.isEmpty
                            ? Center(
                                child: Text(
                                  'No blocked accounts.',
                                  style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                                ),
                              )
                            : ListView.builder(
                                itemCount: blockedList.length,
                                itemBuilder: (_, idx) {
                                  final u = blockedList[idx];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                                    ),
                                    child: Row(
                                      children: [
                                        VipAvatar(
                                          radius: 20,
                                          nickname: u.nickname,
                                          avatarUrl: u.avatarUrl,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                u.nickname,
                                                style: TextStyle(
                                                  color: isDark ? Colors.white : Colors.black87,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              Text(
                                                u.displayUsername,
                                                style: TextStyle(
                                                  color: isDark ? Colors.white60 : Colors.black54,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        OutlinedButton(
                                          onPressed: () async {
                                            await SupabaseService.instance.unblockUser(u.id);
                                            setSheetState(() {});
                                          },
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppColors.brandPink,
                                            side: const BorderSide(color: AppColors.brandPink),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            minimumSize: const Size(0, 32),
                                          ),
                                          child: const Text('Unblock', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              )),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showEditProfileBottomSheet(UserProfile profile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController(text: profile.nickname);
    final usernameCtrl = TextEditingController(
      text: profile.username?.replaceAll('@', '') ?? '',
    );
    final locationCtrl = TextEditingController(
      text: profile.country == 'Global (Worldwide)' ? '' : profile.country,
    );
    String selectedAvatar = profile.avatarUrl ?? '';
    bool? isUsernameAvailable;
    String usernameStatusMsg = '';
    bool isCheckingUsername = false;
    Timer? usernameDebounce;

    final presetAvatars = [
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
      'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150',
      'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=150',
      'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=150',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(modalCtx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: AppColors.border(context), width: 1.5)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Edit Profile',
                    style: TextStyle(
                      color: AppColors.txtPrimary(context),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Update your avatar, username, nickname and display location.',
                    style: TextStyle(color: AppColors.txtSecondary(context), fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select Avatar Photo',
                    style: TextStyle(color: AppColors.txtPrimary(context), fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 60,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: presetAvatars.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, idx) {
                        final av = presetAvatars[idx];
                        final isSelected = selectedAvatar == av;
                        return GestureDetector(
                          onTap: () => setModalState(() => selectedAvatar = av),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? AppColors.brandPink : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 25,
                              backgroundImage: NetworkImage(av),
                              onBackgroundImageError: (_, __) {},
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: nameCtrl,
                    style: TextStyle(color: AppColors.txtPrimary(context)),
                    decoration: InputDecoration(
                      labelText: 'Nickname',
                      labelStyle: TextStyle(color: AppColors.txtSecondary(context)),
                      filled: true,
                      fillColor: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Unique Username Field with 7-Day Change Cooldown
                  TextField(
                    controller: usernameCtrl,
                    enabled: profile.canChangeUsername,
                    style: TextStyle(
                      color: profile.canChangeUsername
                          ? AppColors.txtPrimary(context)
                          : AppColors.txtSecondary(context),
                    ),
                    onChanged: (val) {
                      if (!profile.canChangeUsername) return;
                      usernameDebounce?.cancel();
                      final clean = val.trim().toLowerCase().replaceAll('@', '');
                      if (clean.isEmpty) {
                        setModalState(() {
                          isUsernameAvailable = null;
                          usernameStatusMsg = '';
                          isCheckingUsername = false;
                        });
                        return;
                      }

                      setModalState(() => isCheckingUsername = true);
                      usernameDebounce = Timer(const Duration(milliseconds: 300), () async {
                        final res = await SupabaseService.instance.checkUsernameAvailability(clean);
                        setModalState(() {
                          isCheckingUsername = false;
                          isUsernameAvailable = res['available'] == true;
                          usernameStatusMsg = res['message']?.toString() ??
                              (isUsernameAvailable! ? 'Username is available' : 'Username already taken');
                        });
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Username',
                      prefixText: '@ ',
                      prefixStyle: const TextStyle(
                        color: AppColors.brandPink,
                        fontWeight: FontWeight.bold,
                      ),
                      suffixIcon: !profile.canChangeUsername
                          ? const Icon(Icons.lock_rounded, color: Colors.amber, size: 20)
                          : (isCheckingUsername
                              ? const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandPink),
                                  ),
                                )
                              : (isUsernameAvailable == true
                                  ? const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20)
                                  : (isUsernameAvailable == false
                                      ? const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 20)
                                      : null))),
                      labelStyle: TextStyle(color: AppColors.txtSecondary(context)),
                      filled: true,
                      fillColor: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  if (!profile.canChangeUsername) ...[
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        '🔒 Username locked for ${profile.daysUntilUsernameChange} more day(s) (can only be changed once every 7 days).',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  ] else if (usernameStatusMsg.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        usernameStatusMsg,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isUsernameAvailable == true ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 5),
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Text(
                        'ℹ️ Note: Usernames can only be changed once every 7 days.',
                        style: TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  TextField(
                    controller: locationCtrl,
                    style: TextStyle(color: AppColors.txtPrimary(context)),
                    decoration: InputDecoration(
                      labelText: 'Location / City (e.g. Shekhupura)',
                      labelStyle: TextStyle(color: AppColors.txtSecondary(context)),
                      filled: true,
                      fillColor: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandIndigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () async {
                      final trimmedName = nameCtrl.text.trim();
                      final trimmedLoc = locationCtrl.text.trim();
                      final cleanUsername = usernameCtrl.text.trim().toLowerCase().replaceAll('@', '');
                      if (trimmedName.isEmpty) return;

                      if (cleanUsername.isNotEmpty &&
                          cleanUsername != profile.username?.toLowerCase()) {
                        if (!profile.canChangeUsername) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Username locked! You can only change your username once every 7 days (${profile.daysUntilUsernameChange} days remaining).',
                              ),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                          return;
                        }
                        if (isUsernameAvailable == false) {
                          return;
                        }
                      }

                      await SupabaseService.instance.updateProfile(
                        nickname: trimmedName,
                        username: cleanUsername.isNotEmpty ? cleanUsername : null,
                        avatarUrl: selectedAvatar.isNotEmpty ? selectedAvatar : null,
                        country: trimmedLoc.isNotEmpty ? trimmedLoc : 'Global (Worldwide)',
                      );

                      if (modalCtx.mounted) {
                        Navigator.of(modalCtx).pop();
                      }
                      if (mounted) {
                        setState(() {});
                      }
                    },
                    child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you sure you want to sign out? You will be returned to Guest Mode.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop(); // pop dialog
              Navigator.of(context).pop(); // close drawer
              await SupabaseService.instance.signOut();
            },
            child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    final coins = ref.watch(userCoinsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isGuest = ref.watch(isGuestProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final creatorWallet = ref.watch(creatorWalletStreamProvider).valueOrNull ??
        ref.watch(creatorWalletProvider).valueOrNull ??
        SupabaseService.instance.currentCreatorWallet;

    final guestNumber = (profile != null && profile.nickname.startsWith('guest#'))
        ? profile.nickname.replaceFirst('guest#', '')
        : (profile?.displayId ?? '9329887');
    final displayName = isGuest ? 'guest#$guestNumber' : (profile?.nickname ?? 'User');
    final displayId = isGuest ? guestNumber : (profile?.displayId ?? '000000000');
    final actualId = profile?.id ?? '';
    final avatarUrl = isGuest ? null : profile?.avatarUrl;
    final dob = isGuest ? 'Sign in to view' : (profile?.birthDate ?? 'Not set');
    final gender = isGuest ? 'Sign in to set' : (profile?.genderDisplayName ?? 'Not set');
    final location = isGuest ? 'Global (Worldwide)' : ((profile?.country != null && profile!.country.isNotEmpty) ? profile.country : 'Global (Worldwide)');

    final drawerBg = isDark ? const Color(0xFF1B1B2F) : Colors.white;
    final cardBg = isDark ? const Color(0xFF262640) : const Color(0xFFF1F5F9);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF64748B);

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final drawerWidth = isMobile ? (screenWidth * 0.88).clamp(300.0, 380.0) : 380.0;

    return Drawer(
      width: drawerWidth,
      backgroundColor: drawerBg,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(
          children: [
            // 1. Header with title and Close "X" button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'My Profile',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : Colors.black87, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 2. Identity Card: Avatar, Nickname, ID + Copy, Edit Button
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                      ),
                      child: Row(
                        children: [
                          // Avatar with VIP Golden Circle when user is VIP
                          VipAvatar(
                            nickname: displayName,
                            avatarUrl: avatarUrl,
                            radius: 25,
                            isVip: isGuest ? false : (profile?.isVip ?? false),
                            showVipBadge: !isGuest && (profile?.isVip ?? false),
                          ),
                          const SizedBox(width: 12),
                          // Name & ID
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        displayName,
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (!isGuest && (profile?.isVip ?? false)) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
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
                                  ],
                                ),
                                if (!isGuest) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    profile?.displayUsername ?? '@user',
                                    style: const TextStyle(
                                      color: AppColors.brandPink,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 3),
                                InkWell(
                                  onTap: () => _copyUserId(actualId.isNotEmpty ? actualId : displayId),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'ID: $displayId',
                                        style: TextStyle(
                                          color: subtitleColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.copy_rounded, color: subtitleColor, size: 12),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Edit Button
                          InkWell(
                            onTap: isGuest
                                ? () => AuthModal.show(context)
                                : () => _showEditProfileBottomSheet(profile!),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_rounded, color: subtitleColor, size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Edit',
                                    style: TextStyle(
                                      color: subtitleColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isGuest && (profile?.needsProfileCompletion ?? false)) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () => CompleteProfileModal.show(context, dismissible: false),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.brandPink.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.brandPink.withOpacity(0.35)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: AppColors.brandPink, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Set Username & Date of Birth',
                                      style: TextStyle(
                                        color: AppColors.brandPink,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Add unique @username and 18+ age verification.',
                                      style: TextStyle(fontSize: 11, color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.brandPink),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),

                    // 3. VIP Membership Banner (Baatkry Plus)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: (profile?.isVip ?? false)
                            ? const LinearGradient(
                                colors: [Color(0xFF2C2205), Color(0xFF533F08), Color(0xFF2C2205)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : const LinearGradient(
                                colors: [Color(0xFF3B2B6D), Color(0xFF6B48B8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: (profile?.isVip ?? false)
                              ? const Color(0xFFFFD700)
                              : const Color(0xFFFFD700).withOpacity(0.5),
                          width: (profile?.isVip ?? false) ? 1.5 : 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: ((profile?.isVip ?? false)
                                    ? const Color(0xFFFFD700)
                                    : const Color(0xFF6B48B8))
                                .withOpacity(0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0x33FFD700),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFD700), size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Flexible(
                                      child: Text(
                                        'Baatkry Plus',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (profile?.isVip ?? false) ...[
                                      const SizedBox(width: 4),
                                      const Text('👑', style: TextStyle(fontSize: 11)),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  (profile?.isVipActive ?? false)
                                      ? 'VIP Active: Unlimited Filters'
                                      : ((profile?.isVip ?? false)
                                          ? 'VIP Expired: Renew 1-Month (\$4.99/mo)'
                                          : 'Get More Gender Filters'),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              VipComparisonModal.show(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFEB3B),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              elevation: 2,
                            ),
                            child: Text(
                              (profile?.isVipActive ?? false)
                                  ? 'Perks'
                                  : ((profile?.isVip ?? false) ? 'Renew' : 'Join'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 7-Day Free Coins Daily Reward Banner
                    InkWell(
                      onTap: () => FreeCoinsModal.show(context),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF241D3B) : const Color(0xFFF3F0FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.card_giftcard_rounded, color: AppColors.coinGold, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '🎁 7-Day Free Coins',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    (profile?.canClaimDailyReward ?? false)
                                        ? 'Day ${profile?.nextDailyRewardDay ?? 1} (+${profile?.nextDailyRewardCoins ?? 50} coins) ready!'
                                        : 'Claimed today • Next reward tomorrow',
                                    style: TextStyle(color: subtitleColor, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: (profile?.canClaimDailyReward ?? false) ? const Color(0xFFFFD700) : Colors.white12,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                (profile?.canClaimDailyReward ?? false) ? 'Claim' : 'Active',
                                style: TextStyle(
                                  color: (profile?.canClaimDailyReward ?? false) ? Colors.black : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 4. Balances: Dual Balance Badges (M Coins & Diamond Gems)
                    Row(
                      children: [
                        // Left: Purchased Coins (Calls & Gifts)
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (isGuest) {
                                AuthModal.show(context);
                              } else {
                                WalletScreen.show(context);
                              }
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFFD700),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: const Text('M', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      isGuest ? '0' : '$coins',
                                      style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.add_circle_outline_rounded, color: AppColors.coinGold, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Right: Gift Earnings (Withdrawable)
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (isGuest) {
                                AuthModal.show(context);
                              } else {
                                CreatorStatusModal.show(context);
                              }
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.diamond_rounded, color: AppColors.brandPink, size: 22),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      isGuest ? '0' : '${((creatorWallet?.availableEarningsUsd ?? 0.0) / 0.05).round()}',
                                      style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  const Text('💸', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Detailed Balances Card (Calls & Gifts + Withdrawable Earnings)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                      ),
                      child: Column(
                        children: [
                          // Spendable / Purchased Coins
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: AppColors.coinGold.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            'Coin Balance (Calls & Gifts)',
                                            style: TextStyle(color: subtitleColor, fontSize: 11, fontWeight: FontWeight.w500),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.white10,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('Non-withdrawable', style: TextStyle(fontSize: 8, color: Colors.white60)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isGuest ? '0 Coins' : '$coins Coins',
                                      style: const TextStyle(
                                        color: AppColors.coinGold,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  WalletScreen.show(context);
                                },
                                icon: const Icon(Icons.add_rounded, size: 14),
                                label: const Text('Top Up', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.coinGold,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          // Withdrawable Gift Earnings
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: AppColors.brandPink.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.redeem_rounded, color: AppColors.brandPink, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            'Gift Earnings',
                                            style: TextStyle(color: subtitleColor, fontSize: 11, fontWeight: FontWeight.w500),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.brandPink.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('Withdrawable 💸', style: TextStyle(fontSize: 8, color: AppColors.brandPink)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isGuest
                                          ? '\$0.00'
                                          : '\$${(creatorWallet?.availableEarningsUsd ?? 0.0).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: AppColors.brandPink,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Wallet Actions: Top Up Coins & Withdraw
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.add_rounded, size: 14),
                            label: const Text('Top Up Coins', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.coinGold,
                              side: const BorderSide(color: AppColors.coinGold, width: 1.2),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                              WalletScreen.show(context);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.arrow_upward_rounded, size: 14),
                            label: const Text('Withdraw', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandPink,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                              CreatorStatusModal.show(context);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 5. User Attributes: Birthday, Gender, Location
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            icon: Icons.cake_outlined,
                            label: 'Birthday',
                            value: dob.isNotEmpty ? dob : 'Not set',
                            textColor: textColor,
                            subtitleColor: subtitleColor,
                          ),
                          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 16),
                          _buildDetailRow(
                            icon: Icons.person_outline_rounded,
                            label: 'Gender',
                            value: gender,
                            textColor: textColor,
                            subtitleColor: subtitleColor,
                          ),
                          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 16),
                          _buildDetailRow(
                            icon: Icons.location_on_outlined,
                            label: 'Location',
                            value: location,
                            textColor: textColor,
                            subtitleColor: subtitleColor,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 6. Navigation Actions: Creator Studio & Premium Membership
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                      ),
                      child: Column(
                        children: [
                          // 🌟 Creator Studio (Moved from outside to inside Profile section)
                          InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              CreatorStatusModal.show(context);
                            },
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.brandPink.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.stars_rounded, color: AppColors.brandPink, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Creator Studio',
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Earn 70% cash on virtual gifts',
                                          style: TextStyle(color: subtitleColor, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios_rounded, color: subtitleColor, size: 13),
                                ],
                              ),
                            ),
                          ),
                          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                          // 👥 Friends & Text Chats (Separate Friends Section)
                          InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              FriendsScreen.show(context, initialTabIndex: 0);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.brandIndigo.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.people_alt_rounded, color: AppColors.brandIndigo, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'My Friends & Text Chats',
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Chat & send gifts to friends you follow',
                                          style: TextStyle(color: subtitleColor, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios_rounded, color: subtitleColor, size: 13),
                                ],
                              ),
                            ),
                          ),
                          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                          // 🔍 Find Friends (Search by @username from complete database)
                          InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              FriendsScreen.show(context, initialTabIndex: 1);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.brandPink.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.person_search_rounded, color: AppColors.brandPink, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Find Friends',
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Search users by @username across the platform',
                                          style: TextStyle(color: subtitleColor, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios_rounded, color: subtitleColor, size: 13),
                                ],
                              ),
                            ),
                          ),
                          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                          // 👑 VIP Membership & Gender Filters
                          InkWell(
                            onTap: () {
                              VipComparisonModal.show(context);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.coinGold.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.workspace_premium_rounded, color: AppColors.coinGold, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (profile?.isVip ?? false) ? 'VIP Membership (Active 👑)' : 'Buy Premium Membership',
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          (profile?.isVip ?? false)
                                              ? 'Active 👑 • View all VIP perks & comparisons'
                                              : 'Compare Normal vs VIP perks & upgrade',
                                          style: TextStyle(color: subtitleColor, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios_rounded, color: subtitleColor, size: 13),
                                ],
                              ),
                            ),
                          ),
                          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                          // 🚫 Blocked Accounts
                          InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              _showBlockedUsersSheet(context);
                            },
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.danger.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.block_rounded, color: AppColors.danger, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Blocked Accounts',
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Manage blocked users and unblock',
                                          style: TextStyle(color: subtitleColor, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios_rounded, color: subtitleColor, size: 13),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 7. Settings & Theme Switcher (Dark / Light / System)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.palette_outlined, color: subtitleColor, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'App Theme Settings',
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildThemeChip(
                                  label: 'Dark',
                                  icon: Icons.dark_mode_rounded,
                                  isSelected: themeMode == ThemeMode.dark,
                                  onTap: () => ref.read(themeModeProvider.notifier).setTheme(ThemeMode.dark),
                                  isDark: isDark,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildThemeChip(
                                  label: 'Light',
                                  icon: Icons.light_mode_rounded,
                                  isSelected: themeMode == ThemeMode.light,
                                  onTap: () => ref.read(themeModeProvider.notifier).setTheme(ThemeMode.light),
                                  isDark: isDark,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildThemeChip(
                                  label: 'System',
                                  icon: Icons.brightness_auto_rounded,
                                  isSelected: themeMode == ThemeMode.system,
                                  onTap: () => ref.read(themeModeProvider.notifier).setTheme(ThemeMode.system),
                                  isDark: isDark,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 8. Bottom Action: Sign In (if Guest) or Sign Out
                    if (isGuest)
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          AuthModal.show(context);
                        },
                        icon: const Text('G ', style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w900, fontSize: 16)),
                        label: const Text('Sign In with Google', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      )
                    else
                      InkWell(
                        onTap: _confirmSignOut,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                          ),
                          alignment: Alignment.center,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.logout_rounded, color: AppColors.danger, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Sign Out',
                                style: TextStyle(
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color textColor,
    required Color subtitleColor,
  }) {
    return Row(
      children: [
        Icon(icon, color: subtitleColor, size: 18),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: subtitleColor, fontSize: 12),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildThemeChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandIndigo
              : (isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.brandIndigo : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

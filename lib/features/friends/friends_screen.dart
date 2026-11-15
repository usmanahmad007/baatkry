import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/vip_avatar.dart';
import '../../models/friend_request.dart';
import '../../models/user_profile.dart';
import '../../services/matchmaking_service.dart';
import '../../services/supabase_service.dart';
import '../call/video_call_screen.dart';
import 'friend_chat_screen.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const FriendsScreen({super.key, this.initialTabIndex = 0});

  static Future<void> show(BuildContext context, {int initialTabIndex = 0}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FriendsScreen(initialTabIndex: initialTabIndex),
      ),
    );
  }

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<UserProfile> _friends = [];
  List<UserProfile> _discoverUsers = [];
  List<FriendRequest> _incomingRequests = [];
  bool _isLoading = true;

  // Search by Username (Find Friends tab)
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  List<UserProfile> _discoveredUsers = [];
  bool _isSearching = false;

  // Filter My Friends tab
  final TextEditingController _friendFilterController = TextEditingController();
  String _friendFilterQuery = '';

  // Reciprocity & Follow State Maps
  final Set<String> _following = {};
  final Set<String> _followers = {};
  final Set<String> _mutualFriends = {};
  final Set<String> _sentRequests = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _friendFilterController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final friends = await SupabaseService.instance.fetchFriends();
      final requests = await SupabaseService.instance.fetchFriendRequests();
      final discover = await SupabaseService.instance.fetchDiscoverUsers(limit: 30);

      final myFollowing = <String>{};
      final myFollowers = <String>{};
      final mutual = <String>{};

      for (final f in friends) {
        final isF = await SupabaseService.instance.isFollowing(f.id);
        final isBy = await SupabaseService.instance.isFollowedBy(f.id);
        if (isF) myFollowing.add(f.id);
        if (isBy) myFollowers.add(f.id);
        if (isF && isBy) mutual.add(f.id);
      }

      if (mounted) {
        setState(() {
          _friends = friends;
          _incomingRequests = requests;
          _discoverUsers = discover;
          _following.clear();
          _following.addAll(myFollowing);
          _followers.clear();
          _followers.addAll(myFollowers);
          _mutualFriends.clear();
          _mutualFriends.addAll(mutual);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final clean = query.trim();
    setState(() => _searchQuery = clean);

    if (clean.isEmpty) {
      setState(() {
        _discoveredUsers = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final results = await SupabaseService.instance.searchUsersByUsername(clean);
        if (mounted) {
          setState(() {
            _discoveredUsers = results;
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  Future<void> _handleRespond(FriendRequest request, bool accept, {bool followBack = false}) async {
    try {
      await SupabaseService.instance.respondToFriendRequest(
        requestId: request.id,
        request: request,
        accept: accept,
        followBack: followBack,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: accept ? AppColors.success : AppColors.danger,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                Icon(
                  accept ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  accept
                      ? 'Connected with ${request.senderName}! 🤝'
                      : 'Friend request declined.',
                ),
              ],
            ),
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Failed: $e'),
          ),
        );
      }
    }
  }

  Future<void> _handleFollowBack(UserProfile friend) async {
    try {
      await SupabaseService.instance.followBackUser(friend.id);
      if (mounted) {
        setState(() {
          _following.add(friend.id);
          _mutualFriends.add(friend.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.handshake_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('You followed ${friend.nickname} back! You are mutual friends now.'),
              ],
            ),
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Could not follow back: $e'),
          ),
        );
      }
    }
  }

  Future<void> _sendFriendRequestTo(UserProfile target) async {
    setState(() => _sentRequests.add(target.id));
    try {
      final res = await SupabaseService.instance.sendFriendRequest(
        receiverId: target.id,
        receiverName: target.nickname,
        receiverAvatar: target.avatarUrl,
      );

      // In Instagram model, sending follow request marks as following/requested
      setState(() {
        _following.add(target.id);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(res['message']?.toString() ?? 'Follow request sent to ${target.displayUsername}!'),
              ],
            ),
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sentRequests.remove(target.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Failed to send request: $e'),
          ),
        );
      }
    }
  }

  Future<void> _confirmUnfollow(UserProfile user) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Unfollow ${user.displayUsername}?',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        content: Text(
          'Their profile and posts will no longer appear in your friends list. You can follow them again anytime from Find Friends.',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Unfollow'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await SupabaseService.instance.unfollowUser(user.id);
        if (mounted) {
          setState(() {
            _following.remove(user.id);
            _mutualFriends.remove(user.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.brandIndigo,
              behavior: SnackBarBehavior.floating,
              content: Text('Unfollowed ${user.nickname}.'),
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.danger,
              content: Text('Failed to unfollow: $e'),
            ),
          );
        }
      }
    }
  }

  Future<void> _confirmBlock(UserProfile user) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Block ${user.displayUsername}?',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        content: Text(
          'They will not be able to find your profile, call you, or send you messages on Baatkry. Any follow connection will be severed.',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await SupabaseService.instance.blockUser(user.id, 'Blocked from friends view');
        if (mounted) {
          setState(() {
            _friends.removeWhere((f) => f.id == user.id);
            _discoveredUsers.removeWhere((u) => u.id == user.id);
            _discoverUsers.removeWhere((u) => u.id == user.id);
            _following.remove(user.id);
            _followers.remove(user.id);
            _mutualFriends.remove(user.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
              content: Text('${user.nickname} has been blocked.'),
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.danger,
              content: Text('Failed to block user: $e'),
            ),
          );
        }
      }
    }
  }

  void _showBlockedUsersSheet() {
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
                                            _loadData();
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

  void _startVideoCall(UserProfile friend) {
    final myProfile = SupabaseService.instance.currentProfile ??
        const UserProfile(id: 'me', nickname: 'Me');
    final myId = myProfile.id;
    final sortedIds = [myId, friend.id]..sort();
    final roomId = 'friend_call_${sortedIds.join('_')}';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          matchResult: MatchResult(
            roomId: roomId,
            token: 'friend_call_token_${DateTime.now().millisecondsSinceEpoch}',
            peerId: friend.id,
            peerName: friend.nickname,
            peerGender: friend.gender,
            peerCountry: friend.country,
            peerCountryFlag: '🌍',
          ),
          myProfile: myProfile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final cardBg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white60 : Colors.black54;

    // Filter "My Friends": ONLY display users who are my friends like I followed them or mutual!
    final myFriendsOnly = _friends.where((f) {
      final isF = _following.contains(f.id);
      final isM = _mutualFriends.contains(f.id);
      return isF || isM;
    }).toList();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.people_alt_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'Friends & Chats',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.shield_outlined, color: textColor, size: 22),
            tooltip: 'Blocked Accounts',
            onPressed: _showBlockedUsersSheet,
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.brandPink,
          unselectedLabelColor: subtitleColor,
          indicatorColor: AppColors.brandPink,
          indicatorWeight: 3,
          tabs: [
            // Tab 1: My Friends (users I follow)
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.people_alt_rounded, size: 16),
                  const SizedBox(width: 5),
                  const Text('My Friends', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  if (myFriendsOnly.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${myFriendsOnly.length}',
                        style: const TextStyle(
                          color: AppColors.brandPink,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Tab 2: Find Friends (Instagram-style live search)
            const Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_search_rounded, size: 16),
                  SizedBox(width: 5),
                  Text('Find Friends', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),

            // Tab 3: Requests
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mark_email_unread_rounded, size: 16),
                  const SizedBox(width: 5),
                  const Text('Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  if (_incomingRequests.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_incomingRequests.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brandPink))
          : TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: My Friends (users I follow)
                _buildMyFriendsTab(myFriendsOnly, isDark, cardBg, textColor, subtitleColor),

                // Tab 2: Find Friends (search from complete database)
                _buildFindFriendsTab(isDark, cardBg, textColor, subtitleColor),

                // Tab 3: Requests (incoming follow/friend requests)
                _buildRequestsTab(isDark, cardBg, textColor, subtitleColor),
              ],
            ),
    );
  }

  /// TAB 1: My Friends - ONLY displays users who are my friend like I followed them
  Widget _buildMyFriendsTab(
    List<UserProfile> friends,
    bool isDark,
    Color cardBg,
    Color textColor,
    Color subtitleColor,
  ) {
    final filtered = friends.where((f) {
      if (_friendFilterQuery.isEmpty) return true;
      final q = _friendFilterQuery.toLowerCase().replaceAll('@', '');
      return f.nickname.toLowerCase().contains(q) ||
          f.displayUsername.toLowerCase().contains(q);
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.brandPink,
      child: Column(
        children: [
          // Filter within my friends
          if (friends.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _friendFilterController,
                onChanged: (val) => setState(() => _friendFilterQuery = val.trim()),
                style: TextStyle(color: textColor, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Filter my friends by name or @username...',
                  hintStyle: TextStyle(color: subtitleColor, fontSize: 12),
                  prefixIcon: Icon(Icons.search_rounded, color: subtitleColor, size: 18),
                  suffixIcon: _friendFilterQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded, color: subtitleColor, size: 16),
                          onPressed: () {
                            _friendFilterController.clear();
                            setState(() => _friendFilterQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: cardBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.brandPink, width: 1.5),
                  ),
                ),
              ),
            ),

          // Friends List
          Expanded(
            child: friends.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              color: AppColors.brandPink.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Text('👥', style: TextStyle(fontSize: 40)),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'No Friends Yet',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Only people you follow appear here. Search usernames on "Find Friends" to follow people and start text chatting!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: subtitleColor, fontSize: 13, height: 1.4),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () => _tabController.animateTo(1),
                            icon: const Icon(Icons.person_search_rounded, size: 18),
                            label: const Text('Find Friends Now'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandPink,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final friend = filtered[index];
                      final isMutual = _mutualFriends.contains(friend.id);
                      final isFollower = _followers.contains(friend.id);
                      final isFollowing = _following.contains(friend.id);
                      final canFollowBack = isFollower && !isFollowing;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            VipAvatar(
                              radius: 24,
                              nickname: friend.nickname,
                              avatarUrl: friend.avatarUrl,
                              isVip: friend.isVip,
                              showVipBadge: true,
                            ),
                            const SizedBox(width: 12),

                            // Name, Username & Reciprocity Badge
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          friend.nickname,
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (friend.isVip) ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.verified_rounded, color: AppColors.coinGold, size: 16),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    friend.displayUsername,
                                    style: const TextStyle(
                                      color: AppColors.brandPink,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isMutual
                                              ? AppColors.success.withOpacity(0.15)
                                              : (isFollower
                                                  ? AppColors.brandIndigo.withOpacity(0.15)
                                                  : Colors.white10),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isMutual
                                              ? 'Mutual Friends 🤝'
                                              : (isFollower ? 'Follows you' : 'Following'),
                                          style: TextStyle(
                                            color: isMutual
                                                ? AppColors.success
                                                : (isFollower ? AppColors.brandIndigo : subtitleColor),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Actions: Follow Back, Video Call, Text Chat
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (canFollowBack) ...[
                                  ElevatedButton(
                                    onPressed: () => _handleFollowBack(friend),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.brandIndigo,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      minimumSize: const Size(0, 36),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                    child: const Text('Follow Back'),
                                  ),
                                  const SizedBox(width: 6),
                                ],

                                // Video Call Button
                                IconButton(
                                  icon: const Icon(Icons.videocam_rounded, color: AppColors.brandPink, size: 22),
                                  tooltip: 'Direct Video Call',
                                  onPressed: () => _startVideoCall(friend),
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppColors.brandPink.withOpacity(0.12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.all(8),
                                  ),
                                ),
                                const SizedBox(width: 6),

                                // Text Chat Button
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => FriendChatScreen(friend: friend),
                                      ),
                                    ).then((_) => _loadData());
                                  },
                                  icon: const Icon(Icons.chat_bubble_rounded, size: 14),
                                  label: const Text('Text Chat'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.brandPink,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    minimumSize: const Size(0, 36),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 2),

                                // 3-dots popup menu: Unfollow, Block, Call
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert_rounded, color: subtitleColor, size: 20),
                                  color: cardBg,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  onSelected: (val) {
                                    if (val == 'unfollow') {
                                      _confirmUnfollow(friend);
                                    } else if (val == 'block') {
                                      _confirmBlock(friend);
                                    } else if (val == 'call') {
                                      _startVideoCall(friend);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(
                                      value: 'call',
                                      child: Row(
                                        children: [
                                          Icon(Icons.videocam_rounded, color: AppColors.brandPink, size: 18),
                                          SizedBox(width: 10),
                                          Text('Direct Video Call', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'unfollow',
                                      child: Row(
                                        children: [
                                          Icon(Icons.person_remove_rounded, color: AppColors.danger, size: 18),
                                          SizedBox(width: 10),
                                          Text('Unfollow', style: TextStyle(fontSize: 13, color: AppColors.danger, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'block',
                                      child: Row(
                                        children: [
                                          Icon(Icons.block_rounded, color: AppColors.danger, size: 18),
                                          SizedBox(width: 10),
                                          Text('Block User', style: TextStyle(fontSize: 13, color: AppColors.danger, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// TAB 2: Find Friends - Instagram-style complete database user search with prefix ranking
  Widget _buildFindFriendsTab(
    bool isDark,
    Color cardBg,
    Color textColor,
    Color subtitleColor,
  ) {
    final showSearchResults = _searchQuery.isNotEmpty;
    final displayList = showSearchResults ? _discoveredUsers : _discoverUsers;

    return RefreshIndicator(
      onRefresh: () async {
        if (_searchQuery.isNotEmpty) {
          _onSearchChanged(_searchQuery);
        } else {
          await _loadData();
        }
      },
      color: AppColors.brandPink,
      child: Column(
        children: [
          // Search Input Bar (searches complete database)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Search by @username from complete database...',
                hintStyle: TextStyle(color: subtitleColor, fontSize: 13),
                prefixIcon: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Text(
                    '@',
                    style: TextStyle(
                      color: AppColors.brandPink,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 0),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandPink),
                        ),
                      )
                    : (_searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, color: subtitleColor, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null),
                filled: true,
                fillColor: cardBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.brandPink, width: 1.8),
                ),
              ),
            ),
          ),

          // Section Subtitle / Instagram Context
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              children: [
                Icon(
                  showSearchResults ? Icons.manage_search_rounded : Icons.explore_rounded,
                  color: AppColors.brandPink,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  showSearchResults
                      ? 'Search Results (${_discoveredUsers.length})'
                      : 'Discover People on Baatkry',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                const Spacer(),
                if (showSearchResults)
                  Text(
                    'Usernames starting with "@$_searchQuery" first',
                    style: TextStyle(color: subtitleColor, fontSize: 11),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // User Cards List
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator(color: AppColors.brandPink))
                : (displayList.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: AppColors.brandPink.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(child: Text('🔍', style: TextStyle(fontSize: 36))),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                showSearchResults
                                    ? 'No users found matching "@$_searchQuery"'
                                    : 'No discoverable accounts yet',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                showSearchResults
                                    ? 'Make sure the username is spelled correctly or try entering fewer letters to browse similar users.'
                                    : 'Users registered with a unique @username will appear here automatically.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: subtitleColor, fontSize: 12.5, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        itemCount: displayList.length,
                        itemBuilder: (context, index) {
                          final user = displayList[index];
                          return _buildDiscoverUserCard(user, isDark, cardBg, textColor, subtitleColor);
                        },
                      )),
          ),
        ],
      ),
    );
  }

  /// Single card for Discover / Find Friends
  Widget _buildDiscoverUserCard(
    UserProfile user,
    bool isDark,
    Color cardBg,
    Color textColor,
    Color subtitleColor,
  ) {
    final isFollowing = _following.contains(user.id);
    final isRequested = _sentRequests.contains(user.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Row(
        children: [
          VipAvatar(
            radius: 20,
            nickname: user.nickname,
            avatarUrl: user.avatarUrl,
            isVip: user.isVip,
            showVipBadge: true,
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
                        user.nickname,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (user.isVip) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified_rounded, color: AppColors.coinGold, size: 14),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  user.displayUsername,
                  style: const TextStyle(
                    color: AppColors.brandPink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Follow Button
          if (isFollowing)
            OutlinedButton.icon(
              onPressed: () => _confirmUnfollow(user),
              icon: const Icon(Icons.check_rounded, color: AppColors.success, size: 14),
              label: const Text('Following'),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? Colors.white70 : Colors.black87,
                side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(0, 34),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
            )
          else if (_followers.contains(user.id))
            ElevatedButton.icon(
              onPressed: () => _handleFollowBack(user),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
              label: const Text('Follow Back'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandIndigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(0, 34),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
            )
          else if (isRequested)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.brandIndigo.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Requested ⏳',
                style: TextStyle(color: AppColors.brandIndigo, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () => _sendFriendRequestTo(user),
              icon: const Icon(Icons.person_add_rounded, size: 14),
              label: const Text('Follow'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandPink,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 34),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          const SizedBox(width: 4),

          // Text Chat Button
          IconButton(
            icon: const Icon(Icons.chat_bubble_rounded, color: AppColors.brandPink, size: 18),
            tooltip: 'Text Chat',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FriendChatScreen(friend: user),
                ),
              ).then((_) => _loadData());
            },
            style: IconButton.styleFrom(
              backgroundColor: AppColors.brandPink.withOpacity(0.12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.all(8),
            ),
          ),

          // 3-dots popup menu: Call, Unfollow, Block
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: subtitleColor, size: 18),
            color: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (val) {
              if (val == 'call') {
                _startVideoCall(user);
              } else if (val == 'unfollow') {
                _confirmUnfollow(user);
              } else if (val == 'block') {
                _confirmBlock(user);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'call',
                child: Row(
                  children: [
                    Icon(Icons.videocam_rounded, color: AppColors.brandPink, size: 18),
                    SizedBox(width: 10),
                    Text('Direct Video Call', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (isFollowing)
                const PopupMenuItem(
                  value: 'unfollow',
                  child: Row(
                    children: [
                      Icon(Icons.person_remove_rounded, color: AppColors.danger, size: 18),
                      SizedBox(width: 10),
                      Text('Unfollow', style: TextStyle(fontSize: 13, color: AppColors.danger, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block_rounded, color: AppColors.danger, size: 18),
                    SizedBox(width: 10),
                    Text('Block User', style: TextStyle(fontSize: 13, color: AppColors.danger, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// TAB 3: Requests - Display incoming requests
  Widget _buildRequestsTab(
    bool isDark,
    Color cardBg,
    Color textColor,
    Color subtitleColor,
  ) {
    if (_incomingRequests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppColors.brandIndigo.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('📬', style: TextStyle(fontSize: 42)),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'No Pending Requests',
                style: TextStyle(
                  color: textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'When people you meet in video chat or discover via @username send you friend requests, they will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: subtitleColor, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.brandPink,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        itemCount: _incomingRequests.length,
        itemBuilder: (context, index) {
          final req = _incomingRequests[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
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
                    VipAvatar(
                      radius: 22,
                      nickname: req.senderName,
                      avatarUrl: req.senderAvatar,
                      isVip: req.senderIsVip,
                      showVipBadge: true,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  req.senderName,
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (req.senderIsVip) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.verified_rounded, color: AppColors.coinGold, size: 16),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Sent you a friend request to chat, call & gift',
                            style: TextStyle(color: subtitleColor, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Accept Only (Instagram model)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _handleRespond(req, true, followBack: false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        child: const Text('Accept'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Accept & Follow Back
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _handleRespond(req, true, followBack: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandIndigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        child: const Text('Accept & Follow Back'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Decline Button
                    OutlinedButton(
                      onPressed: () => _handleRespond(req, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: subtitleColor,
                        side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      child: const Text('Decline'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

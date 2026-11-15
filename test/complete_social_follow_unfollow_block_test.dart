import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monkey_omegle_app/features/friends/friend_chat_screen.dart';
import 'package:monkey_omegle_app/features/friends/friends_screen.dart';
import 'package:monkey_omegle_app/features/profile/my_profile_drawer.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // Set up mock current user
    SupabaseService.instance.currentProfile = const UserProfile(
      id: 'acc1_user_id',
      isAnonymous: false,
      nickname: 'Account One',
      username: 'account1',
      coins: 500,
      isVip: true,
      age: 22,
      birthDate: '2002-01-01',
      isAgeVerified: true,
    );
  });

  group('Instagram Follow, Unfollow & Mutual Friendship Logic', () {
    test('Account 1 follows Account 2, updates following & creates request for Account 2', () async {
      final res = await SupabaseService.instance.followUser(
        'acc2_user_id',
        peerName: 'Account Two',
        peerAvatar: 'https://example.com/avatar2.jpg',
      );

      expect(res['success'], isTrue);
      expect(res['isMutual'], isFalse);

      final isF = await SupabaseService.instance.isFollowing('acc2_user_id');
      expect(isF, isTrue);

      final friends = await SupabaseService.instance.fetchFriends();
      expect(friends.any((f) => f.id == 'acc2_user_id'), isTrue);

      // Now switch current profile to Account 2 to verify Account 2 sees the incoming request!
      SupabaseService.instance.currentProfile = const UserProfile(
        id: 'acc2_user_id',
        isAnonymous: false,
        nickname: 'Account Two',
        username: 'account2',
        coins: 200,
        age: 24,
        birthDate: '2000-05-15',
        isAgeVerified: true,
      );

      final incomingRequests = await SupabaseService.instance.fetchFriendRequests();
      expect(incomingRequests.isNotEmpty, isTrue);
      final reqFromAcc1 = incomingRequests.firstWhere((r) => r.senderId == 'acc1_user_id');
      expect(reqFromAcc1.senderName, equals('Account One'));
      expect(reqFromAcc1.receiverId, equals('acc2_user_id'));

      // Account 2 accepts with follow back
      final respondRes = await SupabaseService.instance.respondToFriendRequest(
        requestId: reqFromAcc1.id,
        accept: true,
        followBack: true,
      );
      expect(respondRes['success'], isTrue);

      final acc2Friends = await SupabaseService.instance.fetchFriends();
      expect(acc2Friends.any((f) => f.id == 'acc1_user_id'), isTrue);

      // Verify mutual friendship
      final isMutual = await SupabaseService.instance.isMutualFriend('acc1_user_id');
      expect(isMutual, isTrue);
    });

    test('Unfollowing a user removes them from following and friends list', () async {
      await SupabaseService.instance.followUser('peer_999', peerName: 'Peer 999');
      expect(await SupabaseService.instance.isFollowing('peer_999'), isTrue);

      final unfollowRes = await SupabaseService.instance.unfollowUser('peer_999');
      expect(unfollowRes['success'], isTrue);

      expect(await SupabaseService.instance.isFollowing('peer_999'), isFalse);
      final friends = await SupabaseService.instance.fetchFriends();
      expect(friends.any((f) => f.id == 'peer_999'), isFalse);
    });
  });

  group('Block & Unblock System with Safety Exclusions', () {
    test('Blocking a user removes connections and excludes from search and requests', () async {
      final prefs = await SharedPreferences.getInstance();

      // Seed another user
      const userB = UserProfile(
        id: 'user_b_id',
        isAnonymous: false,
        nickname: 'User B',
        username: 'user_b',
      );
      await prefs.setStringList('local_registered_users', [jsonEncode(userB.toMap())]);

      // Account 1 follows User B
      await SupabaseService.instance.followUser('user_b_id', peerName: 'User B');
      expect(await SupabaseService.instance.isFollowing('user_b_id'), isTrue);

      // Account 1 blocks User B
      await SupabaseService.instance.blockUser('user_b_id', 'Spam behavior');
      expect(SupabaseService.instance.isUserBlocked('user_b_id'), isTrue);

      // Follow relationship is severed immediately
      expect(await SupabaseService.instance.isFollowing('user_b_id'), isFalse);
      final friends = await SupabaseService.instance.fetchFriends();
      expect(friends.any((f) => f.id == 'user_b_id'), isFalse);

      // User B must NOT appear in search results
      final searchResults = await SupabaseService.instance.searchUsersByUsername('user_b');
      expect(searchResults.any((u) => u.id == 'user_b_id'), isFalse);

      // Blocked users list returns User B
      final blockedList = await SupabaseService.instance.fetchBlockedUsersList();
      expect(blockedList.any((u) => u.id == 'user_b_id'), isTrue);

      // Unblocking User B removes from block list
      await SupabaseService.instance.unblockUser('user_b_id');
      expect(SupabaseService.instance.isUserBlocked('user_b_id'), isFalse);
    });
  });

  group('UI Widgets: FriendsScreen, Chat Actions & Drawer', () {
    testWidgets('FriendsScreen displays Follow / Following toggle and Blocked Accounts action', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      const friend = UserProfile(
        id: 'friend_123',
        isAnonymous: false,
        nickname: 'Alex Explorer',
        username: 'alex_exp',
        coins: 100,
      );
      await prefs.setStringList('local_following_acc1_user_id', ['friend_123']);
      await prefs.setString('local_user_info_friend_123', jsonEncode(friend.toMap()));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FriendsScreen(initialTabIndex: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check AppBar title and Blocked Accounts icon
      expect(find.text('Friends & Chats'), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

      // Check My Friends tab lists Alex
      expect(find.text('Alex Explorer'), findsOneWidget);
      expect(find.text('@alex_exp'), findsOneWidget);
      expect(find.text('Text Chat'), findsOneWidget);

      // Switch to Find Friends tab
      await tester.tap(find.text('Find Friends'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('FriendChatScreen displays 3-dots popup menu with Unfollow and Block', (tester) async {
      const friend = UserProfile(
        id: 'friend_777',
        isAnonymous: false,
        nickname: 'Sara Smith',
        username: 'sara_s',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FriendChatScreen(friend: friend),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sara Smith'), findsOneWidget);
      expect(find.text('@sara_s'), findsOneWidget);

      // Open 3-dots menu
      final moreBtn = find.byIcon(Icons.more_vert_rounded);
      expect(moreBtn, findsOneWidget);
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();

      expect(find.text('Unfollow'), findsOneWidget);
      expect(find.text('Block User'), findsOneWidget);
    });

    testWidgets('MyProfileDrawer contains Blocked Accounts tile', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              drawer: MyProfileDrawer(),
              body: Center(child: Text('Home')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Check Blocked Accounts tile exists
      expect(find.text('Blocked Accounts'), findsOneWidget);
      expect(find.text('Manage blocked users and unblock'), findsOneWidget);
    });
  });
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:monkey_omegle_app/features/friends/friends_screen.dart';
import 'package:monkey_omegle_app/models/friend_request.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Find Friends Complete Database Search & Instagram Prefix Priority', () {
    test('1. searchUsersByUsername finds second account across database caches and ranks prefix matches first', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SupabaseService.instance;

      const myId = 'account_1_main';
      service.currentProfile = const UserProfile(
        id: myId,
        isAnonymous: false,
        nickname: 'Main User',
        username: 'usman_main',
      );

      // Register second account (account_2) and another user (peer_3)
      await prefs.setStringList('local_registered_users', [
        jsonEncode({
          'id': 'account_2_second',
          'username': 'usman_second',
          'nickname': 'Usman Alt Account',
          'coins': 120,
        }),
        jsonEncode({
          'id': 'peer_contains',
          'username': 'focusman', // contains 'usman', but does NOT start with 'usman'
          'nickname': 'Focus Man',
          'coins': 200,
        }),
        jsonEncode({
          'id': myId, // current user should be excluded
          'username': 'usman_main',
          'nickname': 'Main User',
        }),
      ]);

      // Set explicit owner key to simulate registration
      await prefs.setString('local_username_owner_usman_second', 'account_2_second');
      await prefs.setString('local_user_username_account_2_second', 'usman_second');

      // Search for 'usman'
      final results = await service.searchUsersByUsername('usman');

      // Second account must be found!
      expect(results.any((u) => u.username == 'usman_second'), isTrue);

      // Current user's own main account must be excluded
      expect(results.any((u) => u.id == myId), isFalse);

      // Instagram ranking: username starting with 'usman' must come before username containing 'usman'
      final indexSecond = results.indexWhere((u) => u.username == 'usman_second');
      final indexContains = results.indexWhere((u) => u.username == 'focusman');
      expect(indexSecond, lessThan(indexContains));
    });

    test('2. My Friends only displays users that current user followed; pending requests stay in Requests', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SupabaseService.instance;

      const meId = 'user_active';
      const followedFriendId = 'user_followed';
      const requesterOnlyId = 'user_requester_only';

      service.currentProfile = const UserProfile(
        id: meId,
        isAnonymous: false,
        nickname: 'Active User',
        username: 'active_user',
      );

      // Save user info for both
      await prefs.setString('local_user_info_$followedFriendId', jsonEncode({
        'id': followedFriendId,
        'nickname': 'Followed Friend',
        'username': 'followed_friend',
      }));
      await prefs.setString('local_user_info_$requesterOnlyId', jsonEncode({
        'id': requesterOnlyId,
        'nickname': 'Requester Only',
        'username': 'requester_only',
      }));

      // Current user follows followedFriendId:
      await prefs.setStringList('local_following_$meId', [followedFriendId]);

      // requesterOnlyId sent a request to current user, but current user has NOT followed them:
      final request = FriendRequest(
        id: 'req_123',
        senderId: requesterOnlyId,
        senderName: 'Requester Only',
        senderAvatar: null,
        receiverId: meId,
        receiverName: 'Active User',
        status: 'pending',
        createdAt: DateTime.now(),
      );
      await prefs.setStringList('local_friend_requests', [jsonEncode(request.toMap())]);

      // fetchFriends returns friends list
      final friends = await service.fetchFriends();
      expect(friends.any((f) => f.id == followedFriendId), isTrue);

      // Requests list contains requesterOnlyId
      final incoming = await service.fetchFriendRequests();
      expect(incoming.any((r) => r.senderId == requesterOnlyId), isTrue);

      // requesterOnlyId is NOT followed by me yet
      final isFollowedByMe = await service.isFollowing(requesterOnlyId);
      expect(isFollowedByMe, isFalse);
    });

    testWidgets('3. FriendsScreen renders 3 tabs: My Friends, Find Friends, Requests', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      const meId = 'usr_tester';
      const friendId = 'usr_friend_1';

      final service = SupabaseService.instance;
      service.currentProfile = const UserProfile(
        id: meId,
        isAnonymous: false,
        nickname: 'Tester',
        username: 'tester_pro',
      );

      // Add 1 friend I follow
      await prefs.setStringList('local_following_$meId', [friendId]);
      await prefs.setStringList('local_friends_$meId', [friendId]);
      await prefs.setString('local_user_info_$friendId', jsonEncode({
        'id': friendId,
        'nickname': 'Zack Coder',
        'username': 'zack_coder',
      }));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FriendsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the 3 tabs are present in AppBar
      expect(find.text('My Friends'), findsOneWidget);
      expect(find.text('Find Friends'), findsOneWidget);
      expect(find.text('Requests'), findsOneWidget);

      // On Tab 1 (My Friends): friend is visible with Text Chat & Video Call buttons
      expect(find.text('Zack Coder'), findsOneWidget);
      expect(find.text('@zack_coder'), findsOneWidget);
      expect(find.text('Text Chat'), findsOneWidget);
      expect(find.byTooltip('Direct Video Call'), findsOneWidget);

      // Switch to Tab 2 (Find Friends)
      await tester.tap(find.text('Find Friends'));
      await tester.pumpAndSettle();

      // Find Friends has search bar with @ prefix
      expect(find.text('Search by @username from complete database...'), findsOneWidget);
      expect(find.text('@'), findsOneWidget);

      // Switch to Tab 3 (Requests)
      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();
      expect(find.text('No Pending Requests'), findsOneWidget);
    });
  });
}

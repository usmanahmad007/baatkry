import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:monkey_omegle_app/core/theme/app_theme.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/models/friend_request.dart';
import 'package:monkey_omegle_app/services/supabase_service.dart';
import 'package:monkey_omegle_app/features/profile/complete_profile_modal.dart';
import 'package:monkey_omegle_app/features/friends/friends_screen.dart';
import 'package:monkey_omegle_app/features/friends/friend_chat_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('1. Unique Username Validation & Availability', () {
    test('Username must be 3-20 characters, alphanumeric and underscore only', () async {
      final service = SupabaseService.instance;

      // Empty
      final emptyRes = await service.checkUsernameAvailability('');
      expect(emptyRes['available'], isFalse);
      expect(emptyRes['message'], contains('empty'));

      // Too short
      final shortRes = await service.checkUsernameAvailability('ab');
      expect(shortRes['available'], isFalse);
      expect(shortRes['message'], contains('at least 3'));

      // Too long (>20)
      final longRes = await service.checkUsernameAvailability('abcdefghijklmnopqrstuv');
      expect(longRes['available'], isFalse);
      expect(longRes['message'], contains('exceed 20'));

      // Invalid characters
      final invalidRes = await service.checkUsernameAvailability('user name!');
      expect(invalidRes['available'], isFalse);
      expect(invalidRes['message'], contains('underscores'));

      // Valid and available
      final validRes = await service.checkUsernameAvailability('usman_king');
      expect(validRes['available'], isTrue);
      expect(validRes['message'], equals('Username is available'));
    });

    test('Username uniqueness is case-insensitive and prevents duplicate registration', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SupabaseService.instance;

      // Pre-register user 1 with username "alex_star"
      await prefs.setString('local_username_owner_alex_star', 'user_1');
      await prefs.setStringList('local_registered_users', [
        jsonEncode({
          'id': 'user_1',
          'username': 'alex_star',
          'nickname': 'Alex',
        }),
      ]);

      // Another user attempts to register the same username with different casing
      final checkRes = await service.checkUsernameAvailability('Alex_Star', currentUserId: 'user_2');
      expect(checkRes['available'], isFalse);
      expect(checkRes['message'], equals('Username already taken'));

      // User 1 checking their own username is allowed
      final selfCheck = await service.checkUsernameAvailability('alex_star', currentUserId: 'user_1');
      expect(selfCheck['available'], isTrue);
    });

    test('setUsernameAndDob enforces 18+ requirement and persists correctly', () async {
      final service = SupabaseService.instance;
      service.currentProfile = const UserProfile(
        id: 'usr_valid_age',
        isAnonymous: false,
        nickname: 'Zack',
      );

      // Attempt with under 18 DOB (e.g. born 10 years ago)
      final minorDob = DateTime.now().subtract(const Duration(days: 365 * 14));
      expect(
        () => service.setUsernameAndDob(username: 'zack_pro', dateOfBirth: minorDob),
        throwsA(predicate((e) => e.toString().contains('18 years old'))),
      );

      // Attempt with adult DOB (e.g. 22 years old)
      final adultDob = DateTime.now().subtract(const Duration(days: 365 * 22));
      final res = await service.setUsernameAndDob(username: 'zack_pro', dateOfBirth: adultDob);
      expect(res['success'], isTrue);
      expect(res['username'], equals('zack_pro'));

      final updated = service.currentProfile;
      expect(updated?.username, equals('zack_pro'));
      expect(updated?.displayUsername, equals('@zack_pro'));
      expect(updated?.isAgeVerified, isTrue);
      expect(updated?.needsProfileCompletion, isFalse);
    });
  });

  group('2. Search Users by @Username', () {
    test('searchUsersByUsername finds users by username or nickname and excludes current user', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SupabaseService.instance;

      service.currentProfile = const UserProfile(
        id: 'me_id',
        isAnonymous: false,
        nickname: 'Current User',
        username: 'current_hero',
      );

      // Register two other users
      await prefs.setStringList('local_registered_users', [
        jsonEncode({
          'id': 'peer_1',
          'username': 'usman_flutter',
          'nickname': 'Usman Dev',
          'coins': 500,
        }),
        jsonEncode({
          'id': 'peer_2',
          'username': 'sarah_gamer',
          'nickname': 'Sarah Gamer',
          'coins': 120,
        }),
      ]);

      // Search by partial username
      final results = await service.searchUsersByUsername('usman');
      expect(results.length, equals(1));
      expect(results.first.username, equals('usman_flutter'));
      expect(results.first.displayUsername, equals('@usman_flutter'));

      // Search for self should return empty (cannot add self)
      final selfResults = await service.searchUsersByUsername('current_hero');
      expect(selfResults, isEmpty);
    });
  });

  group('3. Instagram-Style Follower & Reciprocity System', () {
    test('Accepting friend request follows the receiver without forcing follow-back', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SupabaseService.instance;

      const userA = 'user_alice';
      const userB = 'user_bob';

      // Current user is Bob
      service.currentProfile = const UserProfile(
        id: userB,
        isAnonymous: false,
        nickname: 'Bob',
        username: 'bob_the_builder',
      );

      // Alice sent a friend request to Bob
      const reqId = 'req_alice_to_bob';
      final req = FriendRequest(
        id: reqId,
        senderId: userA,
        senderName: 'Alice',
        senderAvatar: null,
        receiverId: userB,
        receiverName: 'Bob',
        status: 'pending',
        createdAt: DateTime.now(),
      );
      await prefs.setStringList('local_friend_requests', [jsonEncode(req.toMap())]);

      // Bob accepts the request WITHOUT following back (Instagram model)
      final res = await service.respondToFriendRequest(
        requestId: reqId,
        accept: true,
        followBack: false,
      );
      expect(res['success'], isTrue);

      // Check reciprocity
      // Alice is following Bob:
      final isAliceFollowingBob = (prefs.getStringList('local_following_$userA') ?? []).contains(userB);
      expect(isAliceFollowingBob, isTrue);

      // Bob is followed by Alice:
      final isBobFollowedByAlice = await service.isFollowedBy(userA);
      expect(isBobFollowedByAlice, isTrue);

      // Bob has NOT followed back yet:
      final isBobFollowingAlice = await service.isFollowing(userA);
      expect(isBobFollowingAlice, isFalse);

      // They are not mutual friends yet:
      final isMutual = await service.isMutualFriend(userA);
      expect(isMutual, isFalse);

      // Now Bob decides to follow Alice back!
      final followBackRes = await service.followBackUser(userA);
      expect(followBackRes['success'], isTrue);
      expect(followBackRes['isMutual'], isTrue);

      // Now both are following each other mutually:
      expect(await service.isFollowing(userA), isTrue);
      expect(await service.isMutualFriend(userA), isTrue);
    });
  });

  group('4. CompleteProfileModal & Friends UI Widgets', () {
    testWidgets('CompleteProfileModal renders username field with live status text', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CompleteProfileModal(dismissible: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Complete Your Profile'), findsOneWidget);
      expect(find.text('Unique Username'), findsOneWidget);
      expect(find.text('Date of Birth (18+ Verification)'), findsOneWidget);
      expect(find.text('@'), findsOneWidget);

      // Enter username
      await tester.enterText(find.byType(TextField), 'cool_coder');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Should show green "Username is available"
      expect(find.text('Username is available'), findsOneWidget);
      final statusWidget = tester.widget<Text>(find.text('Username is available'));
      expect(statusWidget.style?.color, equals(AppColors.success));
    });

    testWidgets('FriendChatScreen displays username and has video call button in actions', (tester) async {
      const friend = UserProfile(
        id: 'peer_chat_id',
        isAnonymous: false,
        nickname: 'Samantha Star',
        username: 'samantha_star',
        gender: 'women',
        country: 'United Kingdom',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FriendChatScreen(friend: friend),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check displayed nickname and @username
      expect(find.text('Samantha Star'), findsOneWidget);
      expect(find.text('@samantha_star'), findsOneWidget);

      // Check Video Call action button exists in AppBar
      expect(find.byTooltip('Direct Video Call'), findsOneWidget);
      expect(find.byTooltip('Send Gift'), findsOneWidget);
    });

    testWidgets('FriendsScreen has Search by @username and Video Call button', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      const meId = 'my_active_user';
      const friendId = 'friend_jane';

      final service = SupabaseService.instance;
      service.currentProfile = const UserProfile(
        id: meId,
        isAnonymous: false,
        nickname: 'Me',
        username: 'my_username',
      );

      // Add Jane as friend
      await prefs.setStringList('local_friends_$meId', [friendId]);
      await prefs.setStringList('local_following_$meId', [friendId]);
      await prefs.setStringList('local_followers_$meId', [friendId]);
      await prefs.setString('local_user_info_$friendId', jsonEncode({
        'id': friendId,
        'nickname': 'Jane Doe',
        'username': 'jane_doe',
        'gender': 'women',
      }));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FriendsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify search input
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('@jane_doe'), findsOneWidget);
      expect(find.text('Mutual Friends 🤝'), findsOneWidget);

      // Verify Video Call and Text Chat buttons
      expect(find.byTooltip('Direct Video Call'), findsOneWidget);
      expect(find.text('Text Chat'), findsOneWidget);
    });
  });
}

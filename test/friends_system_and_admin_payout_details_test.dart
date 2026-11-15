import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:monkey_omegle_app/models/friend_request.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/models/virtual_gift.dart';
import 'package:monkey_omegle_app/services/supabase_service.dart';
import 'package:monkey_omegle_app/features/friends/friends_screen.dart';
import 'package:monkey_omegle_app/features/friends/friend_chat_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('1. Payout Processing 3% Fee & Admin Beneficiary Details', () {
    test('3% payout fee calculation is accurate and net amount is correct', () async {
      final prefs = await SharedPreferences.getInstance();
      const creatorId = 'creator_test_3pct';

      final service = SupabaseService.instance;
      service.currentProfile = const UserProfile(
        id: creatorId,
        isAnonymous: false,
        nickname: 'Alice Streamer',
        coins: 1000,
      );

      // Approve creator status
      await prefs.setBool('local_is_creator_$creatorId', true);
      await prefs.setStringList('local_approved_creators', [creatorId]);
      await prefs.setDouble('local_creator_avail_$creatorId', 100.0);
      await prefs.setDouble('local_creator_withdrawn_$creatorId', 0.0);

      const requestedGross = 50.0;
      final expectedFee = (requestedGross * 0.03 * 100).round() / 100.0; // 1.50
      final expectedNet = requestedGross - expectedFee; // 48.50

      final res = await service.requestCreatorWithdrawal(
        payoutAccountId: 'acc_bank_01',
        amountUsd: requestedGross,
        feeUsd: expectedFee,
        payoutMethod: 'bank_transfer',
        payoutDetails: {
          'bank_name': 'Chase International',
          'account_holder': 'Alice Streamer',
          'account_number': 'US64CHAS0987654321',
          'routing_code': 'CHASUS33',
        },
      );

      expect(res['success'], isTrue);
      expect(res['withdrawal'], isNotNull);

      final w = res['withdrawal'];
      expect(w.amountUsd, equals(50.0));
      expect(w.feeUsd, equals(1.50));
      expect(w.netAmountUsd, equals(expectedNet));
      expect(w.payoutMethod, equals('bank_transfer'));
      expect(w.payoutDetails['bank_name'], equals('Chase International'));
      expect(w.payoutDetails['account_number'], equals('US64CHAS0987654321'));
    });

    test('Admin Users tab returns only real registered/active users (no spam/dummy bots)', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SupabaseService.instance;

      service.currentProfile = const UserProfile(
        id: 'real_user_001',
        isAnonymous: false,
        nickname: 'RealUserAlpha',
      );

      // Add a real registered user into local storage
      await prefs.setStringList('local_registered_users', [
        jsonEncode({
          'id': 'real_user_002',
          'nickname': 'RealUserBeta',
          'email': 'beta@example.com',
          'created_at': DateTime.now().toIso8601String(),
          'coins': 200,
          'is_vip': false,
        }),
      ]);

      final users = await service.fetchAdminUsers();

      // Ensure no mock bots exist in the list
      expect(users.any((u) => u.username == 'BannedBot404'), isFalse);
      expect(users.any((u) => u.username == 'ToxicCaller99'), isFalse);
      expect(users.any((u) => u.username == 'Elena_Streamer'), isFalse);
      expect(users.any((u) => u.username == 'Sarah_VIP'), isFalse);

      // Ensure real users are present
      expect(users.any((u) => u.id == 'real_user_001'), isTrue);
      expect(users.any((u) => u.id == 'real_user_002'), isTrue);
    });
  });

  group('2. Friends Request System (Enforced During Video Chat)', () {
    test('Cannot send friend request to self', () async {
      final service = SupabaseService.instance;
      service.currentProfile = const UserProfile(
        id: 'user_alpha',
        isAnonymous: false,
        nickname: 'Alpha',
      );

      expect(
        () => service.sendFriendRequest(
          receiverId: 'user_alpha',
          receiverName: 'Alpha',
          isDuringVideoChat: true,
        ),
        throwsException,
      );
    });

    test('Sending friend request to peer succeeds and saves pending request', () async {
      final service = SupabaseService.instance;
      service.currentProfile = const UserProfile(
        id: 'user_alpha',
        isAnonymous: false,
        nickname: 'Alpha',
        isVip: true,
      );

      final res = await service.sendFriendRequest(
        receiverId: 'user_beta',
        receiverName: 'Beta',
        isDuringVideoChat: true,
      );

      expect(res['success'], isTrue);
      expect(res['message'], contains('Friend request sent to Beta'));

      // Check status from Alpha's perspective
      final statusAlpha = await service.checkFriendStatus('user_beta');
      expect(statusAlpha, equals('pending_sent'));

      // Switch to Beta perspective
      service.currentProfile = const UserProfile(
        id: 'user_beta',
        isAnonymous: false,
        nickname: 'Beta',
      );

      final incoming = await service.fetchFriendRequests();
      expect(incoming.length, equals(1));
      expect(incoming.first.senderId, equals('user_alpha'));
      expect(incoming.first.senderName, equals('Alpha'));
      expect(incoming.first.senderIsVip, isTrue);
      expect(incoming.first.isPending, isTrue);

      final statusBeta = await service.checkFriendStatus('user_alpha');
      expect(statusBeta, equals('pending_received'));
    });

    test('Accepting friend request adds both users to mutual friends', () async {
      final service = SupabaseService.instance;
      service.currentProfile = const UserProfile(
        id: 'user_alpha',
        isAnonymous: false,
        nickname: 'Alpha',
      );

      // Alpha sends request to Beta
      final sendRes = await service.sendFriendRequest(
        receiverId: 'user_beta',
        receiverName: 'Beta',
        isDuringVideoChat: true,
      );
      final req = sendRes['request'] as FriendRequest;

      // Beta accepts request
      service.currentProfile = const UserProfile(
        id: 'user_beta',
        isAnonymous: false,
        nickname: 'Beta',
      );

      final acceptRes = await service.respondToFriendRequest(
        requestId: req.id,
        accept: true,
      );
      expect(acceptRes['success'], isTrue);
      expect(acceptRes['status'], equals('accepted'));

      // Verify Beta sees Alpha as friend
      final betaFriends = await service.fetchFriends();
      expect(betaFriends.any((f) => f.id == 'user_alpha'), isTrue);

      // Verify Alpha sees Beta as friend
      service.currentProfile = const UserProfile(
        id: 'user_alpha',
        isAnonymous: false,
        nickname: 'Alpha',
      );
      final alphaFriends = await service.fetchFriends();
      expect(alphaFriends.any((f) => f.id == 'user_beta'), isTrue);

      // Status between both is 'friends'
      expect(await service.checkFriendStatus('user_beta'), equals('friends'));
    });

    test('Declining friend request does not add friend and marks declined', () async {
      final service = SupabaseService.instance;
      service.currentProfile = const UserProfile(
        id: 'user_one',
        isAnonymous: false,
        nickname: 'One',
      );

      final sendRes = await service.sendFriendRequest(
        receiverId: 'user_two',
        receiverName: 'Two',
        isDuringVideoChat: true,
      );
      final req = sendRes['request'] as FriendRequest;

      service.currentProfile = const UserProfile(
        id: 'user_two',
        isAnonymous: false,
        nickname: 'Two',
      );

      final declineRes = await service.respondToFriendRequest(
        requestId: req.id,
        accept: false,
      );
      expect(declineRes['success'], isTrue);
      expect(declineRes['status'], equals('declined'));

      final twoFriends = await service.fetchFriends();
      expect(twoFriends.isEmpty, isTrue);
    });
  });

  group('3. Friends 1-on-1 Text-Only Chat & Virtual Gifting', () {
    test('Can send text messages between friends and stream updates', () async {
      final service = SupabaseService.instance;
      service.currentProfile = const UserProfile(
        id: 'friend_a',
        isAnonymous: false,
        nickname: 'Friend A',
      );

      final msg1 = await service.sendFriendChatMessage(
        friendId: 'friend_b',
        text: 'Hello from Friend A!',
      );

      expect(msg1.senderId, equals('friend_a'));
      expect(msg1.receiverId, equals('friend_b'));
      expect(msg1.text, equals('Hello from Friend A!'));
      expect(msg1.isGift, isFalse);

      final history = await service.fetchFriendChatMessages('friend_b');
      expect(history.length, equals(1));
      expect(history.first.text, equals('Hello from Friend A!'));
    });

    test('Gifting in friend chat executes full gifting logic: sender debit, receiver credit, creator 70% earnings', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SupabaseService.instance;

      const senderId = 'chat_gifter_101';
      const friendId = 'creator_friend_202';

      // Setup friend as approved creator
      await prefs.setBool('local_is_creator_$friendId', true);
      await prefs.setStringList('local_approved_creators', [friendId]);
      await prefs.setDouble('local_creator_avail_$friendId', 0.0);
      await prefs.setInt('local_user_coins_$friendId', 50);

      // Setup sender with 200 coins
      service.currentProfile = const UserProfile(
        id: senderId,
        isAnonymous: false,
        nickname: 'Gifter John',
        coins: 200,
      );
      await prefs.setInt('local_user_coins_$senderId', 200);

      final gift = VirtualGift.defaultGifts.firstWhere((g) => g.coinPrice == 50); // e.g. Rose 50 coins

      // 1. Send virtual gift (deducts 50 coins from sender)
      final sendRes = await service.sendVirtualGift(
        gift: gift,
        receiverId: friendId,
        receiverName: 'Creator Mary',
        roomId: 'friend_chat_$friendId',
      );
      expect(sendRes['success'], isTrue);
      expect(service.currentProfile!.coins, equals(150));

      // 2. Credit received gift coins to friend (and calculate creator 70% cash earnings)
      service.currentProfile = const UserProfile(
        id: friendId,
        isAnonymous: false,
        nickname: 'Creator Mary',
        coins: 50,
      );

      await service.creditReceivedGiftCoins(
        coins: gift.coinPrice,
        senderId: senderId,
        senderName: 'Gifter John',
        giftName: gift.name,
      );

      // Receiver coin balance increased by 50 -> 100
      expect(service.currentProfile!.coins, equals(100));

      // Creator 70% cash earnings: 50 coins * $0.002 = $0.10 gross * 70% = $0.07 net
      final creatorAvail = prefs.getDouble('local_creator_avail_$friendId') ?? 0.0;
      expect(creatorAvail, closeTo(0.07, 0.001));

      // 3. Post gift message into the 1-on-1 friend text chat
      service.currentProfile = const UserProfile(
        id: senderId,
        isAnonymous: false,
        nickname: 'Gifter John',
        coins: 150,
      );

      final giftMsg = await service.sendFriendChatMessage(
        friendId: friendId,
        text: 'Sent ${gift.name} 🎁',
        isGift: true,
        giftName: gift.name,
        giftEmoji: gift.emoji,
        giftCoins: gift.coinPrice,
      );

      expect(giftMsg.isGift, isTrue);
      expect(giftMsg.giftName, equals(gift.name));
      expect(giftMsg.giftCoins, equals(50));

      final chatHistory = await service.fetchFriendChatMessages(friendId);
      expect(chatHistory.any((m) => m.isGift && m.giftName == gift.name), isTrue);
    });
  });

  group('4. Separate Friends UI & Friend Chat Screen Widgets', () {
    testWidgets('FriendsScreen renders Friends and Requests tabs', (tester) async {
      final service = SupabaseService.instance;
      service.currentProfile = const UserProfile(
        id: 'ui_user',
        isAnonymous: false,
        nickname: 'UI Tester',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FriendsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Friends & Chats'), findsOneWidget);
      expect(find.text('My Friends'), findsOneWidget);
      expect(find.text('Requests'), findsOneWidget);
    });

    testWidgets('FriendChatScreen supports text chat, direct video call, and 🎁 gift button', (tester) async {
      final service = SupabaseService.instance;
      service.currentProfile = const UserProfile(
        id: 'chat_user_1',
        isAnonymous: false,
        nickname: 'User One',
      );

      const friend = UserProfile(
        id: 'chat_user_2',
        isAnonymous: false,
        nickname: 'Friend Two',
        isVip: true,
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: FriendChatScreen(friend: friend),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check friend details in header
      expect(find.text('Friend Two'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);

      // Verify video call and gift buttons exist in friend chat
      expect(find.byTooltip('Direct Video Call'), findsOneWidget);
      expect(find.byTooltip('Send Gift'), findsOneWidget);

      // Verify text input exists
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });
  });
}

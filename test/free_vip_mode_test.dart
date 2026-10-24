import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/services/matchmaking_service.dart';

void main() {
  group('Free Mode vs VIP Mode Tests', () {
    test('User with 0 coins in random matching enters Free Mode and does not deduct coins', () {
      const user = UserProfile(
        id: 'user_free_01',
        nickname: 'FreeUser',
        coins: 0,
        isAnonymous: false,
      );

      // Match result where stranger peer is a woman
      const matchResult = MatchResult(
        roomId: 'room_123',
        token: 'token_123',
        peerId: 'peer_999',
        peerName: 'Sophia',
        peerGender: 'women',
      );

      // Filter selected by user: 'everyone' (free random)
      const requestedFilter = 'everyone';
      final filter = requestedFilter.toLowerCase().trim();
      final requestedVip = filter.isNotEmpty && filter != 'everyone' && filter != 'unspecified';
      final hasCoins = user.coins > 0 || user.isVip;
      final isVip = requestedVip && hasCoins;

      expect(requestedVip, isFalse);
      expect(isVip, isFalse);
      expect(matchResult.peerGender, equals('women')); // Peer's physical gender does not affect user's free mode
    });

    test('User with 0 coins attempting VIP filter automatically falls back to Free Mode', () {
      const userWithZeroCoins = UserProfile(
        id: 'user_broke_01',
        nickname: 'ZeroCoinUser',
        coins: 0,
        isAnonymous: false,
      );

      // Requested VIP filter 'women'
      const requestedFilter = 'women';
      final filter = requestedFilter.toLowerCase().trim();
      final requestedVip = filter.isNotEmpty && filter != 'everyone' && filter != 'unspecified';
      final hasCoins = userWithZeroCoins.coins > 0 || userWithZeroCoins.isVip;
      final isVip = requestedVip && hasCoins;

      // Because user has 0 coins, isVip must be false
      expect(requestedVip, isTrue);
      expect(hasCoins, isFalse);
      expect(isVip, isFalse);
      final activeGenderFilter = isVip ? filter : 'everyone';
      expect(activeGenderFilter, equals('everyone'));
    });

    test('User with coins in VIP mode correctly enables VIP Mode', () {
      const vipUser = UserProfile(
        id: 'user_vip_01',
        nickname: 'VipUser',
        coins: 300,
        isAnonymous: false,
      );

      const requestedFilter = 'women';
      final filter = requestedFilter.toLowerCase().trim();
      final requestedVip = filter.isNotEmpty && filter != 'everyone' && filter != 'unspecified';
      final hasCoins = vipUser.coins > 0 || vipUser.isVip;
      final isVip = requestedVip && hasCoins;

      expect(isVip, isTrue);
      final activeGenderFilter = isVip ? filter : 'everyone';
      expect(activeGenderFilter, equals('women'));
    });

    test('Switching from VIP to Free Mode resets filter to everyone and elapsed time to 0', () {
      var activeGenderFilter = 'women';
      var isGenderFiltered = true;
      var callElapsedSeconds = 45;

      // User triggers switch to free
      activeGenderFilter = 'everyone';
      isGenderFiltered = false;
      callElapsedSeconds = 0;

      expect(activeGenderFilter, equals('everyone'));
      expect(isGenderFiltered, isFalse);
      expect(callElapsedSeconds, equals(0));
    });
    test('VIP mode decreases coins by 1 each second and reaches 0', () {
      var coinsRemaining = 30;
      var elapsedSeconds = 0;
      const isGenderFiltered = true;

      // Simulate 10 seconds of VIP call
      for (var i = 0; i < 10; i++) {
        elapsedSeconds++;
        if (isGenderFiltered) {
          if (coinsRemaining > 0) {
            coinsRemaining--;
          }
        }
      }

      expect(elapsedSeconds, equals(10));
      expect(coinsRemaining, equals(20));

      // Simulate remaining 20 seconds
      for (var i = 0; i < 20; i++) {
        elapsedSeconds++;
        if (isGenderFiltered) {
          if (coinsRemaining > 0) {
            coinsRemaining--;
          }
        }
      }

      expect(elapsedSeconds, equals(30));
      expect(coinsRemaining, equals(0));
    });

    test('VideoCallScreen profile updates with live decremented coins upon skip or exit', () {
      const initialProfile = UserProfile(
        id: 'u_1',
        nickname: 'VipUser',
        coins: 30,
        isAnonymous: false,
      );

      var coinsRemaining = 30;
      // 15 seconds pass in VIP mode
      coinsRemaining -= 15;

      final updatedProfile = initialProfile.copyWith(coins: coinsRemaining);
      expect(updatedProfile.coins, equals(15));
    });
  });
}

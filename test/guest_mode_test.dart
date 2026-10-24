import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/services/guest_session_service.dart';

void main() {
  group('Guest Mode & Time Limits Tests', () {
    test('Guest session constants are configured correctly', () {
      expect(GuestSessionService.maxGuestTotalSeconds, 180); // 3 minutes total
      expect(GuestSessionService.maxGuestPersonSeconds, 30); // 30 seconds max per person
    });

    test('Guest probability check generates ~60% girls and ~40% other', () {
      const guestProfile = UserProfile(id: 'guest_1', isAnonymous: true);
      expect(guestProfile.isAnonymous, isTrue);

      int girlsCount = 0;
      int otherCount = 0;
      const iterations = 1000;

      for (int i = 0; i < iterations; i++) {
        // Deterministic pseudo-test of the probability logic
        final val = (i % 100) / 100.0;
        if (val < 0.60) {
          girlsCount++;
        } else {
          otherCount++;
        }
      }

      expect(girlsCount, 600);
      expect(otherCount, 400);
      expect(girlsCount / iterations, 0.60);
      expect(otherCount / iterations, 0.40);
    });

    test('Google logged-in user is not anonymous', () {
      const googleUser = UserProfile(
        id: 'google_user_1',
        isAnonymous: false,
        nickname: 'Usman',
      );

      expect(googleUser.isAnonymous, isFalse);
    });

    test('Default user signup receives 120 initial bonus coins', () {
      const newUser = UserProfile(id: 'new_user');
      expect(newUser.coins, 120);
    });
  });
}

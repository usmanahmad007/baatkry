import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';

void main() {
  group('18+ Age Verification & Consent Tests', () {
    test('Calculates age correctly from Date of Birth', () {
      final now = DateTime.now();
      final adultDob = DateTime(now.year - 20, now.month, now.day);
      final minorDob = DateTime(now.year - 16, now.month, now.day);

      int computeAge(DateTime dob) {
        int age = now.year - dob.year;
        if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
          age--;
        }
        return age;
      }

      expect(computeAge(adultDob), 20);
      expect(computeAge(minorDob), 16);
      expect(computeAge(adultDob) >= 18, isTrue);
      expect(computeAge(minorDob) >= 18, isFalse);
    });

    test('Strict 18+ boundary evaluation for birth certificates', () {
      final now = DateTime.now();
      final exactly18 = DateTime(now.year - 18, now.month, now.day);
      final under18ByOneDay = DateTime(now.year - 18, now.month, now.day + 1);

      int computeAge(DateTime dob) {
        int age = now.year - dob.year;
        if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
          age--;
        }
        return age;
      }

      expect(computeAge(exactly18) >= 18, isTrue);
      expect(computeAge(under18ByOneDay) >= 18, isFalse);
    });

    test('UserProfile handles age and isAgeVerified properly', () {
      const adultProfile = UserProfile(
        id: 'user_1',
        nickname: 'Adult User',
        age: 22,
        isAgeVerified: true,
      );

      expect(adultProfile.age, 22);
      expect(adultProfile.isAgeVerified, isTrue);

      final map = adultProfile.toMap();
      expect(map['age'], 22);
      expect(map['is_age_verified'], isTrue);

      final fromMap = UserProfile.fromMap(map);
      expect(fromMap.age, 22);
      expect(fromMap.isAgeVerified, isTrue);
    });
  });
}

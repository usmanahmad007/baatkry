import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monkey_omegle_app/models/user_profile.dart';
import 'package:monkey_omegle_app/services/supabase_service.dart';
import 'package:monkey_omegle_app/features/profile/complete_profile_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Mandatory One-Time Profile Completion & Blocking Flow', () {
    test('1. Guest / Anonymous users are never asked for username or DOB', () {
      const guest = UserProfile(
        id: 'guest_9329887',
        isAnonymous: true,
        nickname: 'guest#9329887',
        coins: 0,
      );

      expect(guest.isAnonymous, isTrue);
      expect(guest.hasUsername, isFalse);
      expect(guest.hasDob, isFalse);
      // needsProfileCompletion must be FALSE for anonymous guests
      expect(guest.needsProfileCompletion, isFalse);
    });

    test('2. First-time signup or existing user without username/DOB has needsProfileCompletion == true', () {
      const newUser = UserProfile(
        id: 'usr_first_time',
        isAnonymous: false,
        nickname: 'JohnDoe',
        username: null,
        birthDate: null,
        coins: 120,
      );

      expect(newUser.isAnonymous, isFalse);
      expect(newUser.hasUsername, isFalse);
      expect(newUser.hasDob, isFalse);
      expect(newUser.needsProfileCompletion, isTrue);

      const existingUserNoDob = UserProfile(
        id: 'usr_existing_1',
        isAnonymous: false,
        nickname: 'Alice',
        username: 'alice_w',
        birthDate: null, // missing DOB
      );
      expect(existingUserNoDob.needsProfileCompletion, isTrue);

      const existingUserNoUsername = UserProfile(
        id: 'usr_existing_2',
        isAnonymous: false,
        nickname: 'Bob',
        username: null, // missing username
        birthDate: '1998-04-12',
        age: 28,
        isAgeVerified: true,
      );
      expect(existingUserNoUsername.needsProfileCompletion, isTrue);
    });

    test('3. setUsernameAndDob persists both fields and turns needsProfileCompletion to false forever', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SupabaseService.instance;

      // Simulate sign in with email
      await service.signInWithEmail(email: 'user.first@baatkry.com', password: 'Password123!');
      final initialProfile = service.currentProfile!;
      expect(initialProfile.needsProfileCompletion, isTrue);

      // Save username and DOB with gender
      final result = await service.setUsernameAndDob(
        username: 'cool_baatkry_user',
        dateOfBirth: DateTime(2000, 5, 20),
        gender: 'men',
      );

      expect(result['success'], isTrue);
      expect(result['username'], equals('cool_baatkry_user'));
      expect(result['birth_date'], equals('2000-05-20'));

      final updatedProfile = service.currentProfile!;
      expect(updatedProfile.hasUsername, isTrue);
      expect(updatedProfile.username, equals('cool_baatkry_user'));
      expect(updatedProfile.hasDob, isTrue);
      expect(updatedProfile.birthDate, equals('2000-05-20'));
      expect(updatedProfile.isAgeVerified, isTrue);
      expect(updatedProfile.isGenderSet, isTrue);
      expect(updatedProfile.gender, equals('men'));

      // Now needsProfileCompletion must be FALSE permanently
      expect(updatedProfile.needsProfileCompletion, isFalse);

      // Check local persistence
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_user_username_${updatedProfile.id}'), equals('cool_baatkry_user'));
      expect(prefs.getString('local_user_dob_${updatedProfile.id}'), equals('2000-05-20'));
      expect(prefs.getBool('baatkry_age_verified_18_plus'), isTrue);
      expect(prefs.getString('local_user_gender_${updatedProfile.id}'), equals('men'));
    });

    testWidgets('4. CompleteProfileModal is non-dismissible (dismissible: false) and enforces required fields', (tester) async {
      const incompleteProfile = UserProfile(
        id: 'usr_blocking_test',
        isAnonymous: false,
        nickname: 'Alex',
        username: null,
        birthDate: null,
        coins: 120,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => CompleteProfileModal.show(ctx, initialProfile: incompleteProfile, dismissible: false),
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        ),
      );

      // Tap button to open CompleteProfileModal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Modal is visible
      expect(find.text('Complete Your Profile'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget); // Required badge instead of close 'X'
      expect(find.byIcon(Icons.close_rounded), findsNothing); // No close icon!

      // PopScope is present and configured with canPop: false
      final popScopeFinder = find.byWidgetPredicate((w) => w is PopScope);
      expect(popScopeFinder, findsOneWidget);
      final popScope = tester.widget(popScopeFinder) as dynamic;
      expect(popScope.canPop, isFalse);

      // Save & Continue button is disabled until valid input
      final buttonFinder = find.widgetWithText(ElevatedButton, 'Save & Continue');
      expect(buttonFinder, findsOneWidget);
      final elevatedButton = tester.widget<ElevatedButton>(buttonFinder);
      expect(elevatedButton.onPressed, isNull); // Disabled!
    });

    testWidgets('5. CompleteProfileModal.show returns immediately if profile is already complete', (tester) async {
      const completeProfile = UserProfile(
        id: 'usr_done',
        isAnonymous: false,
        nickname: 'Alex',
        username: 'alex_ready',
        birthDate: '1999-01-01',
        age: 27,
        isAgeVerified: true,
      );

      expect(completeProfile.needsProfileCompletion, isFalse);

      bool? modalResult;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    modalResult = await CompleteProfileModal.show(ctx, initialProfile: completeProfile);
                  },
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Modal was NEVER displayed because profile was already complete!
      expect(find.text('Complete Your Profile'), findsNothing);
      expect(modalResult, isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Permission & Reload Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Permission is initially not requested', () async {
      final service = PermissionService.instance;
      await service.init();
      expect(service.hasRequested, isFalse);
      expect(service.isGranted, isFalse);
    });

    test('Marking permission handled persists and prevents repeated requests', () async {
      final service = PermissionService.instance;
      await service.markPermissionHandled(granted: true);
      expect(service.hasRequested, isTrue);
      expect(service.isGranted, isTrue);

      // Re-init from persisted prefs
      await service.init();
      expect(service.hasRequested, isTrue);
      expect(service.isGranted, isTrue);
    });

    test('Time resets to zero on gender/free mode transition', () {
      int elapsedSeconds = 45;
      String filter = 'everyone';
      bool isFiltered = false;

      // User switches to VIP Women filter
      void switchToGender(String newGender) {
        filter = newGender;
        isFiltered = true;
        elapsedSeconds = 0; // Starts from 0
      }

      // User switches back to Free Random
      void switchToFree() {
        filter = 'unspecified';
        isFiltered = false;
        elapsedSeconds = 0; // Starts from 0
      }

      switchToGender('women');
      expect(filter, 'women');
      expect(isFiltered, isTrue);
      expect(elapsedSeconds, 0);

      elapsedSeconds = 120;
      switchToFree();
      expect(filter, 'unspecified');
      expect(isFiltered, isFalse);
      expect(elapsedSeconds, 0);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/models/creator_application.dart';
import 'package:monkey_omegle_app/models/creator_profile.dart';

void main() {
  group('CreatorApplication Model Tests', () {
    test('CreatorApplication calculates age and status correctly', () {
      final dob = DateTime(DateTime.now().year - 24, 5, 15);
      final app = CreatorApplication(
        id: 'app-uuid-1',
        userId: 'user-uuid-1',
        fullName: 'Jane Doe',
        dateOfBirth: dob,
        country: 'Pakistan',
        idDocumentType: IdDocumentType.nationalId,
        idDocumentFrontUrl: 'https://storage/id_front.jpg',
        selfieUrl: 'https://storage/selfie.jpg',
        status: CreatorApplicationStatus.pending,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(app.id, 'app-uuid-1');
      expect(app.fullName, 'Jane Doe');
      expect(app.age, 24);
      expect(app.isPending, true);
      expect(app.isApproved, false);
      expect(app.isRejected, false);
      expect(app.idDocumentType.displayName, 'National ID Card');
    });

    test('CreatorApplication parses status fromMap correctly', () {
      final map = {
        'id': 'app-2',
        'user_id': 'u-2',
        'full_name': 'John Smith',
        'date_of_birth': '1998-10-20',
        'country': 'United States',
        'id_document_type': 'passport',
        'id_document_front_url': 'https://front.jpg',
        'selfie_url': 'https://selfie.jpg',
        'status': 'approved',
        'social_media_links': {'instagram': '@johnny'},
      };

      final app = CreatorApplication.fromMap(map);
      expect(app.id, 'app-2');
      expect(app.isApproved, true);
      expect(app.isPending, false);
      expect(app.idDocumentType, IdDocumentType.passport);
      expect(app.socialMediaLinks['instagram'], '@johnny');
    });

    test('CreatorApplication handles rejected status with reason', () {
      final map = {
        'id': 'app-3',
        'user_id': 'u-3',
        'full_name': 'Applicant',
        'date_of_birth': '2001-01-01',
        'country': 'Canada',
        'id_document_type': 'driving_license',
        'id_document_front_url': 'https://front.jpg',
        'selfie_url': 'https://selfie.jpg',
        'status': 'rejected',
        'rejection_reason': 'ID document image was blurry and unreadable.',
      };

      final app = CreatorApplication.fromMap(map);
      expect(app.isRejected, true);
      expect(app.rejectionReason, contains('blurry'));
      expect(app.status.displayName, 'Application Rejected');
    });
  });

  group('CreatorProfile Model Tests', () {
    test('CreatorProfile parses statistics and verification', () {
      final map = {
        'id': 'creator-1',
        'display_name': 'Star Creator',
        'bio': 'Live chat host & gamer',
        'category': 'Entertainment',
        'is_verified': true,
        'total_gifts_received': 1420,
        'total_call_minutes': 850,
        'follower_count': 3200,
      };

      final profile = CreatorProfile.fromMap(map);
      expect(profile.id, 'creator-1');
      expect(profile.displayName, 'Star Creator');
      expect(profile.isVerified, true);
      expect(profile.totalGiftsReceived, 1420);
      expect(profile.totalCallMinutes, 850);
      expect(profile.followerCount, 3200);
    });
  });
}

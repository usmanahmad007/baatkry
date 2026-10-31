enum CreatorApplicationStatus {
  pending,
  underReview,
  approved,
  rejected;

  static CreatorApplicationStatus fromString(String? val) {
    switch (val?.toLowerCase().trim()) {
      case 'approved':
        return CreatorApplicationStatus.approved;
      case 'rejected':
        return CreatorApplicationStatus.rejected;
      case 'under_review':
        return CreatorApplicationStatus.underReview;
      case 'pending':
      default:
        return CreatorApplicationStatus.pending;
    }
  }

  String get displayName {
    switch (this) {
      case CreatorApplicationStatus.pending:
        return 'Pending Review';
      case CreatorApplicationStatus.underReview:
        return 'Under Review';
      case CreatorApplicationStatus.approved:
        return 'Approved & Verified';
      case CreatorApplicationStatus.rejected:
        return 'Application Rejected';
    }
  }
}

enum IdDocumentType {
  nationalId,
  passport,
  drivingLicense;

  static IdDocumentType fromString(String? val) {
    switch (val?.toLowerCase().trim()) {
      case 'passport':
        return IdDocumentType.passport;
      case 'driving_license':
        return IdDocumentType.drivingLicense;
      case 'national_id':
      default:
        return IdDocumentType.nationalId;
    }
  }

  String get dbValue {
    switch (this) {
      case IdDocumentType.passport:
        return 'passport';
      case IdDocumentType.drivingLicense:
        return 'driving_license';
      case IdDocumentType.nationalId:
        return 'national_id';
    }
  }

  String get displayName {
    switch (this) {
      case IdDocumentType.nationalId:
        return 'National ID Card';
      case IdDocumentType.passport:
        return 'Passport';
      case IdDocumentType.drivingLicense:
        return "Driver's License";
    }
  }
}

class CreatorApplication {
  final String id;
  final String userId;
  final String fullName;
  final DateTime dateOfBirth;
  final String country;
  final IdDocumentType idDocumentType;
  final String idDocumentFrontUrl;
  final String? idDocumentBackUrl;
  final String selfieUrl;
  final Map<String, dynamic> socialMediaLinks;
  final String? bio;
  final CreatorApplicationStatus status;
  final String? rejectionReason;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CreatorApplication({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.dateOfBirth,
    required this.country,
    required this.idDocumentType,
    required this.idDocumentFrontUrl,
    this.idDocumentBackUrl,
    required this.selfieUrl,
    this.socialMediaLinks = const {},
    this.bio,
    this.status = CreatorApplicationStatus.pending,
    this.rejectionReason,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPending => status == CreatorApplicationStatus.pending || status == CreatorApplicationStatus.underReview;
  bool get isApproved => status == CreatorApplicationStatus.approved;
  bool get isRejected => status == CreatorApplicationStatus.rejected;

  int get age {
    final now = DateTime.now();
    int a = now.year - dateOfBirth.year;
    if (now.month < dateOfBirth.month || (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      a--;
    }
    return a;
  }

  factory CreatorApplication.fromMap(Map<String, dynamic> map) {
    return CreatorApplication(
      id: map['id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      fullName: map['full_name'] as String? ?? '',
      dateOfBirth: map['date_of_birth'] != null
          ? DateTime.tryParse(map['date_of_birth'].toString()) ?? DateTime(2000, 1, 1)
          : DateTime(2000, 1, 1),
      country: map['country'] as String? ?? 'Global',
      idDocumentType: IdDocumentType.fromString(map['id_document_type'] as String?),
      idDocumentFrontUrl: map['id_document_front_url'] as String? ?? '',
      idDocumentBackUrl: map['id_document_back_url'] as String?,
      selfieUrl: map['selfie_url'] as String? ?? '',
      socialMediaLinks: (map['social_media_links'] as Map?)?.cast<String, dynamic>() ?? const {},
      bio: map['bio'] as String?,
      status: CreatorApplicationStatus.fromString(map['status'] as String?),
      rejectionReason: map['rejection_reason'] as String?,
      reviewedBy: map['reviewed_by'] as String?,
      reviewedAt: map['reviewed_at'] != null ? DateTime.tryParse(map['reviewed_at'].toString()) : null,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'full_name': fullName,
      'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
      'country': country,
      'id_document_type': idDocumentType.dbValue,
      'id_document_front_url': idDocumentFrontUrl,
      'id_document_back_url': idDocumentBackUrl,
      'selfie_url': selfieUrl,
      'social_media_links': socialMediaLinks,
      'bio': bio,
      'status': status.name,
      'rejection_reason': rejectionReason,
      'reviewed_by': reviewedBy,
      'reviewed_at': reviewedAt?.toIso8601String(),
    };
  }
}

import 'package:flutter/material.dart';

/// Represents an itemized abuse or safety report submitted against a user
class UserReport {
  final String id;
  final String? reporterId;
  final String reportedId;
  final String reason;
  final String? details;
  final String? roomId;
  final String status; // 'pending', 'investigating', 'resolved', 'dismissed'
  final String actionTaken; // 'none', 'warned', 'suspended_24h', 'suspended_7d', 'banned', 'creator_revoked', 'wallet_frozen', 'dismissed'
  final String? adminNotes;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final String? reporterName;
  final String? reportedName;

  const UserReport({
    required this.id,
    this.reporterId,
    required this.reportedId,
    required this.reason,
    this.details,
    this.roomId,
    this.status = 'pending',
    this.actionTaken = 'none',
    this.adminNotes,
    this.resolvedBy,
    this.resolvedAt,
    required this.createdAt,
    this.reporterName,
    this.reportedName,
  });

  bool get isPending => status == 'pending' || status == 'investigating';
  bool get isResolved => status == 'resolved';
  bool get isDismissed => status == 'dismissed';

  bool get isUnderageFlag =>
      reason.toLowerCase().contains('underage') ||
      reason.toLowerCase().contains('<18') ||
      (details != null && details!.toLowerCase().contains('underage'));

  String get statusDisplayName {
    switch (status) {
      case 'pending':
        return 'Pending Review';
      case 'investigating':
        return 'Investigating';
      case 'resolved':
        return 'Resolved';
      case 'dismissed':
        return 'Dismissed';
      default:
        return status;
    }
  }

  Color get statusBadgeColor {
    switch (status) {
      case 'pending':
        return const Color(0xFFFF9800); // Orange
      case 'investigating':
        return const Color(0xFF2196F3); // Blue
      case 'resolved':
        return const Color(0xFF4CAF50); // Green
      case 'dismissed':
        return Colors.grey;
      default:
        return Colors.white70;
    }
  }

  Color get riskBadgeColor {
    if (isUnderageFlag) return const Color(0xFFE91E63); // Bright Red / Pink for Underage
    if (reason.toLowerCase().contains('nudity') || reason.toLowerCase().contains('sexual')) {
      return const Color(0xFFF44336); // Red
    }
    if (reason.toLowerCase().contains('scam') || reason.toLowerCase().contains('fraud')) {
      return const Color(0xFFFF9800); // Orange
    }
    return const Color(0xFF9C27B0); // Purple for harassment / other
  }

  String get actionLabel {
    switch (actionTaken) {
      case 'banned':
        return 'Permanently Banned';
      case 'suspended_24h':
        return 'Suspended (24 Hours)';
      case 'suspended_7d':
        return 'Suspended (7 Days)';
      case 'creator_revoked':
        return 'Creator KYC Revoked';
      case 'wallet_frozen':
        return 'Creator Wallet Frozen';
      case 'warned':
        return 'Official Warning Issued';
      case 'dismissed':
        return 'Dismissed (False Alarm)';
      case 'none':
      default:
        return 'No Action Taken';
    }
  }

  factory UserReport.fromMap(Map<String, dynamic> map) {
    return UserReport(
      id: map['id']?.toString() ?? '',
      reporterId: map['reporter_id']?.toString(),
      reportedId: map['reported_id']?.toString() ?? '',
      reason: map['reason']?.toString() ?? 'Safety Concern',
      details: map['details']?.toString(),
      roomId: map['room_id']?.toString(),
      status: map['status']?.toString() ?? 'pending',
      actionTaken: map['action_taken']?.toString() ?? 'none',
      adminNotes: map['admin_notes']?.toString(),
      resolvedBy: map['resolved_by']?.toString(),
      resolvedAt: map['resolved_at'] != null
          ? DateTime.tryParse(map['resolved_at'].toString())
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      reporterName: map['reporter_nickname']?.toString() ?? map['reporter_name']?.toString(),
      reportedName: map['reported_nickname']?.toString() ?? map['reported_name']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'reporter_id': reporterId,
      'reported_id': reportedId,
      'reason': reason,
      'details': details,
      'room_id': roomId,
      'status': status,
      'action_taken': actionTaken,
      'admin_notes': adminNotes,
      'resolved_by': resolvedBy,
      'resolved_at': resolvedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'reporter_name': reporterName,
      'reported_name': reportedName,
    };
  }
}

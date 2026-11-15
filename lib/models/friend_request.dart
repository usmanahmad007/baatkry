class FriendRequest {
  final String id;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final bool senderIsVip;
  final String receiverId;
  final String receiverName;
  final String? receiverAvatar;
  final String status; // 'pending', 'accepted', 'declined'
  final DateTime createdAt;
  final DateTime? updatedAt;

  const FriendRequest({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    this.senderIsVip = false,
    required this.receiverId,
    required this.receiverName,
    this.receiverAvatar,
    this.status = 'pending',
    required this.createdAt,
    this.updatedAt,
  });

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDeclined => status == 'declined';

  FriendRequest copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? senderAvatar,
    bool? senderIsVip,
    String? receiverId,
    String? receiverName,
    String? receiverAvatar,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FriendRequest(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      senderIsVip: senderIsVip ?? this.senderIsVip,
      receiverId: receiverId ?? this.receiverId,
      receiverName: receiverName ?? this.receiverName,
      receiverAvatar: receiverAvatar ?? this.receiverAvatar,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_avatar': senderAvatar,
      'sender_is_vip': senderIsVip,
      'receiver_id': receiverId,
      'receiver_name': receiverName,
      'receiver_avatar': receiverAvatar,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory FriendRequest.fromMap(Map<String, dynamic> map) {
    return FriendRequest(
      id: map['id']?.toString() ?? '',
      senderId: map['sender_id']?.toString() ?? '',
      senderName: map['sender_name']?.toString() ?? 'Stranger',
      senderAvatar: map['sender_avatar']?.toString(),
      senderIsVip: map['sender_is_vip'] == true,
      receiverId: map['receiver_id']?.toString() ?? '',
      receiverName: map['receiver_name']?.toString() ?? 'User',
      receiverAvatar: map['receiver_avatar']?.toString(),
      status: map['status']?.toString() ?? 'pending',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }
}

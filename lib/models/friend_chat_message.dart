class FriendChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String receiverId;
  final String text;
  final bool isGift;
  final String? giftName;
  final String? giftEmoji;
  final int? giftCoins;
  final DateTime createdAt;

  const FriendChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.receiverId,
    required this.text,
    this.isGift = false,
    this.giftName,
    this.giftEmoji,
    this.giftCoins,
    required this.createdAt,
  });

  bool isSentBy(String userId) => senderId == userId;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'sender_id': senderId,
      'sender_name': senderName,
      'receiver_id': receiverId,
      'text': text,
      'is_gift': isGift,
      'gift_name': giftName,
      'gift_emoji': giftEmoji,
      'gift_coins': giftCoins,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory FriendChatMessage.fromMap(Map<String, dynamic> map) {
    return FriendChatMessage(
      id: map['id']?.toString() ?? '',
      chatId: map['chat_id']?.toString() ?? '',
      senderId: map['sender_id']?.toString() ?? '',
      senderName: map['sender_name']?.toString() ?? 'User',
      receiverId: map['receiver_id']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      isGift: map['is_gift'] == true,
      giftName: map['gift_name']?.toString(),
      giftEmoji: map['gift_emoji']?.toString(),
      giftCoins: (map['gift_coins'] as num?)?.toInt(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  static String computeChatId(String userA, String userB) {
    final list = [userA, userB]..sort();
    return 'chat_${list[0]}_${list[1]}';
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/vip_avatar.dart';
import '../../models/friend_chat_message.dart';
import '../../models/user_profile.dart';
import '../../models/virtual_gift.dart';
import '../../services/matchmaking_service.dart';
import '../../services/supabase_service.dart';
import '../call/video_call_screen.dart';
import '../shop/shop_modal.dart';

class FriendChatScreen extends ConsumerStatefulWidget {
  final UserProfile friend;

  const FriendChatScreen({super.key, required this.friend});

  @override
  ConsumerState<FriendChatScreen> createState() => _FriendChatScreenState();
}

class _FriendChatScreenState extends ConsumerState<FriendChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<List<FriendChatMessage>>? _chatSub;
  List<FriendChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _chatSub = SupabaseService.instance
        .getFriendChatStream(widget.friend.id)
        .listen((updated) {
      if (mounted) {
        setState(() => _messages = updated);
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final msgs = await SupabaseService.instance.fetchFriendChatMessages(widget.friend.id);
      if (mounted) {
        setState(() {
          _messages = msgs;
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    // Check administrative moderation status
    final mod = await SupabaseService.instance.checkAccountModerationStatus();
    if (mod['isBanned'] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Account suspended by admin: ${mod['banReason'] ?? 'Community guidelines violation'}'),
          ),
        );
      }
      return;
    }
    if (mod['isRestricted'] == true) {
      final rType = mod['restrictionType']?.toString() ?? '';
      if (rType == 'chat_mute' || rType.contains('mute') || rType.contains('restrict')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.orange.shade800,
              content: Text('Chat restricted by admin (${mod['restrictionType']}): ${mod['restrictionReason'] ?? 'Administrative moderation action'}'),
            ),
          );
        }
        return;
      }
    }

    _textController.clear();
    setState(() => _isSending = true);

    try {
      final msg = await SupabaseService.instance.sendFriendChatMessage(
        friendId: widget.friend.id,
        text: text,
      );

      if (mounted) {
        setState(() {
          _messages.add(msg);
          _isSending = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Failed to send: $e'),
          ),
        );
      }
    }
  }

  void _showGiftPickerModal() {
    const gifts = VirtualGift.defaultGifts;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDark ? Colors.white : Colors.black87;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (modalCtx) => Consumer(
        builder: (ctx, refWatch, _) {
          final myCoins = refWatch.watch(userCoinsProvider);

          return Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: AppColors.border(context), width: 1.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Title & My Balance
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text('🎁', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        Text(
                          'Send Gift to ${widget.friend.nickname}',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.coinGold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '$myCoins',
                            style: const TextStyle(
                              color: AppColors.coinGold,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Gifts Grid
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: gifts.length,
                    itemBuilder: (context, index) {
                      final gift = gifts[index];
                      final canAfford = myCoins >= gift.coinPrice;

                      return InkWell(
                        onTap: () async {
                          if (!canAfford) {
                            Navigator.of(modalCtx).pop();
                            ShopModal.show(context);
                            return;
                          }

                          Navigator.of(modalCtx).pop();
                          await _executeSendGift(gift);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: canAfford ? AppColors.coinGold.withOpacity(0.4) : (isDark ? Colors.white10 : Colors.black12),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(gift.emoji, style: const TextStyle(fontSize: 32)),
                              const SizedBox(height: 6),
                              Text(
                                gift.name,
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.monetization_on_rounded, size: 12, color: AppColors.coinGold),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${gift.coinPrice}',
                                    style: TextStyle(
                                      color: canAfford ? AppColors.coinGold : AppColors.textMuted,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _executeSendGift(VirtualGift gift) async {
    final myProfile = SupabaseService.instance.currentProfile;
    final myId = myProfile?.id ?? 'me';
    final myName = myProfile?.nickname ?? 'Friend';

    try {
      // 1. Send virtual gift (deduct sender coins, credit receiver, 70% cash earnings if creator)
      await SupabaseService.instance.sendVirtualGift(
        gift: gift,
        receiverId: widget.friend.id,
        receiverName: widget.friend.nickname,
        roomId: 'friend_chat_${widget.friend.id}',
      );

      // 2. Credit incoming coins immediately to friend account
      await SupabaseService.instance.creditReceivedGiftCoins(
        coins: gift.coinPrice,
        senderId: myId,
        senderName: myName,
        giftName: gift.name,
      );

      // 3. Post gift message into the 1-on-1 text conversation
      final msg = await SupabaseService.instance.sendFriendChatMessage(
        friendId: widget.friend.id,
        text: 'Sent ${gift.name} 🎁',
        isGift: true,
        giftName: gift.name,
        giftEmoji: gift.emoji,
        giftCoins: gift.coinPrice,
      );

      ref.invalidate(userCoinsProvider);
      ref.invalidate(userProfileProvider);

      if (mounted) {
        setState(() {
          _messages.add(msg);
        });
        _scrollToBottom();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.brandPink,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                Text(gift.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text('Sent ${gift.name} (${gift.coinPrice} coins) to ${widget.friend.nickname}!'),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Failed to send gift: $e'),
          ),
        );
      }
    }
  }

  void _startVideoCall() {
    final myProfile = SupabaseService.instance.currentProfile ??
        const UserProfile(id: 'me', nickname: 'Me');
    final myId = myProfile.id;
    final sortedIds = [myId, widget.friend.id]..sort();
    final roomId = 'friend_call_${sortedIds.join('_')}';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          matchResult: MatchResult(
            roomId: roomId,
            token: 'friend_call_token_${DateTime.now().millisecondsSinceEpoch}',
            peerId: widget.friend.id,
            peerName: widget.friend.nickname,
            peerGender: widget.friend.gender,
            peerCountry: widget.friend.country,
            peerCountryFlag: '🌍',
          ),
          myProfile: myProfile,
        ),
      ),
    );
  }

  Future<void> _confirmUnfollow() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Unfollow ${widget.friend.displayUsername}?',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        content: Text(
          'They will no longer appear in your friends list.',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Unfollow'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SupabaseService.instance.unfollowUser(widget.friend.id);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.brandIndigo,
            content: Text('Unfollowed ${widget.friend.nickname}.'),
          ),
        );
      }
    }
  }

  Future<void> _confirmBlock() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Block ${widget.friend.displayUsername}?',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        content: Text(
          'They will not be able to find your profile, call you, or send you messages on Baatkry.',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SupabaseService.instance.blockUser(widget.friend.id, 'Blocked from text chat');
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('${widget.friend.nickname} has been blocked.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final cardBg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDark ? Colors.white : Colors.black87;
    final myId = SupabaseService.instance.currentProfile?.id ?? '';

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            VipAvatar(
              radius: 18,
              nickname: widget.friend.nickname,
              avatarUrl: widget.friend.avatarUrl,
              isVip: widget.friend.isVip,
              showVipBadge: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.friend.nickname,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.friend.isVip) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded, color: AppColors.coinGold, size: 15),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        widget.friend.displayUsername,
                        style: const TextStyle(
                          color: AppColors.brandPink,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.circle, color: AppColors.success, size: 6),
                      const SizedBox(width: 4),
                      Text(
                        'Online',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_rounded, color: AppColors.brandPink, size: 24),
            tooltip: 'Direct Video Call',
            onPressed: _startVideoCall,
          ),
          IconButton(
            icon: const Icon(Icons.card_giftcard_rounded, color: AppColors.coinGold, size: 22),
            tooltip: 'Send Gift',
            onPressed: _showGiftPickerModal,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: textColor, size: 20),
            color: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (val) {
              if (val == 'unfollow') {
                _confirmUnfollow();
              } else if (val == 'block') {
                _confirmBlock();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'unfollow',
                child: Row(
                  children: [
                    Icon(Icons.person_remove_rounded, color: AppColors.danger, size: 18),
                    SizedBox(width: 10),
                    Text('Unfollow', style: TextStyle(fontSize: 13, color: AppColors.danger, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block_rounded, color: AppColors.danger, size: 18),
                    SizedBox(width: 10),
                    Text('Block User', style: TextStyle(fontSize: 13, color: AppColors.danger, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Message List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brandPink))
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.brandPink.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Text('💬', style: TextStyle(fontSize: 36)),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Say hello to ${widget.friend.nickname}!',
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Send text messages and virtual gifts.',
                              style: TextStyle(
                                color: isDark ? Colors.white60 : Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg.isSentBy(myId);

                          if (msg.isGift) {
                            return _buildGiftMessageBubble(msg, isMe, isDark, cardBg);
                          }
                          return _buildTextMessageBubble(msg, isMe, isDark, textColor);
                        },
                      ),
          ),

          // Bottom Action Bar (Gift Button + Text Input + Send Button)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            decoration: BoxDecoration(
              color: cardBg,
              border: Border(
                top: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // Gift Button 🎁
                  InkWell(
                    onTap: _showGiftPickerModal,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: AppColors.vipGoldGradient,
                        borderRadius: BorderRadius.circular(21),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.coinGold.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('🎁', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Text Field
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                      ),
                      child: TextField(
                        controller: _textController,
                        onSubmitted: (_) => _handleSendMessage(),
                        style: TextStyle(color: textColor, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Send Button
                  InkWell(
                    onTap: _handleSendMessage,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child: const Center(
                        child: Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextMessageBubble(
    FriendChatMessage msg,
    bool isMe,
    bool isDark,
    Color textColor,
  ) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isMe ? AppColors.primaryGradient : null,
          color: isMe ? null : (isDark ? AppColors.darkSurface : AppColors.lightSurface),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: isMe ? null : Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: TextStyle(
                color: isMe ? Colors.white : textColor,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                color: isMe ? Colors.white70 : (isDark ? Colors.white38 : Colors.black38),
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGiftMessageBubble(
    FriendChatMessage msg,
    bool isMe,
    bool isDark,
    Color cardBg,
  ) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF261D10) : const Color(0xFFFFF9E6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.coinGold.withOpacity(0.6), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.coinGold.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.coinGold.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Text(msg.giftEmoji ?? '🎁', style: const TextStyle(fontSize: 28)),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isMe ? 'You sent ${msg.giftName ?? "Gift"}' : '${msg.senderName} sent ${msg.giftName ?? "Gift"}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.coinGold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        '+${msg.giftCoins ?? 0} Coins Transferred',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Creator received 70% cash earnings',
                    style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

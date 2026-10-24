import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../../core/theme/app_theme.dart';
import '../../models/chat_message.dart';
import '../../models/user_profile.dart';
import '../../services/livekit_service.dart';
import '../../services/matchmaking_service.dart';
import '../../services/supabase_service.dart';
import '../matchmaking/radar_screen.dart';
import '../moderation/eula_modal.dart';
import '../moderation/report_modal.dart';
import '../shop/shop_modal.dart';

class VideoCallScreen extends StatefulWidget {
  final MatchResult matchResult;
  final UserProfile myProfile;

  const VideoCallScreen({
    super.key,
    required this.matchResult,
    required this.myProfile,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final LiveKitService _liveKit = LiveKitService.instance;
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  StreamSubscription<VideoTrack?>? _remoteTrackSub;
  StreamSubscription<ChatMessage>? _chatSub;
  StreamSubscription<void>? _peerDisconnectedSub;

  VideoTrack? _remoteVideoTrack;
  LocalVideoTrack? _localVideoTrack;

  // Unlimited Call Timer & Gender Coin Deduction (1 Coin = 1 Second)
  int _callElapsedSeconds = 0;
  late int _coinsRemaining;
  Timer? _callTimer;
  bool _isLiked = false;
  bool _isTheaterMode = false;
  bool _showMobileChat = false;

  bool get _isGenderFiltered => widget.matchResult.peerGender != 'unspecified';

  @override
  void initState() {
    super.initState();
    _coinsRemaining = widget.myProfile.coins;
    _initCall();
    _startCallTimer();
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _callElapsedSeconds++;

        // If user is filtering by gender, deduct 1 coin per second
        if (_isGenderFiltered) {
          if (_coinsRemaining > 0) {
            _coinsRemaining--;
            if (_coinsRemaining % 10 == 0 || _coinsRemaining == 0) {
              SupabaseService.instance.deductCoins(10);
            }
          } else {
            _onGenderCoinsExhausted();
          }
        }
      });
    });
  }

  void _onGenderCoinsExhausted() {
    _callTimer?.cancel();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.coinGold, width: 1.5),
        ),
        title: const Text('Coins Finished 🪙', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Your coins for filtering by ${widget.matchResult.peerGender} have ended (1 coin = 1 second).\n\nRecharge (min 500 Rs for 25 mins) to continue with gender filtering (20 Rs = 1 min), or enjoy free unlimited random chat!',
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // Continue in free unlimited chat
              _startCallTimer();
            },
            child: const Text('Free Unlimited', style: TextStyle(color: Colors.white70)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.vipGoldGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                ShopModal.show(context);
              },
              child: const Text('Recharge (500 Rs)', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _initCall() async {
    _remoteTrackSub = _liveKit.remoteTrackStream.listen((track) {
      if (mounted) setState(() => _remoteVideoTrack = track);
    });

    _chatSub = _liveKit.chatMessageStream.listen((msg) {
      if (mounted) {
        setState(() => _messages.add(msg));
        _scrollChatToBottom();
      }
    });

    _peerDisconnectedSub = _liveKit.peerDisconnectedStream.listen((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User skipped. Finding next match...')),
        );
        _onSkipToNext();
      }
    });

    try {
      await _liveKit.connect(
        roomName: widget.matchResult.roomId,
        token: widget.matchResult.token,
      );

      final localPub = _liveKit.room?.localParticipant?.videoTrackPublications.firstOrNull;
      if (localPub?.track != null) {
        setState(() => _localVideoTrack = localPub!.track);
      } else {
        final track = await _liveKit.startLocalPreview();
        if (mounted) setState(() => _localVideoTrack = track);
      }
    } catch (e) {
      debugPrint('[VideoCallScreen] Connection error: $e');
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _remoteTrackSub?.cancel();
    _chatSub?.cancel();
    _peerDisconnectedSub?.cancel();
    _liveKit.disconnect();
    _textController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _onSkipToNext() async {
    await _liveKit.disconnect();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RadarScreen(
          profile: widget.myProfile,
        ),
      ),
    );
  }

  void _onReportUser() {
    ReportModal.show(
      context,
      peerId: widget.matchResult.peerId,
      peerName: widget.matchResult.peerName,
      roomId: widget.matchResult.roomId,
      onReportSubmitted: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.success,
            content: Text('User reported and blocked. Matching next user...'),
          ),
        );
        _onSkipToNext();
      },
    );
  }

  void _sendMessage([String? quickText]) {
    final text = quickText ?? _textController.text.trim();
    if (text.isEmpty) return;

    _liveKit.sendChatMessage(
      text,
      myId: widget.myProfile.id,
      myName: widget.myProfile.nickname,
    );

    if (quickText == null) {
      _textController.clear();
    }
    _scrollChatToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.meshBackgroundGradient,
        ),
        child: Column(
          children: [
            // Top Navigation Bar
            if (!_isTheaterMode) SafeArea(bottom: false, child: _buildTopNavBar()),

            // Main Body: Responsive Desktop Side-by-Side vs Mobile Vertical Split
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 900;

                  if (isDesktop) {
                    // DESKTOP LAYOUT: My Camera (Left) + Stranger's Camera (Center) + Chat (Right)
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Local Camera Card (Left)
                          Expanded(
                            flex: 5,
                            child: _buildMyCameraCard(isMobile: false),
                          ),
                          const SizedBox(width: 14),

                          // 2. Stranger's Camera Card (Center/Right)
                          Expanded(
                            flex: 5,
                            child: _buildStrangerCameraCard(isMobile: false),
                          ),
                          const SizedBox(width: 14),

                          // 3. Chat Sidebar (Right side panel)
                          if (!_isTheaterMode)
                            SizedBox(
                              width: 320,
                              child: _buildChatSidebar(isMobile: false),
                            ),
                        ],
                      ),
                    );
                  } else {
                    // MOBILE LAYOUT: Half screen for one user and half screen for second user (50/50 vertical split)
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Top 50%: Remote Stranger
                              Expanded(
                                child: _buildStrangerCameraCard(isMobile: true),
                              ),
                              const SizedBox(height: 8),

                              // Bottom 50%: My Local Camera
                              Expanded(
                                child: _buildMyCameraCard(isMobile: true),
                              ),
                            ],
                          ),

                          // Floating Mobile Chat Overlay
                          if (_showMobileChat)
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              height: constraints.maxHeight * 0.45,
                              child: _buildChatSidebar(isMobile: true),
                            ),
                        ],
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top Navigation Bar (Modern pills and controls)
  // ---------------------------------------------------------------------------
  Widget _buildTopNavBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left Pills: Safety Lab, Theater Mode, Free Coins
          Row(
            children: [
              _buildNavPill(
                icon: Icons.shield_rounded,
                label: 'Safety Lab',
                onTap: () => EulaModal.checkAndShow(context, onAccepted: () {}),
              ),
              const SizedBox(width: 10),
              _buildNavPill(
                icon: Icons.fullscreen_rounded,
                label: _isTheaterMode ? 'Exit Theater' : 'Theater',
                onTap: () => setState(() => _isTheaterMode = !_isTheaterMode),
              ),
              const SizedBox(width: 10),
              _buildNavPill(
                icon: Icons.monetization_on_rounded,
                label: '${widget.myProfile.coins} Coins',
                accentColor: AppColors.coinGold,
                onTap: () => ShopModal.show(context),
              ),
            ],
          ),

          // Right: Live Duration & Gender Filter Coins
          Row(
            children: [
              // Live Duration Pill (Unlimited!)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: AppColors.darkCardGradient,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.brandIndigo.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      _formatDuration(_callElapsedSeconds),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),

              // If gender-filtered, show remaining coins / seconds (1 coin = 1 second)
              if (_isGenderFiltered) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => ShopModal.show(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: _coinsRemaining < 60 ? null : AppColors.vipGoldGradient,
                      color: _coinsRemaining < 60 ? AppColors.danger : null,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 8, color: Colors.black),
                        const SizedBox(width: 4),
                        Text(
                          '${_coinsRemaining}s (1 coin/s)',
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 10),

              // User Avatar
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.brandIndigo,
                child: Text(
                  widget.myProfile.nickname.isNotEmpty ? widget.myProfile.nickname[0].toUpperCase() : 'U',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? accentColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accentColor != null ? accentColor.withOpacity(0.4) : AppColors.surfaceBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: accentColor ?? Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: accentColor ?? Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card 1: My Camera (Local User)
  // ---------------------------------------------------------------------------
  Widget _buildMyCameraCard({bool isMobile = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.brandIndigo.withOpacity(0.4), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Local Camera Feed
          if (_localVideoTrack != null)
            VideoTrackRenderer(
              _localVideoTrack!,
              fit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              mirrorMode: VideoViewMirrorMode.mirror,
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF14172B), Color(0xFF0F1222)],
                ),
              ),
              child: const Center(
                child: Icon(Icons.videocam_rounded, size: 54, color: Colors.white24),
              ),
            ),

          // Bottom Left: "You" Pill
          Positioned(
            bottom: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.circle, color: AppColors.success, size: 8),
                  SizedBox(width: 6),
                  Text('You (Local)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
          ),

          // Bottom Right: Flip Camera & Mic Controls
          Positioned(
            bottom: 12,
            right: 12,
            child: Row(
              children: [
                _buildCircularControl(
                  icon: _liveKit.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  isAlert: _liveKit.isMicMuted,
                  onTap: () async {
                    await _liveKit.toggleMicrophone();
                    setState(() {});
                  },
                ),
                const SizedBox(width: 8),
                _buildCircularControl(
                  icon: Icons.flip_camera_ios_rounded,
                  onTap: () async {
                    await _liveKit.flipCamera();
                    setState(() {});
                  },
                ),
                if (isMobile) ...[
                  const SizedBox(width: 8),
                  _buildCircularControl(
                    icon: Icons.chat_bubble_outline_rounded,
                    onTap: () => setState(() => _showMobileChat = !_showMobileChat),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card 2: Stranger's Camera (Remote Peer)
  // ---------------------------------------------------------------------------
  Widget _buildStrangerCameraCard({bool isMobile = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.brandPink.withOpacity(0.4), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Remote Peer Video Feed
          if (_remoteVideoTrack != null)
            VideoTrackRenderer(
              _remoteVideoTrack!,
              fit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1D1730), Color(0xFF121424)],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundColor: AppColors.brandIndigo,
                      child: Text(
                        widget.matchResult.peerName.isNotEmpty ? widget.matchResult.peerName[0].toUpperCase() : 'P',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.matchResult.peerName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    const Text('Connecting stranger stream...', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ),

          // Top Left Overlay: Avatar, Name, Location, Heart, Badges
          Positioned(
            top: 14,
            left: 14,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.brandIndigo,
                  child: Text(
                    widget.matchResult.peerName.isNotEmpty ? widget.matchResult.peerName[0].toUpperCase() : 'R',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),

                // Name & Location
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.matchResult.peerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                    ),
                    const Text(
                      'Global • Online',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),

                // Heart Button
                InkWell(
                  onTap: () {
                    setState(() => _isLiked = !_isLiked);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: AppColors.brandPink,
                        content: Text(_isLiked ? 'Added to friends!' : 'Removed from friends.'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      gradient: _isLiked ? AppColors.primaryGradient : null,
                      color: _isLiked ? null : Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Flag / Report Icon
                InkWell(
                  onTap: _onReportUser,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.flag_rounded, color: Colors.white70, size: 16),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Left: baatkry.app pill
          Positioned(
            bottom: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                children: [
                  Text('⚡', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 6),
                  Text(
                    'baatkry.app',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Right: Big Skip/Next Button
          Positioned(
            bottom: 14,
            right: 14,
            child: InkWell(
              onTap: _onSkipToNext,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white30, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandIndigo.withOpacity(0.5),
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.fast_forward_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card 3: Chat Sidebar
  // ---------------------------------------------------------------------------
  Widget _buildChatSidebar({bool isMobile = false}) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.darkCardGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.surfaceBorder, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Top Tab Bar with Avatars
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.surfaceElevated,
              border: Border(bottom: BorderSide(color: AppColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.brandIndigo,
                  child: Text(
                    widget.myProfile.nickname.isNotEmpty ? widget.myProfile.nickname[0].toUpperCase() : 'Y',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),

                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.brandPink,
                  child: Text(
                    widget.matchResult.peerName.isNotEmpty ? widget.matchResult.peerName[0].toUpperCase() : 'R',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const Spacer(),

                if (isMobile)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                    onPressed: () => setState(() => _showMobileChat = false),
                  ),
              ],
            ),
          ),

          // Message Thread List
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded, color: Colors.white.withOpacity(0.3), size: 36),
                          const SizedBox(height: 8),
                          Text(
                            'Say hi to ${widget.matchResult.peerName}!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _chatScrollController,
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return Align(
                        alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            gradient: msg.isMe ? AppColors.primaryGradient : null,
                            color: msg.isMe ? null : AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            msg.text,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Quick Emoji Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                for (final emoji in ['👋', '🔥', '😂', '❤️', '👍'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: InkWell(
                      onTap: () => _sendMessage(emoji),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Text(emoji, style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom Input Bar: "Send Message", Emoji, Gift
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.backgroundElevated,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Send Message',
                      hintStyle: TextStyle(color: Colors.white54, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),

                // Emoji Button (😍)
                InkWell(
                  onTap: () => _sendMessage('😍'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('😍', style: TextStyle(fontSize: 18)),
                  ),
                ),

                // Gift / Coin Button (🎁)
                InkWell(
                  onTap: () {
                    ShopModal.show(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      gradient: AppColors.vipGoldGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.card_giftcard_rounded, color: Colors.black, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularControl({
    required IconData icon,
    required VoidCallback onTap,
    bool isAlert = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isAlert ? AppColors.danger : Colors.black.withOpacity(0.65),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

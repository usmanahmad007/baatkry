import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/vip_avatar.dart';
import '../../models/chat_message.dart';
import '../../models/gift_transaction.dart';
import '../../models/user_profile.dart';
import '../../models/wallet.dart';
import '../../services/guest_session_service.dart';
import '../../services/livekit_service.dart';
import '../../services/matchmaking_service.dart';
import '../../services/supabase_service.dart';
import '../auth/auth_modal.dart';
import '../gift/gift_animation_overlay.dart';
import '../gift/gift_modal.dart';
import '../home/widgets/country_picker_modal.dart';
import '../moderation/eula_modal.dart';
import '../moderation/report_modal.dart';
import '../shop/shop_modal.dart';
import '../../models/country.dart';

class VideoCallScreen extends ConsumerStatefulWidget {
  final MatchResult matchResult;
  final UserProfile myProfile;
  final String genderFilter;
  final String countryFilter;

  const VideoCallScreen({
    super.key,
    required this.matchResult,
    required this.myProfile,
    this.genderFilter = 'everyone',
    this.countryFilter = 'Global (Worldwide)',
  });

  @override
  ConsumerState<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends ConsumerState<VideoCallScreen> {
  final LiveKitService _liveKit = LiveKitService.instance;
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  StreamSubscription<VideoTrack?>? _remoteTrackSub;
  StreamSubscription<ChatMessage>? _chatSub;
  StreamSubscription<GiftEvent>? _giftSub;
  StreamSubscription<void>? _peerDisconnectedSub;
  StreamSubscription<UserProfile?>? _profileSub;
  StreamSubscription<UserWallet?>? _walletSub;
  StreamSubscription<MatchResult>? _matchSub;
  StreamSubscription<MatchmakingStatus>? _statusSub;
  late String _activeCountryFilter;

  VideoTrack? _remoteVideoTrack;
  LocalVideoTrack? _localVideoTrack;

  // Active Match Result (smooth in-place transition without reloading screen)
  late MatchResult _activeMatchResult;
  bool _isSearchingNext = false;

  // Call Timers & Economy
  int _callElapsedSeconds = 0; // Current person call elapsed seconds
  int _guestTotalSecondsUsed = 0; // Total guest seconds across all calls
  late int _coinsRemaining;
  Timer? _callTimer;
  bool _isTheaterMode = false;
  bool _showMobileChat = false;
  String _friendStatus = 'none'; // 'none', 'pending_sent', 'pending_received', 'friends'
  bool _isSendingFriendRequest = false;

  late String _activeGenderFilter;
  late bool _isGenderFiltered;

  bool get _isGuest => widget.myProfile.isAnonymous;

  @override
  void initState() {
    super.initState();
    _activeMatchResult = widget.matchResult;
    _activeCountryFilter = widget.countryFilter;
    _checkFriendStatus();
    final filter = widget.genderFilter.toLowerCase().trim();
    final requestedVip = filter.isNotEmpty && filter != 'everyone' && filter != 'unspecified';
    final initialCoins = SupabaseService.instance.currentProfile?.coins ?? widget.myProfile.coins;
    final hasCoins = initialCoins > 0 || widget.myProfile.isVip;
    final isVip = requestedVip && hasCoins;

    _activeGenderFilter = isVip ? filter : 'everyone';
    _isGenderFiltered = isVip;
    _coinsRemaining = initialCoins;
    _guestTotalSecondsUsed = GuestSessionService.instance.cachedSecondsUsed;

    // Listen to real-time profile and wallet updates (coin purchases, gifts sent/received)
    _profileSub = SupabaseService.instance.profileStream.listen((p) {
      if (mounted && p != null) {
        setState(() {
          _coinsRemaining = p.coins;
        });
      }
    });

    _walletSub = SupabaseService.instance.walletStream.listen((w) {
      if (mounted && w != null) {
        setState(() {
          _coinsRemaining = w.balance;
        });
      }
    });

    // Check if guest trial already exhausted before call starts
    if (_isGuest && GuestSessionService.instance.isTrialExhausted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onGuestTrialExhausted();
      });
      return;
    }

    _startLocalCamera();
    _initCall();
    _startCallTimer();
  }

  Future<void> _startLocalCamera() async {
    try {
      final track = await _liveKit.getOrCreateLocalCamera();
      if (mounted && track != null) {
        setState(() => _localVideoTrack = track);
      }
    } catch (e) {
      debugPrint('[VideoCallScreen] _startLocalCamera error: $e');
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _callElapsedSeconds++;

        // ---------------------------------------------------------------------
        // GUEST MODE RULES:
        // 1. Max 3 Minutes (180s) Total Talk Time
        // 2. Max 30 Seconds with one person -> auto skip to next available user
        // ---------------------------------------------------------------------
        if (_isGuest) {
          _guestTotalSecondsUsed++;

          // Persist guest seconds every 5 seconds
          if (_guestTotalSecondsUsed % 5 == 0 ||
              _guestTotalSecondsUsed >= GuestSessionService.maxGuestTotalSeconds) {
            GuestSessionService.instance.recordSecondsUsed(_guestTotalSecondsUsed);
          }

          // Rule 1: 3 Minutes total exhausted
          if (_guestTotalSecondsUsed >= GuestSessionService.maxGuestTotalSeconds) {
            _onGuestTrialExhausted();
            return;
          }

          // Rule 2: 30 Seconds with current person reached -> auto change user
          if (_callElapsedSeconds >= GuestSessionService.maxGuestPersonSeconds) {
            _onGuestPersonTimeLimitReached();
            return;
          }
        }

        // ---------------------------------------------------------------------
        // LOGGED-IN (GMAIL / GOOGLE) USER RULES:
        // 1. Random Gender Chat: 100% UNLIMITED, NEVER consumes coins!
        //    Every 30s prompts user to choose specific gender if they wish.
        // 2. Specific Gender Chat: Uses coins time ONLY (1 coin = 1 second).
        // ---------------------------------------------------------------------
        if (_isGenderFiltered) {
          // Specific Gender: use coins time only (1 coin = 1 second)
          if (_coinsRemaining > 0) {
            _coinsRemaining--;
            // Immediately sync in-memory so other widgets/screens show live reduction
            SupabaseService.instance.updateLocalCoinsInMemory(_coinsRemaining);

            // Persist to database/storage every 5 seconds or when hitting 0
            if (_coinsRemaining % 5 == 0 || _coinsRemaining == 0) {
              SupabaseService.instance.updateCoinsBalance(_coinsRemaining);
            }
          } else {
            SupabaseService.instance.updateCoinsBalance(0);
            _onGenderCoinsExhausted();
          }
        } else {
          // Random Gender: DO NOT USE COINS! Unlimited free chat without interruptions.
        }
      });
    });
  }

  /// Open gender switch modal manually (e.g. from call header action pill)
  void _showGenderSwitchPrompt() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.coinGold, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.coinGold.withOpacity(isDark ? 0.35 : 0.2),
                  blurRadius: 28,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: AppColors.vipGoldGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.star_rounded, color: Colors.black, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose Specific Gender 👑',
                            style: TextStyle(
                              color: isDark ? Colors.white : AppColors.lightTextPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Select preferred gender (1 coin = 1s)',
                            style: TextStyle(
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _buildGenderChoiceButton(
                        dialogContext,
                        gender: 'women',
                        label: 'Women 👑',
                        icon: Icons.female_rounded,
                        gradient: const LinearGradient(colors: [Color(0xFFEC4899), Color(0xFFF43F5E)]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildGenderChoiceButton(
                        dialogContext,
                        gender: 'men',
                        label: 'Men 👑',
                        icon: Icons.male_rounded,
                        gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF6366F1)]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildGenderChoiceButton(
                        dialogContext,
                        gender: 'transgender',
                        label: 'Trans 👑',
                        icon: Icons.transgender_rounded,
                        gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFA855F7)]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Your Balance: $_coinsRemaining Coins',
                      style: const TextStyle(color: AppColors.coinGold, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(
                        'Stay in Random Chat',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : AppColors.lightTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGenderChoiceButton(
    BuildContext dialogCtx, {
    required String gender,
    required String label,
    required IconData icon,
    required LinearGradient gradient,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: () {
          Navigator.of(dialogCtx).pop();
          _onSelectSpecificGender(gender);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _onSelectSpecificGender(String gender) {
    if (_coinsRemaining <= 0) {
      // User has NO coins: Ask user to add coins by opening topup!
      _showTopupRequiredDialog(gender);
    } else {
      // User HAS coins: apply gender filter, reset time to 0, and RELOAD session to match preferred gender!
      setState(() {
        _activeGenderFilter = gender;
        _isGenderFiltered = true;
        _callElapsedSeconds = 0; // Reset time to 0 every time user switches
      });
      _onSkipToNext();
    }
  }

  void _switchToFreeRandom() {
    // Flush exact remaining coins to storage
    SupabaseService.instance.updateCoinsBalance(_coinsRemaining);

    // Switch to free random, reset time to 0, and RELOAD session
    setState(() {
      _activeGenderFilter = 'everyone';
      _isGenderFiltered = false;
      _callElapsedSeconds = 0; // Reset time to 0 every time user switches to free
    });
    _onSkipToNext();
  }

  void _showTopupRequiredDialog(String gender) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.coinGold, width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Top-up Required 🪙',
                style: TextStyle(
                  color: isDark ? Colors.white : AppColors.lightTextPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have 0 coins. To talk with ${gender.toUpperCase()}, you need coins (1 coin = 1 second).',
              style: TextStyle(
                color: isDark ? Colors.white : AppColors.lightTextPrimary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Add coins via our top-up packages (min 500 Rs for 60 mins), or continue enjoying free unlimited random chat!',
              style: TextStyle(
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Stay in Free Unlimited',
              style: TextStyle(color: isDark ? Colors.white70 : AppColors.lightTextSecondary),
            ),
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
              child: const Text('Top-up Coins', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  /// Guest 30-second per-person limit reached: automatically change user
  void _onGuestPersonTimeLimitReached() {
    _callTimer?.cancel();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.brandIndigo,
        content: Row(
          children: [
            Icon(Icons.autorenew_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '30s guest limit reached! Auto-switching to next person...',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );
    _onSkipToNext();
  }

  /// Guest 3-minute total trial exhausted: prompt login
  void _onGuestTrialExhausted() {
    _callTimer?.cancel();
    _liveKit.disconnect();
    GuestSessionService.instance.recordSecondsUsed(GuestSessionService.maxGuestTotalSeconds);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: AppColors.brandIndigo, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.timer_off_rounded, color: AppColors.warning, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Guest Trial Ended (3 Mins)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have used your 3 minutes of free guest talk time (with 30s per-person limit).',
              style: TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              'Sign in with Google to get 100% UNLIMITED free random video chat (no 30s limit!) and unlock VIP gender filters.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(); // Back to Home
            },
            child: const Text('Exit', style: TextStyle(color: AppColors.textMuted)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
                AuthModal.show(context);
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('G ', style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w900, fontSize: 16)),
                  Text('Sign In for Unlimited', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onGenderCoinsExhausted() {
    // Safety guard: Never show coin finished popup if user is in free unlimited mode!
    if (!_isGenderFiltered) return;
    _callTimer?.cancel();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool choseTopup = false;
    int autoSwitchCountdown = 5;
    Timer? countdownTimer;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (!ctx.mounted) {
              t.cancel();
              return;
            }
            if (autoSwitchCountdown > 1) {
              setDialogState(() => autoSwitchCountdown--);
            } else {
              t.cancel();
              if (Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop();
              }
            }
          });

          return AlertDialog(
            backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: AppColors.coinGold, width: 1.5),
            ),
            title: Row(
              children: [
                const Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 24),
                const SizedBox(width: 8),
                Text(
                  'VIP Coins Finished 🪙',
                  style: TextStyle(
                    color: isDark ? Colors.white : AppColors.lightTextPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your coins for filtering ${_activeGenderFilter.toUpperCase()} have reached 0.',
                  style: TextStyle(
                    color: isDark ? Colors.white : AppColors.lightTextPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Auto-switching to Free Unlimited Random Mode in $autoSwitchCountdown seconds...\nYou can also add top-up anytime.',
                  style: TextStyle(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
            actions: [
              Container(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onPressed: () {
                    countdownTimer?.cancel();
                    Navigator.of(ctx).pop();
                    _switchToFreeRandom();
                  },
                  child: Text(
                    'Return to Free ($autoSwitchCountdown s)',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.coinGold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: () {
                  countdownTimer?.cancel();
                  choseTopup = true;
                  Navigator.of(ctx).pop();
                  ShopModal.show(context).then((_) {
                    if (mounted && _coinsRemaining <= 0) {
                      _switchToFreeRandom();
                    }
                  });
                },
                child: const Text('Add Top-up', style: TextStyle(color: AppColors.coinGold, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      countdownTimer?.cancel();
      // Auto-switch to free random if user dismissed dialog or countdown completed without topping up
      if (!choseTopup && mounted && (_isGenderFiltered || _coinsRemaining <= 0)) {
        _switchToFreeRandom();
      }
    });
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
        if (msg.text.startsWith('__FRIEND_REQ__')) {
          _handleIncomingFriendRequestInCall(msg);
          return;
        }
        setState(() => _messages.add(msg));
        _scrollChatToBottom();
      }
    });

    _giftSub = _liveKit.giftEventStream.listen((event) async {
      if (mounted) {
        final myId = SupabaseService.instance.currentProfile?.id ?? widget.myProfile.id;
        final isMe = event.senderId == myId;

        if (!isMe) {
          // Received gift: add coins to receiver's account live!
          await SupabaseService.instance.creditReceivedGiftCoins(
            coins: event.coins,
            senderId: event.senderId,
            senderName: event.senderName,
            giftName: event.giftName,
          );
          if (mounted) {
            setState(() {
              _coinsRemaining = SupabaseService.instance.currentProfile?.coins ?? (_coinsRemaining + event.coins);
            });
          }
        } else {
          // Gifter sent gift: deduct coins from gifter account
          if (mounted) {
            setState(() {
              _coinsRemaining = SupabaseService.instance.currentProfile?.coins ?? (_coinsRemaining - event.coins);
            });
          }
        }

        final systemMsg = ChatMessage(
          id: 'gift_${DateTime.now().millisecondsSinceEpoch}',
          senderId: event.senderId,
          senderName: 'System',
          text: isMe
              ? '🎁 You sent ${event.giftName} ${event.emoji} (${event.coins} Coins)'
              : '🎁 ${event.senderName} sent you ${event.giftName} ${event.emoji} (+${event.coins} Coins credited!)',
          timestamp: event.timestamp,
          isMe: isMe,
        );
        setState(() => _messages.add(systemMsg));
        _scrollChatToBottom();
      }
    });

    _peerDisconnectedSub = _liveKit.peerDisconnectedStream.listen((_) {
      if (mounted && !_isSearchingNext) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stranger skipped. Finding next match...'),
            duration: Duration(seconds: 1),
          ),
        );
        _onSkipToNext();
      }
    });

    await _connectToRoom(_activeMatchResult);
  }

  Future<void> _connectToRoom(MatchResult match) async {
    try {
      await _liveKit.connect(
        roomName: match.roomId,
        token: match.token,
      );

      if (mounted) {
        setState(() {
          _localVideoTrack = _liveKit.localCameraTrack;
        });
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
    _profileSub?.cancel();
    _walletSub?.cancel();
    _matchSub?.cancel();
    _statusSub?.cancel();
    if (_isGenderFiltered) {
      SupabaseService.instance.updateCoinsBalance(_coinsRemaining);
    }
    if (_isGuest) {
      GuestSessionService.instance.recordSecondsUsed(_guestTotalSecondsUsed);
    }
    _remoteTrackSub?.cancel();
    _chatSub?.cancel();
    _giftSub?.cancel();
    _peerDisconnectedSub?.cancel();
    _liveKit.disconnect();
    _liveKit.stopLocalPreview();
    _textController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _onSkipToNext() async {
    if (_isSearchingNext) return;

    _callTimer?.cancel();

    if (_isGenderFiltered) {
      await SupabaseService.instance.updateCoinsBalance(_coinsRemaining);
    }

    if (_isGuest) {
      await GuestSessionService.instance.recordSecondsUsed(_guestTotalSecondsUsed);
      if (!mounted) return;
      if (_guestTotalSecondsUsed >= GuestSessionService.maxGuestTotalSeconds) {
        _onGuestTrialExhausted();
        return;
      }
    }

    // 1. Immediately reset state to searching and clear stranger stream
    setState(() {
      _isSearchingNext = true;
      _remoteVideoTrack = null;
      _messages.clear();
      _callElapsedSeconds = 0;
      _friendStatus = 'none';
      _localVideoTrack = _liveKit.localCameraTrack; // keeps camera uninterrupted!
    });

    // 2. Disconnect previous room cleanly so its peer connection is closed,
    // while the local camera track remains running continuously without freezing
    await _liveKit.disconnect();
    if (!mounted) return;

    if (_localVideoTrack == null || _localVideoTrack!.isDisposed) {
      final track = await _liveKit.getOrCreateLocalCamera();
      if (mounted && track != null) {
        setState(() => _localVideoTrack = track);
      }
    }

    // Listen for next match
    _matchSub?.cancel();
    _statusSub?.cancel();

    _matchSub = MatchmakingService.instance.matchStream.listen((newResult) async {
      _matchSub?.cancel();
      _statusSub?.cancel();
      if (!mounted) return;

      setState(() {
        _activeMatchResult = newResult;
        _friendStatus = 'none';
      });

      await _connectToRoom(newResult);
      await _checkFriendStatus();

      if (mounted) {
        setState(() {
          _isSearchingNext = false;
        });
        _startCallTimer();
      }
    });

    _statusSub = MatchmakingService.instance.statusStream.listen((status) {
      if (!mounted) return;
      if (status == MatchmakingStatus.noUsersInCountry && _isSearchingNext) {
        _showNoUsersInCountryDialog();
      } else if (status == MatchmakingStatus.noUsersOnline && _isSearchingNext) {
        _showNoUsersOnlineDialog();
      }
    });

    final currentProf = SupabaseService.instance.currentProfile ?? widget.myProfile;
    final updatedProf = currentProf.copyWith(coins: _coinsRemaining);

    MatchmakingService.instance.findMatch(
      myProfile: updatedProf,
      genderFilter: _activeGenderFilter,
      countryFilter: _activeCountryFilter,
    );
  }

  void _showNoUsersInCountryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfElevated(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.brandPink.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.people_outline_rounded, color: AppColors.brandPink, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Live Users Busy',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Currently all live users from $_activeCountryFilter are chatting with someone please wait or switch to any other country you want.',
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.txtPrimary(context),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandIndigo.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.brandIndigo.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.public_rounded, color: AppColors.brandIndigo, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Global (Worldwide) queue matches immediately with 0 waiting time!',
                      style: TextStyle(fontSize: 12, color: AppColors.txtSecondary(context)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _onSkipToNext();
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(color: AppColors.border(context)),
                  ),
                  child: const Text('Keep Waiting', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _openCountryPicker();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandIndigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Switch Country', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() {
                  _activeCountryFilter = 'Global (Worldwide)';
                });
                _onSkipToNext();
              },
              icon: const Text('🌍', style: TextStyle(fontSize: 16)),
              label: const Text(
                'Switch to Global (Instant & Free)',
                style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showNoUsersOnlineDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfElevated(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.brandPink.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.people_outline_rounded, color: AppColors.brandPink, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Live Users Busy',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Currently all other live users online are chatting with someone. We only connect you with authentic live users (no bots or fake profiles).',
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.txtPrimary(context),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandIndigo.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.brandIndigo.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.radar_rounded, color: AppColors.brandIndigo, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Keep waiting to connect automatically as soon as the next live user finishes their chat or joins!',
                      style: TextStyle(fontSize: 12, color: AppColors.txtSecondary(context)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(color: AppColors.border(context)),
                  ),
                  child: const Text('Exit Call', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _onSkipToNext();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandIndigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Keep Waiting', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openCountryPicker() {
    CountryPickerModal.show(
      context: context,
      currentCountryCode: AppCountry.fromName(_activeCountryFilter).code,
      onCountrySelected: (country, coinsDeducted) {
        setState(() {
          _activeCountryFilter = country.name;
        });
        _onSkipToNext();
      },
    );
  }

  void _onReportUser() {
    ReportModal.show(
      context,
      peerId: _activeMatchResult.peerId,
      peerName: _activeMatchResult.peerName,
      roomId: _activeMatchResult.roomId,
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

    final currentProf = SupabaseService.instance.currentProfile ?? widget.myProfile;
    _liveKit.sendChatMessage(
      text,
      myId: currentProf.id,
      myName: currentProf.nickname,
    );

    if (quickText == null) {
      _textController.clear();
    }
    _scrollChatToBottom();
  }

  Future<void> _checkFriendStatus() async {
    if (_activeMatchResult.peerId.isNotEmpty) {
      try {
        final status = await SupabaseService.instance.checkFriendStatus(_activeMatchResult.peerId);
        if (mounted) {
          setState(() => _friendStatus = status);
        }
      } catch (_) {}
    }
  }

  Future<void> _handleSendFriendRequest() async {
    if (_isSendingFriendRequest) return;
    final currentProf = SupabaseService.instance.currentProfile ?? widget.myProfile;
    if (currentProf.isAnonymous) {
      AuthModal.show(context, onAuthSuccess: () {
        _checkFriendStatus();
      });
      return;
    }

    setState(() => _isSendingFriendRequest = true);

    try {
      final res = await SupabaseService.instance.sendFriendRequest(
        receiverId: _activeMatchResult.peerId,
        receiverName: _activeMatchResult.peerName,
        isDuringVideoChat: true,
      );

      if (mounted) {
        setState(() {
          _isSendingFriendRequest = false;
          _friendStatus = res['status'] == 'accepted' ? 'friends' : 'pending_sent';
        });

        // Transmit friend request signal over LiveKit WebRTC Data Channel
        _liveKit.sendChatMessage(
          '__FRIEND_REQ__:${currentProf.id}:${currentProf.nickname}',
          myId: currentProf.id,
          myName: currentProf.nickname,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.brandIndigo,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            content: Row(
              children: [
                const Icon(Icons.person_add_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    res['message']?.toString() ?? 'Friend request sent to ${_activeMatchResult.peerName}!',
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSendingFriendRequest = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.danger, content: Text('$e')),
        );
      }
    }
  }

  void _handleIncomingFriendRequestInCall(ChatMessage msg) {
    if (mounted) {
      setState(() => _friendStatus = 'pending_received');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.brandIndigo,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          content: Row(
            children: [
              const Icon(Icons.favorite_rounded, color: AppColors.brandPink, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('${_activeMatchResult.peerName} sent you a friend request!')),
            ],
          ),
          action: SnackBarAction(
            label: 'Accept',
            textColor: Colors.white,
            onPressed: () async {
              final requests = await SupabaseService.instance.fetchFriendRequests();
              final matching = requests.where((r) => r.senderId == _activeMatchResult.peerId).toList();
              if (matching.isNotEmpty) {
                await SupabaseService.instance.respondToFriendRequest(requestId: matching.first.id, accept: true);
                if (mounted) {
                  setState(() => _friendStatus = 'friends');
                }
              }
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to real-time profile and wallet updates via Riverpod (live coin deductions & credits)
    ref.listen<AsyncValue<UserProfile?>>(userProfileProvider, (previous, next) {
      final p = next.valueOrNull;
      if (mounted && p != null && p.coins != _coinsRemaining) {
        setState(() {
          _coinsRemaining = p.coins;
        });
      }
    });

    ref.listen<AsyncValue<UserWallet?>>(userWalletStreamProvider, (previous, next) {
      final w = next.valueOrNull;
      if (mounted && w != null && w.balance != _coinsRemaining) {
        setState(() {
          _coinsRemaining = w.balance;
        });
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GiftAnimationOverlay(
        child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            if (_isTheaterMode) {
              setState(() => _isTheaterMode = false);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.meshBackgroundGradient,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 900;

                  if (isDesktop) {
                    // DESKTOP LAYOUT: Top navbar + side-by-side video feeds + right-side chat panel
                    return Column(
                      children: [
                        if (!_isTheaterMode) SafeArea(bottom: false, child: _buildTopNavBar()),
                        Expanded(
                          child: Padding(
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
                          ),
                        ),
                      ],
                    );
                  } else {
                    // MOBILE NATIVE LAYOUT: True full-screen 50/50 vertical split with floating controls & quick skip
                    return SafeArea(
                      child: _buildMobileVideoCallView(constraints),
                    );
                  }
                },
              ),

              // Persistent Floating Controls in Full Screen mode so user can always exit full screen
              if (_isTheaterMode)
                Positioned(
                  top: 14,
                  right: 18,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white24, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildNavPill(
                            icon: Icons.fullscreen_exit_rounded,
                            label: 'Exit Full Screen',
                            accentColor: AppColors.brandCyan,
                            onTap: () => setState(() => _isTheaterMode = false),
                          ),
                          const SizedBox(width: 8),
                          _buildNavPill(
                            icon: Icons.logout_rounded,
                            label: 'Exit Call',
                            accentColor: AppColors.danger,
                            onTap: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

  // ---------------------------------------------------------------------------
  // Mobile Native Video Call Layout (Engineered for native smartphone experience)
  // ---------------------------------------------------------------------------
  Widget _buildMobileVideoCallView(BoxConstraints constraints) {
    return Stack(
      children: [
        // 1. Two 50/50 Video Feeds
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top 50%: Stranger Camera Feed
              Expanded(
                child: _buildStrangerCameraCard(isMobile: true),
              ),
              const SizedBox(height: 6),

              // Bottom 50%: My Local Camera Feed
              Expanded(
                child: _buildMyCameraCard(isMobile: true),
              ),
            ],
          ),
        ),

        // 2. Mobile Floating Top Header Overlay
        Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: _buildMobileFloatingHeader(),
        ),

        // 3. Mobile Floating Bottom Control Dock
        Positioned(
          bottom: 12,
          left: 12,
          right: 12,
          child: _buildMobileBottomControlsDock(),
        ),

        // 4. Mobile Chat Slide-Up Sheet
        if (_showMobileChat)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: constraints.maxHeight * 0.55,
            child: _buildChatSidebar(isMobile: true),
          ),
      ],
    );
  }

  Widget _buildMobileFloatingHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left: Exit Button + Duration / VIP Timer
        Row(
          children: [
            InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.danger.withOpacity(0.6)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.close_rounded, color: AppColors.danger, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Exit',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Call Duration or VIP countdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Icon(
                    _isGenderFiltered ? Icons.workspace_premium_rounded : Icons.timer_outlined,
                    color: _isGenderFiltered ? AppColors.coinGold : AppColors.success,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isGenderFiltered
                        ? '${_formatDuration(_coinsRemaining)} left'
                        : _formatDuration(_callElapsedSeconds),
                    style: TextStyle(
                      color: _isGenderFiltered ? AppColors.coinGold : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // Right: Coins Pill + Report Flag
        Row(
          children: [
            InkWell(
              onTap: () => ShopModal.show(context),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: AppColors.vipGoldGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.coinGold.withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.monetization_on_rounded, size: 14, color: Colors.black),
                    const SizedBox(width: 4),
                    Text(
                      '$_coinsRemaining',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Report User Icon
            InkWell(
              onTap: _onReportUser,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.flag_rounded, color: Colors.white70, size: 16),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileBottomControlsDock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.82),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white12, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // 1. Mic Mute / Unmute
          _buildCircularControl(
            icon: _liveKit.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            isAlert: _liveKit.isMicMuted,
            onTap: () async {
              await _liveKit.toggleMicrophone();
              setState(() {});
            },
          ),
          const SizedBox(width: 4),

          // 2. Video Camera On / Off
          _buildCircularControl(
            icon: _liveKit.isVideoMuted ? Icons.videocam_off_rounded : Icons.videocam_rounded,
            isAlert: _liveKit.isVideoMuted,
            onTap: () async {
              await _liveKit.toggleVideo();
              setState(() {});
            },
          ),
          const SizedBox(width: 4),

          // 3. Flip Camera
          _buildCircularControl(
            icon: Icons.flip_camera_ios_rounded,
            onTap: () async {
              await _liveKit.flipCamera();
              if (mounted) {
                setState(() => _localVideoTrack = _liveKit.localCameraTrack);
              }
            },
          ),
          const SizedBox(width: 4),

          // 4. Add Friend (Strictly during active video chat)
          _buildCircularControl(
            icon: _friendStatus == 'friends'
                ? Icons.people_alt_rounded
                : (_friendStatus == 'pending_sent'
                    ? Icons.hourglass_top_rounded
                    : Icons.person_add_alt_1_rounded),
            color: _friendStatus == 'friends'
                ? AppColors.success
                : (_friendStatus == 'pending_sent' ? AppColors.coinGold.withOpacity(0.3) : null),
            iconColor: _friendStatus == 'friends'
                ? Colors.white
                : (_friendStatus == 'pending_sent' ? AppColors.coinGold : Colors.white),
            onTap: (_friendStatus == 'friends' || _friendStatus == 'pending_sent' || _isSendingFriendRequest)
                ? () {}
                : _handleSendFriendRequest,
          ),
          const SizedBox(width: 4),

          // 5. Send Gift
          _buildCircularControl(
            icon: Icons.card_giftcard_rounded,
            onTap: () {
              GiftModal.show(
                context,
                peerId: _activeMatchResult.peerId,
                peerName: _activeMatchResult.peerName,
                roomId: _activeMatchResult.roomId,
              );
            },
          ),
          const SizedBox(width: 4),

          // 6. Text Chat with unread badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              _buildCircularControl(
                icon: Icons.chat_bubble_outline_rounded,
                onTap: () => setState(() => _showMobileChat = !_showMobileChat),
              ),
              if (_messages.isNotEmpty)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.brandPink,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${_messages.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 6),

          // 7. Prominent Mobile "NEXT ⚡" Button (Instant Stranger Skip)
          Expanded(
            child: InkWell(
              onTap: _onSkipToNext,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandPink.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 2),
                          Text(
                            'NEXT',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top Navigation Bar (Modern pills and controls)
  // ---------------------------------------------------------------------------
  Widget _buildTopNavBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 32),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
          // Left Pills: Exit, Safety Lab, Theater Mode, Coins
          Row(
            children: [
              _buildNavPill(
                icon: Icons.logout_rounded,
                label: 'Exit',
                accentColor: AppColors.danger,
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              _buildNavPill(
                icon: Icons.shield_rounded,
                label: 'Safety Lab',
                onTap: () => EulaModal.checkAndShow(context, onAccepted: () {}),
              ),
              const SizedBox(width: 10),
              _buildNavPill(
                icon: _isTheaterMode ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                label: _isTheaterMode ? 'Exit Full Screen' : 'Full Screen',
                accentColor: _isTheaterMode ? AppColors.brandCyan : null,
                onTap: () => setState(() => _isTheaterMode = !_isTheaterMode),
              ),
              const SizedBox(width: 10),
              _buildNavPill(
                icon: Icons.monetization_on_rounded,
                label: '$_coinsRemaining Coins',
                accentColor: AppColors.coinGold,
                onTap: () => ShopModal.show(context),
              ),
            ],
          ),

          // Right: Live Duration & Guest Countdown or VIP Coins
          Row(
            children: [
              if (_isGuest) ...[
                // Guest Rule 1: Auto-Switch 30s Countdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (GuestSessionService.maxGuestPersonSeconds - _callElapsedSeconds) <= 5
                        ? AppColors.danger.withOpacity(0.25)
                        : AppColors.brandIndigo.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: (GuestSessionService.maxGuestPersonSeconds - _callElapsedSeconds) <= 5
                          ? AppColors.danger
                          : AppColors.brandIndigo,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.av_timer_rounded,
                        size: 14,
                        color: (GuestSessionService.maxGuestPersonSeconds - _callElapsedSeconds) <= 5
                            ? AppColors.danger
                            : Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Auto-next: ${max(0, GuestSessionService.maxGuestPersonSeconds - _callElapsedSeconds)}s',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: (GuestSessionService.maxGuestPersonSeconds - _callElapsedSeconds) <= 5
                              ? AppColors.danger
                              : Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Guest Rule 2: 3 Mins Total Countdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_bottom_rounded, size: 14, color: AppColors.coinGold),
                      const SizedBox(width: 4),
                      Text(
                        'Trial: ${max(0, GuestSessionService.maxGuestTotalSeconds - _guestTotalSecondsUsed)}s',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.coinGold, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Google Logged-In User
                if (!_isGenderFiltered) ...[
                  // CASE A: RANDOM GENDER CHAT (100% FREE & UNLIMITED)
                  // 1. Explicit Mode Badge: FREE MODE
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.success.withOpacity(0.6)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success),
                        SizedBox(width: 4),
                        Text(
                          'FREE MODE (Unlimited)',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 2. Display coin balance (DO NOT DEDUCT COINS!)
                  InkWell(
                    onTap: () => ShopModal.show(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: AppColors.vipGoldGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.monetization_on_rounded, size: 14, color: Colors.black),
                          const SizedBox(width: 4),
                          Text(
                            '$_coinsRemaining Coins',
                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 3. Display Call Duration
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: AppColors.darkCardGradient,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.brandIndigo.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.all_inclusive_rounded, size: 15, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(
                          _formatDuration(_callElapsedSeconds),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 4. Filter Gender 👑 Action Pill
                  InkWell(
                    onTap: _showGenderSwitchPrompt,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.coinGold.withOpacity(0.5)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.workspace_premium_rounded, size: 14, color: AppColors.coinGold),
                          SizedBox(width: 4),
                          Text(
                            'Filter Gender 👑',
                            style: TextStyle(color: AppColors.coinGold, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  // CASE B: SPECIFIC GENDER CHAT (VIP MODE: Women, Men, Trans)
                  // 1. Explicit Mode Badge: VIP MODE
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: AppColors.vipGoldGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.coinGold.withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.workspace_premium_rounded, size: 14, color: Colors.black),
                        const SizedBox(width: 4),
                        Text(
                          'VIP MODE (${_activeGenderFilter.toUpperCase()})',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 2. Display ONLY coins time remaining (1 coin = 1 second)
                  InkWell(
                    onTap: () => ShopModal.show(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: _coinsRemaining < 60 ? AppColors.danger : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _coinsRemaining < 60 ? AppColors.danger : AppColors.coinGold.withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _coinsRemaining < 60 ? Icons.timer_outlined : Icons.timer_rounded,
                            size: 14,
                            color: _coinsRemaining < 60 ? Colors.white : AppColors.coinGold,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${_formatDuration(_coinsRemaining)} left ($_coinsRemaining coins)',
                            style: TextStyle(
                              color: _coinsRemaining < 60 ? Colors.white : AppColors.coinGold,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 3. Return to Free Action Pill
                  InkWell(
                    onTap: _switchToFreeRandom,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.brandCyan.withOpacity(0.6)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.autorenew_rounded, size: 14, color: AppColors.brandCyan),
                          SizedBox(width: 4),
                          Text(
                            'Return to Free',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(width: 10),

              // User Avatar
              VipAvatar(
                radius: 16,
                nickname: widget.myProfile.nickname,
                avatarUrl: widget.myProfile.avatarUrl,
                isVip: widget.myProfile.isVip,
                showVipBadge: true,
              ),
            ],
          ),
        ],
      ),
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
          // Local Camera Feed with unique ValueKey to prevent native texture freezing/sticking
          if (_localVideoTrack != null && !_localVideoTrack!.isDisposed)
            VideoTrackRenderer(
              _localVideoTrack!,
              key: ValueKey('local_track_${_localVideoTrack!.sid ?? _localVideoTrack!.mediaStreamTrack.id}'),
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

          // "You" Pill with Mic Mute Status Indicator (top on mobile so dock doesn't cover it)
          Positioned(
            top: isMobile ? 12 : null,
            bottom: isMobile ? null : 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _liveKit.isMicMuted ? AppColors.danger.withOpacity(0.6) : Colors.white12,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _liveKit.isMicMuted ? Icons.mic_off_rounded : Icons.circle,
                    color: _liveKit.isMicMuted ? AppColors.danger : AppColors.success,
                    size: _liveKit.isMicMuted ? 14 : 8,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _liveKit.isMicMuted ? 'You (Muted)' : 'You (Live)',
                    style: TextStyle(
                      color: _liveKit.isMicMuted ? AppColors.danger : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Right: Flip Camera, Video On/Off & Mic Controls (Desktop only - mobile has dedicated bottom dock)
          if (!isMobile)
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
                    icon: _liveKit.isVideoMuted ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                    isAlert: _liveKit.isVideoMuted,
                    onTap: () async {
                      await _liveKit.toggleVideo();
                      setState(() {});
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildCircularControl(
                    icon: Icons.flip_camera_ios_rounded,
                    onTap: () async {
                      await _liveKit.flipCamera();
                      if (mounted) {
                        setState(() => _localVideoTrack = _liveKit.localCameraTrack);
                      }
                    },
                  ),
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
          // Remote Peer Video Feed or In-Place Searching Next Overlay
          if (_isSearchingNext)
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
                    Container(
                      width: 68,
                      height: 68,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.brandIndigo.withOpacity(0.2),
                        border: Border.all(color: AppColors.brandIndigo.withOpacity(0.6), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brandIndigo.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandCyan),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _activeGenderFilter == 'everyone'
                          ? 'Searching next stranger...'
                          : 'Finding ${_activeGenderFilter.toUpperCase()} 👑...',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isGenderFiltered
                          ? 'VIP Mode • 1 coin = 1 second'
                          : 'Free Unlimited Mode',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_remoteVideoTrack != null && !_remoteVideoTrack!.isDisposed)
            VideoTrackRenderer(
              _remoteVideoTrack!,
              key: ValueKey('remote_track_${_remoteVideoTrack!.sid ?? _remoteVideoTrack!.mediaStreamTrack.id}'),
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
                        _activeMatchResult.peerName.isNotEmpty ? _activeMatchResult.peerName[0].toUpperCase() : 'P',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _activeMatchResult.peerName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    const Text('Connecting stranger stream...', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ),

          // Top Left Overlay: Avatar, Name, Location, Heart, Badges (positioned below mobile header on mobile)
          if (!_isSearchingNext)
            Positioned(
              top: isMobile ? 54 : 14,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.brandIndigo,
                    child: Text(
                      _activeMatchResult.peerName.isNotEmpty ? _activeMatchResult.peerName[0].toUpperCase() : 'R',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Name & Location
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _activeMatchResult.peerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${_activeMatchResult.peerCountryFlag} ${_activeMatchResult.peerCountry} • Online',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Add Friend Action Button (Enforced: during video chat only)
                  InkWell(
                    onTap: (_friendStatus == 'friends' || _friendStatus == 'pending_sent' || _isSendingFriendRequest)
                        ? null
                        : _handleSendFriendRequest,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _friendStatus == 'friends'
                            ? AppColors.success.withOpacity(0.25)
                            : (_friendStatus == 'pending_sent'
                                ? AppColors.coinGold.withOpacity(0.25)
                                : AppColors.brandPink.withOpacity(0.35)),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _friendStatus == 'friends'
                              ? AppColors.success
                              : (_friendStatus == 'pending_sent' ? AppColors.coinGold : Colors.white30),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _friendStatus == 'friends'
                                ? Icons.check_circle_rounded
                                : (_friendStatus == 'pending_sent'
                                    ? Icons.hourglass_top_rounded
                                    : Icons.person_add_rounded),
                            color: _friendStatus == 'friends'
                                ? AppColors.success
                                : (_friendStatus == 'pending_sent' ? AppColors.coinGold : Colors.white),
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _friendStatus == 'friends'
                                ? 'Friends'
                                : (_friendStatus == 'pending_sent' ? 'Sent' : 'Add Friend'),
                            style: TextStyle(
                              color: _friendStatus == 'friends'
                                  ? AppColors.success
                                  : (_friendStatus == 'pending_sent' ? AppColors.coinGold : Colors.white),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!isMobile) ...[
                    const SizedBox(width: 6),
                    // Flag / Report Icon (on mobile, flag is in top floating header)
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
                ],
              ),
            ),

          // Bottom Left: baatkry.com pill
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
                    'baatkry.com',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Right: Quick Gift + Big Skip/Next Button (Desktop only - mobile has bottom dock)
          if (!isMobile)
            Positioned(
              bottom: 14,
              right: 14,
              child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isSearchingNext) ...[
                  // Desktop Add Friend Button (Active video chat only)
                  InkWell(
                    onTap: (_friendStatus == 'friends' || _friendStatus == 'pending_sent' || _isSendingFriendRequest)
                        ? null
                        : _handleSendFriendRequest,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _friendStatus == 'friends'
                            ? AppColors.success.withOpacity(0.3)
                            : (_friendStatus == 'pending_sent'
                                ? AppColors.coinGold.withOpacity(0.3)
                                : Colors.black54),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _friendStatus == 'friends'
                              ? AppColors.success
                              : (_friendStatus == 'pending_sent'
                                  ? AppColors.coinGold
                                  : Colors.white24),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          _friendStatus == 'friends'
                              ? Icons.people_alt_rounded
                              : (_friendStatus == 'pending_sent'
                                  ? Icons.hourglass_top_rounded
                                  : Icons.person_add_alt_1_rounded),
                          color: _friendStatus == 'friends'
                              ? AppColors.success
                              : (_friendStatus == 'pending_sent'
                                  ? AppColors.coinGold
                                  : Colors.white),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () {
                      GiftModal.show(
                        context,
                        peerId: _activeMatchResult.peerId,
                        peerName: _activeMatchResult.peerName,
                        roomId: _activeMatchResult.roomId,
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: AppColors.vipGoldGradient,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white70, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.coinGold.withOpacity(0.4),
                            blurRadius: 14,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('🎁', style: TextStyle(fontSize: 22)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                InkWell(
                  onTap: _isSearchingNext ? null : _onSkipToNext,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: _isSearchingNext ? null : AppColors.primaryGradient,
                      color: _isSearchingNext ? Colors.white24 : null,
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
                    child: Icon(
                      _isSearchingNext ? Icons.hourglass_top_rounded : Icons.fast_forward_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ],
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
                VipAvatar(
                  radius: 14,
                  nickname: widget.myProfile.nickname,
                  avatarUrl: widget.myProfile.avatarUrl,
                  isVip: widget.myProfile.isVip,
                  showVipBadge: true,
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
                    GiftModal.show(
                      context,
                      peerId: _activeMatchResult.peerId,
                      peerName: _activeMatchResult.peerName,
                      roomId: _activeMatchResult.roomId,
                    );
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
    Color? color,
    Color? iconColor,
    double size = 36,
    double iconSize = 18,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color ?? (isAlert ? AppColors.danger : Colors.black.withOpacity(0.65)),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: iconColor ?? Colors.white, size: iconSize),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../../services/matchmaking_service.dart';
import '../../services/supabase_service.dart';
import '../call/video_call_screen.dart';

class RadarScreen extends StatefulWidget {
  final UserProfile profile;
  final String genderFilter;

  const RadarScreen({
    super.key,
    required this.profile,
    this.genderFilter = 'everyone',
  });

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  StreamSubscription<MatchResult>? _matchSub;
  String _statusText = 'Looking for someone special...';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _startMatchmaking();
  }

  void _startMatchmaking() {
    _matchSub = MatchmakingService.instance.matchStream.listen((result) {
      if (mounted) {
        setState(() => _statusText = 'Match found! Connecting video...');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => VideoCallScreen(
              matchResult: result,
              myProfile: SupabaseService.instance.currentProfile ?? widget.profile,
              genderFilter: widget.genderFilter,
            ),
          ),
        );
      }
    });

    MatchmakingService.instance.findMatch(
      myProfile: widget.profile,
      genderFilter: widget.genderFilter,
    );
  }

  @override
  void dispose() {
    _matchSub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _onCancel() {
    MatchmakingService.instance.cancelSearch();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.meshGrad(context),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: AppColors.cardGrad(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border(context)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '⚡ Live Matchmaking',
                            style: TextStyle(
                              color: AppColors.txtPrimary(context),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          if (widget.genderFilter != 'everyone') ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: AppColors.vipGoldGradient,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                widget.genderFilter.toUpperCase(),
                                style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: isDark ? Colors.white : AppColors.lightTextPrimary,
                        size: 28,
                      ),
                      onPressed: _onCancel,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Radar pulse circles
              Center(
                child: SizedBox(
                  width: 280,
                  height: 280,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ...List.generate(3, (index) {
                        return AnimatedBuilder(
                          animation: _animController,
                          builder: (context, child) {
                            final progress = (_animController.value + (index / 3)) % 1.0;
                            return Opacity(
                              opacity: (1.0 - progress).clamp(0.0, 1.0),
                              child: Container(
                                width: 280 * progress,
                                height: 280 * progress,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.brandIndigo.withOpacity(isDark ? 0.7 : 0.4),
                                    width: 2,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      }),
                      // Center Avatar Pulse
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.primaryGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brandIndigo.withOpacity(0.6),
                              blurRadius: 28,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.videocam_rounded, size: 42, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 36),
              Text(
                _statusText,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.txtPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.genderFilter == 'everyone'
                    ? 'Connecting with random strangers worldwide...'
                    : 'Searching for ${widget.genderFilter} online now...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.txtSecondary(context),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: AppColors.border(context), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      backgroundColor: AppColors.surfElevated(context),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppColors.txtPrimary(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

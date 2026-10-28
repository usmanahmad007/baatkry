import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/app_config.dart';
import '../models/user_profile.dart';
import 'supabase_service.dart';

/// Tracks authentic, 100% real live online users connected to the app globally.
/// Uses Supabase Realtime Presence — no fake numbers, dummy bots, or simulated users.
class PresenceService {
  static final PresenceService instance = PresenceService._internal();
  PresenceService._internal();

  RealtimeChannel? _presenceChannel;
  int _totalLiveUsers = 1;
  Map<String, int> _countryCounts = const {};
  final _liveCountController = StreamController<int>.broadcast();
  final _countryCountsController = StreamController<Map<String, int>>.broadcast();
  StreamSubscription<UserProfile?>? _profileSub;

  int get totalLiveUsersCount => _totalLiveUsers;
  Map<String, int> get countryCounts => _countryCounts;
  Stream<int> get liveUsersCountStream => _liveCountController.stream;
  Stream<Map<String, int>> get countryCountsStream => _countryCountsController.stream;

  /// Initialize real-time presence tracking with the Supabase client
  Future<void> init() async {
    _profileSub?.cancel();
    _profileSub = SupabaseService.instance.profileStream.listen((profile) {
      if (profile != null) {
        _trackUser(profile);
      }
    });

    final currentProfile = SupabaseService.instance.currentProfile;
    if (currentProfile != null) {
      await _trackUser(currentProfile);
    }
  }

  Future<void> _trackUser(UserProfile profile) async {
    final client = SupabaseService.instance.client;
    if (client == null || !AppConfig.isSupabaseConfigured) {
      // Local fallback with single authentic live user
      _totalLiveUsers = 1;
      _countryCounts = {profile.countryCode.toUpperCase(): 1};
      _liveCountController.add(_totalLiveUsers);
      _countryCountsController.add(_countryCounts);
      return;
    }

    try {
      if (_presenceChannel == null) {
        _presenceChannel = client.channel('baatkry_global_presence');
        _presenceChannel!.onPresenceSync((_) {
          _handlePresenceSync();
        });

        _presenceChannel!.subscribe((status, [error]) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _presenceChannel!.track({
              'user_id': profile.id,
              'country': profile.country,
              'country_code': profile.countryCode,
              'nickname': profile.nickname,
              'joined_at': DateTime.now().toIso8601String(),
            });
          }
        });
      } else {
        await _presenceChannel!.track({
          'user_id': profile.id,
          'country': profile.country,
          'country_code': profile.countryCode,
          'nickname': profile.nickname,
          'joined_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('[PresenceService] Error tracking live presence: $e');
    }
  }

  void _handlePresenceSync() {
    if (_presenceChannel == null) return;
    try {
      final presenceState = _presenceChannel!.presenceState();
      int count = 0;
      final Map<String, int> counts = {};

      for (final entry in presenceState) {
        for (final p in entry.presences) {
          count++;
          final code = (p.payload['country_code'] as String? ?? 'ALL').toUpperCase();
          counts[code] = (counts[code] ?? 0) + 1;
        }
      }

      // Minimum 1 live user is always the current user using the app
      _totalLiveUsers = count > 0 ? count : 1;
      _countryCounts = counts;
      _liveCountController.add(_totalLiveUsers);
      _countryCountsController.add(_countryCounts);
    } catch (e) {
      debugPrint('[PresenceService] Error in presence sync: $e');
    }
  }

  Future<void> dispose() async {
    _profileSub?.cancel();
    try {
      await _presenceChannel?.untrack();
      await _presenceChannel?.unsubscribe();
      _presenceChannel = null;
    } catch (_) {}
  }
}

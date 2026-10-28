import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../models/country.dart';
import '../models/user_profile.dart';
import 'supabase_service.dart';
import 'token_service.dart';

enum MatchmakingStatus {
  idle,
  searching,
  matched,
  connecting,
  failed,
  noUsersInCountry,
  noUsersOnline,
}

class MatchResult {
  final String roomId;
  final String token;
  final String peerId;
  final String peerName;
  final String peerGender;
  final String peerCountry;
  final String peerCountryFlag;
  final List<String> commonInterests;

  const MatchResult({
    required this.roomId,
    required this.token,
    required this.peerId,
    required this.peerName,
    this.peerGender = 'unspecified',
    this.peerCountry = 'Global (Worldwide)',
    this.peerCountryFlag = '🌍',
    this.commonInterests = const [],
  });
}

/// Strictly authentic real-time matchmaking service.
/// ONLY pairs genuine live users connected simultaneously via Supabase Realtime.
/// NEVER creates fake, mock, dummy, or simulated users.
class MatchmakingService {
  static final MatchmakingService instance = MatchmakingService._internal();
  MatchmakingService._internal();

  /// Search timeout for specific countries when no users are live (defaults to 60s)
  static Duration countrySearchTimeout = const Duration(seconds: 60);

  /// Search timeout for global matching when queue has no active peers (defaults to 45s)
  static Duration globalSearchTimeout = const Duration(seconds: 45);

  RealtimeChannel? _channel;
  MatchmakingStatus _status = MatchmakingStatus.idle;
  final _statusController = StreamController<MatchmakingStatus>.broadcast();
  final _matchController = StreamController<MatchResult>.broadcast();
  Timer? _searchTimeoutTimer;
  Timer? _periodicSyncTimer;

  MatchmakingStatus get status => _status;
  Stream<MatchmakingStatus> get statusStream => _statusController.stream;
  Stream<MatchResult> get matchStream => _matchController.stream;

  /// Helper to test if a country selection is Worldwide / Global
  static bool isWorldwide(String? filter) {
    if (filter == null || filter.trim().isEmpty) return true;
    final f = filter.toLowerCase().trim();
    return f == 'all' || f.contains('global') || f.contains('worldwide');
  }

  /// Generates a deterministic, shared room ID between any two users so both
  /// are guaranteed to enter the identical LiveKit room.
  static String generateRoomId(String idA, String idB) {
    final first = idA.compareTo(idB) < 0 ? idA : idB;
    final second = idA.compareTo(idB) < 0 ? idB : idA;
    final s1 = first.length > 8 ? first.substring(0, 8) : first;
    final s2 = second.length > 8 ? second.substring(0, 8) : second;
    return 'room_${s1}_$s2';
  }

  /// Start searching for a real live match.
  Future<void> findMatch({
    required UserProfile myProfile,
    String genderFilter = 'everyone',
    String countryFilter = 'Global (Worldwide)',
  }) async {
    _status = MatchmakingStatus.searching;
    _statusController.add(_status);

    final myIsWorldwide = isWorldwide(countryFilter);
    final effectiveCountryFilter = myIsWorldwide ? 'Global (Worldwide)' : countryFilter;

    final client = SupabaseService.instance.client;

    if (client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _channel?.unsubscribe();
        _channel = client.channel('monkey_matchmaking_pool');

        _channel!
          ..onPresenceSync((_) {
            _checkPresenceForMatch(myProfile, genderFilter, effectiveCountryFilter);
          })
          ..onBroadcast(
            event: 'match_event_${myProfile.id}',
            callback: (payload) async {
              if (_status != MatchmakingStatus.searching) return;

              final roomId = payload['room_id'] as String;
              final peerId = payload['peer_id'] as String;
              final peerName = payload['peer_name'] as String;
              final peerGender = payload['peer_gender'] as String? ?? 'unspecified';
              final peerCountry = payload['peer_country'] as String? ?? 'Global (Worldwide)';
              final peerCountryFlag = payload['peer_country_flag'] as String? ?? '🌍';
              final token = TokenService.createLiveKitToken(
                roomName: roomId,
                participantId: myProfile.id,
                participantName: myProfile.nickname,
              );

              // Immediately remove from waiting presence pool once paired
              try {
                await _channel?.untrack();
              } catch (_) {}

              _onMatchSuccess(MatchResult(
                roomId: roomId,
                token: token,
                peerId: peerId,
                peerName: peerName,
                peerGender: peerGender,
                peerCountry: peerCountry,
                peerCountryFlag: peerCountryFlag,
              ));
            },
          );

        _channel!.subscribe((status, [error]) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _channel!.track({
              'user_id': myProfile.id,
              'nickname': myProfile.nickname,
              'gender': myProfile.gender,
              'interests': myProfile.interests,
              'country': myProfile.country,
              'country_flag': myProfile.countryCode == 'ALL' ? '🌍' : AppCountry.fromCode(myProfile.countryCode).flag,
              'gender_filter': genderFilter,
              'country_filter': effectiveCountryFilter,
              'is_worldwide': myIsWorldwide,
              'status': 'searching',
              'joined_at': DateTime.now().toIso8601String(),
            });

            // Immediately check for any peer already waiting in the pool
            _checkPresenceForMatch(myProfile, genderFilter, effectiveCountryFilter);
          }
        });

        // Periodic sync scanner (runs every 1.5s while searching to guarantee fast matching across network boundaries)
        _periodicSyncTimer?.cancel();
        _periodicSyncTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
          if (_status == MatchmakingStatus.searching) {
            _checkPresenceForMatch(myProfile, genderFilter, effectiveCountryFilter);
          }
        });

        _searchTimeoutTimer?.cancel();
        if (!myIsWorldwide) {
          _searchTimeoutTimer = Timer(countrySearchTimeout, () {
            if (_status == MatchmakingStatus.searching) {
              _status = MatchmakingStatus.noUsersInCountry;
              _statusController.add(_status);
            }
          });
        } else {
          _searchTimeoutTimer = Timer(globalSearchTimeout, () {
            if (_status == MatchmakingStatus.searching) {
              _status = MatchmakingStatus.noUsersOnline;
              _statusController.add(_status);
            }
          });
        }
        return;
      } catch (e) {
        debugPrint('[MatchmakingService] Realtime queue note: $e.');
      }
    }

    // Fallback: Realtime searching queue when server is offline or initializing
    _searchTimeoutTimer?.cancel();
    if (!myIsWorldwide) {
      _searchTimeoutTimer = Timer(countrySearchTimeout, () {
        if (_status == MatchmakingStatus.searching) {
          _status = MatchmakingStatus.noUsersInCountry;
          _statusController.add(_status);
        }
      });
    } else {
      _searchTimeoutTimer = Timer(globalSearchTimeout, () {
        if (_status == MatchmakingStatus.searching) {
          _status = MatchmakingStatus.noUsersOnline;
          _statusController.add(_status);
        }
      });
    }
  }

  void _checkPresenceForMatch(UserProfile myProfile, String genderFilter, [String countryFilter = 'Global (Worldwide)']) async {
    if (_channel == null || _status != MatchmakingStatus.searching) return;

    final presenceState = _channel!.presenceState();
    final List<Map<String, dynamic>> waitingPeers = [];
    final myIsWorldwide = isWorldwide(countryFilter);

    for (final entry in presenceState) {
      final presences = entry.presences;
      for (final p in presences) {
        final payload = p.payload;
        final peerId = payload['user_id'] as String?;
        if (peerId == null || peerId == myProfile.id) continue;

        // Check if this peer already coordinated and matched with us via presence update
        final matchedWith = payload['matched_with'] as String?;
        final remoteRoomId = payload['room_id'] as String?;
        if (matchedWith == myProfile.id && remoteRoomId != null) {
          final peerName = payload['nickname'] as String? ?? 'Stranger';
          final peerGender = payload['gender'] as String? ?? 'unspecified';
          final peerCountry = payload['country'] as String? ?? 'Global (Worldwide)';
          final peerCountryFlag = payload['country_flag'] as String? ?? '🌍';

          final token = TokenService.createLiveKitToken(
            roomName: remoteRoomId,
            participantId: myProfile.id,
            participantName: myProfile.nickname,
          );

          try {
            await _channel?.untrack();
          } catch (_) {}

          _onMatchSuccess(MatchResult(
            roomId: remoteRoomId,
            token: token,
            peerId: peerId,
            peerName: peerName,
            peerGender: peerGender,
            peerCountry: peerCountry,
            peerCountryFlag: peerCountryFlag,
          ));
          return;
        }

        final peerGender = payload['gender'] as String? ?? 'unspecified';
        final peerFilter = payload['gender_filter'] as String? ?? 'everyone';

        // Check gender compatibility
        final myFilterSatisfied = genderFilter == 'everyone' || genderFilter.toLowerCase() == peerGender.toLowerCase();
        final peerFilterSatisfied = peerFilter == 'everyone' || peerFilter.toLowerCase() == myProfile.gender.toLowerCase();
        if (!myFilterSatisfied || !peerFilterSatisfied) continue;

        // Check country compatibility
        final peerCountry = payload['country'] as String? ?? 'Global (Worldwide)';
        final peerCountryFilter = payload['country_filter'] as String? ?? 'Global (Worldwide)';
        final peerIsWorldwide = isWorldwide(peerCountryFilter);

        bool countrySatisfied = false;
        if (myIsWorldwide && peerIsWorldwide) {
          // If both users selected Worldwide: 100% Guaranteed Match!
          countrySatisfied = true;
        } else if (myIsWorldwide && !peerIsWorldwide) {
          // I want anyone worldwide; peer wants specific country: check if my country matches peer's filter
          final myCountry = myProfile.country.toLowerCase();
          final peerReq = peerCountryFilter.toLowerCase();
          countrySatisfied = myCountry.contains(peerReq) || peerReq.contains(myCountry);
        } else if (!myIsWorldwide && peerIsWorldwide) {
          // Peer wants anyone worldwide; I want specific country: check if peer's country matches my filter
          final peerC = peerCountry.toLowerCase();
          final myReq = countryFilter.toLowerCase();
          countrySatisfied = peerC.contains(myReq) || myReq.contains(peerC);
        } else {
          // Both chose specific countries: check cross-match
          countrySatisfied = peerCountry.toLowerCase().contains(countryFilter.toLowerCase()) &&
              myProfile.country.toLowerCase().contains(peerCountryFilter.toLowerCase());
        }

        if (countrySatisfied) {
          waitingPeers.add(payload);
        }
      }
    }

    if (waitingPeers.isNotEmpty && _status == MatchmakingStatus.searching) {
      final peer = waitingPeers.first;
      final peerId = peer['user_id'] as String;
      final peerName = peer['nickname'] as String? ?? 'Stranger';
      final peerGender = peer['gender'] as String? ?? 'unspecified';
      final peerCountry = peer['country'] as String? ?? 'Global (Worldwide)';
      final peerCountryFlag = peer['country_flag'] as String? ?? '🌍';

      // Deterministic shared room ID (both users calculate the exact same room ID)
      final roomId = generateRoomId(myProfile.id, peerId);

      // Coordinator check to prevent duplicate broadcasts
      if (myProfile.id.compareTo(peerId) < 0) {
        // Broadcast match event to the peer
        await _channel!.sendBroadcastMessage(
          event: 'match_event_$peerId',
          payload: {
            'room_id': roomId,
            'peer_id': myProfile.id,
            'peer_name': myProfile.nickname,
            'peer_gender': myProfile.gender,
            'peer_country': myProfile.country,
            'peer_country_flag': myProfile.countryCode == 'ALL' ? '🌍' : AppCountry.fromCode(myProfile.countryCode).flag,
          },
        );

        // Also update presence payload to announce the match
        try {
          await _channel?.track({
            'user_id': myProfile.id,
            'status': 'matched',
            'matched_with': peerId,
            'room_id': roomId,
          });
        } catch (_) {}

        // Untrack coordinator from waiting pool
        try {
          await _channel?.untrack();
        } catch (_) {}

        final myToken = TokenService.createLiveKitToken(
          roomName: roomId,
          participantId: myProfile.id,
          participantName: myProfile.nickname,
        );

        _onMatchSuccess(MatchResult(
          roomId: roomId,
          token: myToken,
          peerId: peerId,
          peerName: peerName,
          peerGender: peerGender,
          peerCountry: peerCountry,
          peerCountryFlag: peerCountryFlag,
        ));
      }
    }
  }

  void _onMatchSuccess(MatchResult result) {
    _searchTimeoutTimer?.cancel();
    _periodicSyncTimer?.cancel();
    _status = MatchmakingStatus.matched;
    _statusController.add(_status);
    _matchController.add(result);
  }

  Future<void> cancelSearch() async {
    _searchTimeoutTimer?.cancel();
    _periodicSyncTimer?.cancel();
    _status = MatchmakingStatus.idle;
    _statusController.add(_status);
    try {
      await _channel?.untrack();
      await _channel?.unsubscribe();
      _channel = null;
    } catch (_) {}
  }
}

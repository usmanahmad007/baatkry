import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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
  String? _currentSessionId;
  MatchmakingStatus _status = MatchmakingStatus.idle;
  final _statusController = StreamController<MatchmakingStatus>.broadcast();
  final _matchController = StreamController<MatchResult>.broadcast();
  Timer? _searchTimeoutTimer;
  Timer? _periodicSyncTimer;

  MatchmakingStatus get status => _status;
  Stream<MatchmakingStatus> get statusStream => _statusController.stream;
  Stream<MatchResult> get matchStream => _matchController.stream;
  String? get currentSessionId => _currentSessionId;

  /// Helper to test if a country selection is Worldwide / Global
  static bool isWorldwide(String? filter) {
    if (filter == null || filter.trim().isEmpty) return true;
    final f = filter.toLowerCase().trim();
    return f == 'all' || f.contains('global') || f.contains('worldwide');
  }

  /// Generates a deterministic, shared room ID between any two participants so both
  /// are guaranteed to enter the identical LiveKit room.
  static String generateRoomId(String idA, String idB) {
    final first = idA.compareTo(idB) < 0 ? idA : idB;
    final second = idA.compareTo(idB) < 0 ? idB : idA;
    final s1 = first.length > 8 ? first.substring(0, 8) : first;
    final s2 = second.length > 8 ? second.substring(0, 8) : second;
    return 'room_${s1}_$s2';
  }

  /// Start searching for a real live match across any device (Web, Android, iOS),
  /// supporting registered users and non-registered guests alike.
  Future<void> findMatch({
    required UserProfile myProfile,
    String genderFilter = 'everyone',
    String countryFilter = 'Global (Worldwide)',
  }) async {
    _status = MatchmakingStatus.searching;
    _statusController.add(_status);

    final myIsWorldwide = isWorldwide(countryFilter);
    final effectiveCountryFilter = myIsWorldwide ? 'Global (Worldwide)' : countryFilter;

    // Generate unique participant session ID for this search session
    // Guarantees independent presence state even if multiple devices are logged into the same account!
    final clientSessionId = 'sess_${const Uuid().v4().replaceAll('-', '').substring(0, 16)}';
    _currentSessionId = clientSessionId;

    final client = SupabaseService.instance.client;

    if (client != null && AppConfig.isSupabaseConfigured) {
      try {
        if (_channel != null) {
          final old = _channel;
          _channel = null;
          try {
            await old?.untrack();
            await client.removeChannel(old!);
          } catch (_) {}
        }

        // Use clientSessionId as the unique presence key
        _channel = client.channel(
          'monkey_matchmaking_pool',
          opts: RealtimeChannelConfig(
            key: clientSessionId,
          ),
        );

        _channel!
          ..onPresenceSync((_) {
            _checkPresenceForMatch(myProfile, genderFilter, effectiveCountryFilter);
          })
          ..onBroadcast(
            event: 'match_event_$clientSessionId',
            callback: (payload) async {
              if (_status != MatchmakingStatus.searching) return;

              final roomId = payload['room_id'] as String;
              final peerSessionId = payload['peer_session_id'] as String? ?? '';
              final peerUserId = payload['peer_id'] as String? ?? peerSessionId;
              final peerName = payload['peer_name'] as String? ?? 'Stranger';
              final peerGender = payload['peer_gender'] as String? ?? 'unspecified';
              final peerCountry = payload['peer_country'] as String? ?? 'Global (Worldwide)';
              final peerCountryFlag = payload['peer_country_flag'] as String? ?? '🌍';

              // Unique participant ID per device so LiveKit never experiences identity conflicts
              final myParticipantId = '${myProfile.id}_${clientSessionId.substring(5, 13)}';
              final token = TokenService.createLiveKitToken(
                roomName: roomId,
                participantId: myParticipantId,
                participantName: myProfile.nickname,
              );

              _onMatchSuccess(MatchResult(
                roomId: roomId,
                token: token,
                peerId: peerUserId,
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
              'session_id': clientSessionId,
              'user_id': myProfile.id,
              'nickname': myProfile.nickname,
              'is_anonymous': myProfile.isAnonymous,
              'gender': myProfile.gender,
              'interests': myProfile.interests,
              'country': myProfile.country,
              'country_flag': myProfile.countryCode == 'ALL' ? '🌍' : AppCountry.fromCode(myProfile.countryCode).flag,
              'gender_filter': genderFilter,
              'country_filter': effectiveCountryFilter,
              'is_worldwide': myIsWorldwide,
              'status': 'searching',
              'matched_session_id': '',
              'room_id': '',
              'joined_at': DateTime.now().toIso8601String(),
            });

            // Immediately check for any peer already waiting in the pool
            _checkPresenceForMatch(myProfile, genderFilter, effectiveCountryFilter);
          }
        });

        // Periodic sync scanner (runs every 1000ms while searching for instant cross-device detection)
        _periodicSyncTimer?.cancel();
        _periodicSyncTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
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
    final currentSession = _currentSessionId;
    if (_channel == null || _status != MatchmakingStatus.searching || currentSession == null) return;

    final presenceState = _channel!.presenceState();
    final List<Map<String, dynamic>> waitingPeers = [];
    final myIsWorldwide = isWorldwide(countryFilter);

    for (final entry in presenceState) {
      final presences = entry.presences;
      for (final p in presences) {
        final payload = p.payload;
        final peerSessionId = payload['session_id'] as String?;
        // Ignore self session (same device instance)
        if (peerSessionId == null || peerSessionId == currentSession) continue;

        // 1. Check if this peer already coordinated and matched with us via presence update
        final matchedSession = payload['matched_session_id'] as String?;
        final remoteRoomId = payload['room_id'] as String?;
        if (matchedSession == currentSession && remoteRoomId != null && remoteRoomId.isNotEmpty) {
          final peerName = payload['nickname'] as String? ?? 'Stranger';
          final peerGender = payload['gender'] as String? ?? 'unspecified';
          final peerCountry = payload['country'] as String? ?? 'Global (Worldwide)';
          final peerCountryFlag = payload['country_flag'] as String? ?? '🌍';
          final peerUserId = payload['user_id'] as String? ?? peerSessionId;

          final myParticipantId = '${myProfile.id}_${currentSession.substring(5, 13)}';
          final token = TokenService.createLiveKitToken(
            roomName: remoteRoomId,
            participantId: myParticipantId,
            participantName: myProfile.nickname,
          );

          _onMatchSuccess(MatchResult(
            roomId: remoteRoomId,
            token: token,
            peerId: peerUserId,
            peerName: peerName,
            peerGender: peerGender,
            peerCountry: peerCountry,
            peerCountryFlag: peerCountryFlag,
          ));
          return;
        }

        // 2. Ignore peers that are already matched with someone else
        final peerStatus = payload['status'] as String? ?? 'searching';
        if (peerStatus != 'searching') continue;

        // 3. Gender compatibility check (both registered and non-registered guests)
        final peerGender = payload['gender'] as String? ?? 'unspecified';
        final peerFilter = (payload['gender_filter'] as String? ?? 'everyone').toLowerCase();
        final myFilter = genderFilter.toLowerCase();
        final myGender = myProfile.gender.toLowerCase();

        final myFilterSatisfied = myFilter == 'everyone' || myFilter == peerGender.toLowerCase();
        final peerFilterSatisfied = peerFilter == 'everyone' || peerFilter == myGender;
        if (!myFilterSatisfied || !peerFilterSatisfied) continue;

        // 4. Country compatibility check (Worldwide matches any user, specific country matches requested country)
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
      final peerSessionId = peer['session_id'] as String;
      final peerUserId = peer['user_id'] as String? ?? peerSessionId;
      final peerName = peer['nickname'] as String? ?? 'Stranger';
      final peerGender = peer['gender'] as String? ?? 'unspecified';
      final peerCountry = peer['country'] as String? ?? 'Global (Worldwide)';
      final peerCountryFlag = peer['country_flag'] as String? ?? '🌍';

      // Deterministic shared room ID based on unique session IDs
      final roomId = generateRoomId(currentSession, peerSessionId);

      // Coordinator check: the session with smaller alphabetical ID coordinates
      if (currentSession.compareTo(peerSessionId) < 0) {
        // 1. Broadcast match event to the peer
        await _channel!.sendBroadcastMessage(
          event: 'match_event_$peerSessionId',
          payload: {
            'room_id': roomId,
            'peer_session_id': currentSession,
            'peer_id': myProfile.id,
            'peer_name': myProfile.nickname,
            'peer_gender': myProfile.gender,
            'peer_country': myProfile.country,
            'peer_country_flag': myProfile.countryCode == 'ALL' ? '🌍' : AppCountry.fromCode(myProfile.countryCode).flag,
          },
        );

        // 2. Also update presence payload to announce the match so peer can sync if broadcast was missed
        try {
          await _channel?.track({
            'session_id': currentSession,
            'user_id': myProfile.id,
            'nickname': myProfile.nickname,
            'status': 'matched',
            'matched_session_id': peerSessionId,
            'room_id': roomId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        } catch (_) {}

        final myParticipantId = '${myProfile.id}_${currentSession.substring(5, 13)}';
        final myToken = TokenService.createLiveKitToken(
          roomName: roomId,
          participantId: myParticipantId,
          participantName: myProfile.nickname,
        );

        _onMatchSuccess(MatchResult(
          roomId: roomId,
          token: myToken,
          peerId: peerUserId,
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

    // Give remote peer 2 seconds to read presence state before leaving channel
    final ch = _channel;
    Timer(const Duration(seconds: 2), () async {
      try {
        await ch?.untrack();
      } catch (_) {}
    });
  }

  Future<void> cancelSearch() async {
    _searchTimeoutTimer?.cancel();
    _periodicSyncTimer?.cancel();
    _status = MatchmakingStatus.idle;
    _statusController.add(_status);
    final ch = _channel;
    _channel = null;
    _currentSessionId = null;
    if (ch != null) {
      try {
        await ch.untrack();
        final client = SupabaseService.instance.client;
        if (client != null) {
          await client.removeChannel(ch);
        } else {
          await ch.unsubscribe();
        }
      } catch (_) {}
    }
  }
}

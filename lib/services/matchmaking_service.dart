import 'dart:async';
import 'dart:math';
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

class MatchmakingService {
  static final MatchmakingService instance = MatchmakingService._internal();
  MatchmakingService._internal();

  RealtimeChannel? _channel;
  MatchmakingStatus _status = MatchmakingStatus.idle;
  final _statusController = StreamController<MatchmakingStatus>.broadcast();
  final _matchController = StreamController<MatchResult>.broadcast();
  Timer? _searchTimeoutTimer;

  MatchmakingStatus get status => _status;
  Stream<MatchmakingStatus> get statusStream => _statusController.stream;
  Stream<MatchResult> get matchStream => _matchController.stream;

  /// Start searching for a match.
  /// Free users get 'everyone' (random).
  /// Paid users can select 'men', 'women', or 'transgender'.
  Future<void> findMatch({
    required UserProfile myProfile,
    String genderFilter = 'everyone',
    String countryFilter = 'Global (Worldwide)',
  }) async {
    _status = MatchmakingStatus.searching;
    _statusController.add(_status);

    final client = SupabaseService.instance.client;

    if (client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _channel?.unsubscribe();
        _channel = client.channel('monkey_matchmaking_pool');

        _channel!
          ..onPresenceSync((_) {
            _checkPresenceForMatch(myProfile, genderFilter);
          })
          ..onBroadcast(
            event: 'match_event_${myProfile.id}',
            callback: (payload) {
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
              'gender_filter': genderFilter,
              'country_filter': countryFilter,
              'joined_at': DateTime.now().toIso8601String(),
            });
          }
        });

        // Timeout fallback for testing when developing alone
        _searchTimeoutTimer?.cancel();
        _searchTimeoutTimer = Timer(const Duration(seconds: 4), () {
          if (_status == MatchmakingStatus.searching) {
            _createSimulatedMatch(myProfile, genderFilter, countryFilter);
          }
        });
        return;
      } catch (e) {
        debugPrint('[MatchmakingService] Realtime queue note: $e. Using local match generator.');
      }
    }

    // Local / Offline Simulation for testing without server backend
    _searchTimeoutTimer?.cancel();
    _searchTimeoutTimer = Timer(const Duration(milliseconds: 2200), () {
      if (_status == MatchmakingStatus.searching) {
        _createSimulatedMatch(myProfile, genderFilter, countryFilter);
      }
    });
  }

  void _checkPresenceForMatch(UserProfile myProfile, String genderFilter) {
    if (_channel == null || _status != MatchmakingStatus.searching) return;

    final presenceState = _channel!.presenceState();
    final List<Map<String, dynamic>> waitingPeers = [];

    for (final entry in presenceState) {
      final presences = entry.presences;
      for (final p in presences) {
        final payload = p.payload;
        final peerId = payload['user_id'] as String?;
        final peerGender = payload['gender'] as String? ?? 'unspecified';
        final peerFilter = payload['gender_filter'] as String? ?? 'everyone';

        if (peerId != null && peerId != myProfile.id) {
          // Check mutual filter compatibility
          final myFilterSatisfied = genderFilter == 'everyone' || genderFilter == peerGender;
          final peerFilterSatisfied = peerFilter == 'everyone' || peerFilter == myProfile.gender;

          if (myFilterSatisfied && peerFilterSatisfied) {
            waitingPeers.add(payload);
          }
        }
      }
    }

    if (waitingPeers.isNotEmpty) {
      Map<String, dynamic> peer;
      // If user is in guest mode, show 60% girls and 40% other
      if (myProfile.isAnonymous && genderFilter == 'everyone') {
        final womenPeers = waitingPeers.where((p) => p['gender'] == 'women').toList();
        final otherPeers = waitingPeers.where((p) => p['gender'] != 'women').toList();
        if (womenPeers.isNotEmpty && (Random().nextDouble() < 0.60 || otherPeers.isEmpty)) {
          peer = womenPeers[Random().nextInt(womenPeers.length)];
        } else if (otherPeers.isNotEmpty) {
          peer = otherPeers[Random().nextInt(otherPeers.length)];
        } else {
          peer = waitingPeers.first;
        }
      } else {
        peer = waitingPeers.first;
      }

      final peerId = peer['user_id'] as String;
      final peerName = peer['nickname'] as String? ?? 'Stranger';
      final peerGender = peer['gender'] as String? ?? 'unspecified';

      // Deterministic coordinator
      if (myProfile.id.compareTo(peerId) < 0) {
        final roomId = 'room_${myProfile.id.substring(0, 4)}_${peerId.substring(0, 4)}_${DateTime.now().millisecondsSinceEpoch}';

        _channel!.sendBroadcastMessage(
          event: 'match_event_$peerId',
          payload: {
            'room_id': roomId,
            'peer_id': myProfile.id,
            'peer_name': myProfile.nickname,
            'peer_gender': myProfile.gender,
          },
        );

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
        ));
      }
    }
  }

  void _createSimulatedMatch(UserProfile myProfile, String genderFilter, [String countryFilter = 'Global (Worldwide)']) {
    final namesMen = ['Rajat kumar', 'Alex', 'Jordan', 'Sam', 'Lucas', 'Ali', 'Hamza', 'Daniel', 'Marcus', 'Leo'];
    final namesWomen = ['Sophia', 'Elena', 'Priya', 'Chloe', 'Zoe', 'Ayesha', 'Sara', 'Fatima', 'Jessica', 'Maria', 'Emily', 'Camila'];
    final namesTrans = ['Taylor', 'River', 'Morgan', 'Casey', 'Rowan'];

    List<String> pool;
    String targetGender;

    if (genderFilter == 'men') {
      pool = namesMen;
      targetGender = 'men';
    } else if (genderFilter == 'women') {
      pool = namesWomen;
      targetGender = 'women';
    } else if (genderFilter == 'transgender') {
      pool = namesTrans;
      targetGender = 'transgender';
    } else {
      // Free / Random matching:
      // STRICT REQUIREMENT: If user is in guest mode, show 60% girls and 40% other
      if (myProfile.isAnonymous) {
        final randomVal = Random().nextDouble();
        if (randomVal < 0.60) {
          // 60% probability for girls/women
          pool = namesWomen;
          targetGender = 'women';
        } else {
          // 40% probability for other (men or transgender)
          final otherVal = Random().nextDouble();
          if (otherVal < 0.75) {
            pool = namesMen;
            targetGender = 'men';
          } else {
            pool = namesTrans;
            targetGender = 'transgender';
          }
        }
      } else {
        // Logged-in Google user in random mode: balanced distribution
        final randomVal = Random().nextDouble();
        if (randomVal < 0.50) {
          pool = namesWomen;
          targetGender = 'women';
        } else if (randomVal < 0.85) {
          pool = namesMen;
          targetGender = 'men';
        } else {
          pool = namesTrans;
          targetGender = 'transgender';
        }
      }
    }

    AppCountry matchedCountry;
    if (countryFilter.isNotEmpty && !countryFilter.toLowerCase().contains('global') && countryFilter != 'ALL') {
      matchedCountry = AppCountry.fromName(countryFilter);
    } else {
      // Pick random from top popular countries (excluding the global ALL option)
      final specificCountries = kPopularCountries.where((c) => c.code != 'ALL').toList();
      matchedCountry = specificCountries[Random().nextInt(specificCountries.length)];
    }

    final randomName = pool[Random().nextInt(pool.length)];
    final simulatedPeerId = const Uuid().v4();
    final roomId = 'demo_room_${DateTime.now().millisecondsSinceEpoch}';

    final token = TokenService.createLiveKitToken(
      roomName: roomId,
      participantId: myProfile.id,
      participantName: myProfile.nickname,
    );

    _onMatchSuccess(MatchResult(
      roomId: roomId,
      token: token,
      peerId: simulatedPeerId,
      peerName: randomName,
      peerGender: targetGender,
      peerCountry: matchedCountry.name,
      peerCountryFlag: matchedCountry.flag,
      commonInterests: myProfile.interests.isNotEmpty ? [myProfile.interests.first] : ['Music'],
    ));
  }

  void _onMatchSuccess(MatchResult result) {
    _searchTimeoutTimer?.cancel();
    _status = MatchmakingStatus.matched;
    _statusController.add(_status);
    _matchController.add(result);
  }

  Future<void> cancelSearch() async {
    _searchTimeoutTimer?.cancel();
    _status = MatchmakingStatus.idle;
    _statusController.add(_status);
    try {
      await _channel?.untrack();
      await _channel?.unsubscribe();
      _channel = null;
    } catch (_) {}
  }
}

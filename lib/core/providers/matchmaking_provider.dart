import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/matchmaking_service.dart';

final matchmakingServiceProvider = Provider<MatchmakingService>((ref) {
  return MatchmakingService.instance;
});

/// Streams active matchmaking status transitions
final matchmakingStatusProvider = StreamProvider<MatchmakingStatus>((ref) {
  final service = ref.watch(matchmakingServiceProvider);
  return service.statusStream;
});

/// Streams match success results with LiveKit token and room info
final matchResultProvider = StreamProvider<MatchResult>((ref) {
  final service = ref.watch(matchmakingServiceProvider);
  return service.matchStream;
});

/// Synchronous access to current matchmaking status
final currentMatchmakingStatusProvider = Provider<MatchmakingStatus>((ref) {
  return ref.watch(matchmakingServiceProvider).status;
});

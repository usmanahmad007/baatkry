import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/presence_service.dart';

final presenceServiceProvider = Provider<PresenceService>((ref) {
  return PresenceService.instance;
});

/// Streams real-time global live online user count
final liveUsersCountProvider = StreamProvider<int>((ref) {
  final service = ref.watch(presenceServiceProvider);
  return service.liveUsersCountStream;
});

/// Synchronous access to current live online user count
final currentLiveUsersCountProvider = Provider<int>((ref) {
  final streamCount = ref.watch(liveUsersCountProvider).valueOrNull;
  return streamCount ?? ref.watch(presenceServiceProvider).totalLiveUsersCount;
});

/// Streams real-time per-country user counts for the interactive globe and map
final countryCountsProvider = StreamProvider<Map<String, int>>((ref) {
  final service = ref.watch(presenceServiceProvider);
  return service.countryCountsStream;
});

/// Synchronous access to country distribution counts
final currentCountryCountsProvider = Provider<Map<String, int>>((ref) {
  final streamMap = ref.watch(countryCountsProvider).valueOrNull;
  return streamMap ?? ref.watch(presenceServiceProvider).countryCounts;
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_profile.dart';
import '../../services/supabase_service.dart';

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService.instance;
});

/// Streams user profile updates in real-time (e.g. login, logout, coin changes, VIP status)
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final service = ref.watch(supabaseServiceProvider);
  return service.profileStream;
});

/// Synchronous access to current profile, falling back to stream's latest value
final currentProfileProvider = Provider<UserProfile?>((ref) {
  final streamValue = ref.watch(userProfileProvider).valueOrNull;
  return streamValue ?? ref.watch(supabaseServiceProvider).currentProfile;
});

/// Whether the current user is authenticated (not anonymous)
final isAuthenticatedProvider = Provider<bool>((ref) {
  final profile = ref.watch(currentProfileProvider);
  return profile != null && !profile.isAnonymous;
});

/// Whether the user is an anonymous guest
final isGuestProvider = Provider<bool>((ref) {
  final profile = ref.watch(currentProfileProvider);
  return profile == null || profile.isAnonymous;
});

/// Current live coin balance
final userCoinsProvider = Provider<int>((ref) {
  final profile = ref.watch(currentProfileProvider);
  return profile?.coins ?? 0;
});

/// Whether user has claimed joining bonus
final hasUsedJoiningBonusProvider = Provider<bool>((ref) {
  return ref.watch(supabaseServiceProvider).hasUsedJoiningBonus;
});

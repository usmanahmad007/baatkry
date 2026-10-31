import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/creator_application.dart';
import '../../models/creator_profile.dart';
import '../../services/supabase_service.dart';
import 'user_provider.dart';

/// Checks if current logged-in user is an approved creator
final isCreatorProvider = FutureProvider<bool>((ref) async {
  final profile = ref.watch(userProfileProvider).valueOrNull;
  if (profile == null || profile.isAnonymous) return false;
  return SupabaseService.instance.checkIsCreator(profile.id);
});

/// Fetches the latest creator application for the active user
final myCreatorApplicationProvider = FutureProvider<CreatorApplication?>((ref) async {
  final profile = ref.watch(userProfileProvider).valueOrNull;
  if (profile == null || profile.isAnonymous) return null;
  return SupabaseService.instance.fetchMyCreatorApplication();
});

/// Fetches public creator profile for a specific creator ID
final creatorProfileProvider = FutureProvider.family<CreatorProfile?, String>((ref, creatorId) async {
  if (creatorId.isEmpty) return null;
  return SupabaseService.instance.fetchCreatorProfile(creatorId);
});

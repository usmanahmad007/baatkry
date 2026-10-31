import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/commission_rule.dart';
import '../../models/creator_application.dart';
import '../../models/creator_earning_entry.dart';
import '../../models/creator_profile.dart';
import '../../models/creator_wallet.dart';
import '../../models/creator_withdrawal.dart';
import '../../models/payout_account.dart';
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

/// Real-time stream of the current creator's earnings wallet
final creatorWalletStreamProvider = StreamProvider<CreatorWallet?>((ref) {
  return SupabaseService.instance.creatorWalletStream;
});

/// Fetches creator's real-money wallet
final creatorWalletProvider = FutureProvider<CreatorWallet?>((ref) async {
  final profile = ref.watch(userProfileProvider).valueOrNull;
  if (profile == null || profile.isAnonymous) return null;
  return SupabaseService.instance.fetchCreatorWallet(profile.id);
});

/// Fetches creator's itemized gift earnings ledger
final creatorEarningsProvider = FutureProvider<List<CreatorEarningEntry>>((ref) async {
  final profile = ref.watch(userProfileProvider).valueOrNull;
  if (profile == null || profile.isAnonymous) return [];
  return SupabaseService.instance.fetchCreatorEarnings();
});

/// Fetches active platform commission rules
final activeCommissionRuleProvider = FutureProvider<CommissionRule>((ref) async {
  return SupabaseService.instance.fetchActiveCommissionRule();
});

/// Fetches creator's registered payout accounts (PayPal, Bank, Crypto, etc.)
final creatorPayoutAccountsProvider = FutureProvider<List<PayoutAccount>>((ref) async {
  return SupabaseService.instance.fetchCreatorPayoutAccounts();
});

/// Fetches creator's personal withdrawal payout history and live tracking status
final creatorMyWithdrawalsProvider = FutureProvider<List<CreatorWithdrawal>>((ref) async {
  return SupabaseService.instance.fetchCreatorMyWithdrawals();
});


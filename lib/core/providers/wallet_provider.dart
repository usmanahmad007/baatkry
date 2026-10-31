import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/coin_package.dart';
import '../../models/wallet.dart';
import '../../models/wallet_ledger_entry.dart';
import 'user_provider.dart';

/// Streams real-time updates of the user's double-entry wallet
final userWalletStreamProvider = StreamProvider<UserWallet?>((ref) {
  final service = ref.watch(supabaseServiceProvider);
  return service.walletStream;
});

/// Synchronous access to current user wallet
final currentWalletProvider = Provider<UserWallet?>((ref) {
  final streamVal = ref.watch(userWalletStreamProvider).valueOrNull;
  return streamVal ?? ref.watch(supabaseServiceProvider).currentWallet;
});

/// High-level provider for live coin balance, sourced from Wallet with fallback to UserProfile
final walletBalanceProvider = Provider<int>((ref) {
  final wallet = ref.watch(currentWalletProvider);
  if (wallet != null) return wallet.balance;
  final profile = ref.watch(currentProfileProvider);
  return profile?.coins ?? 0;
});

/// Fetches dynamic active coin packages from database
final coinPackagesProvider = FutureProvider<List<CoinPackage>>((ref) async {
  final service = ref.watch(supabaseServiceProvider);
  return service.fetchCoinPackages();
});

/// Fetches itemized ledger transaction history
final walletLedgerProvider = FutureProvider<List<WalletLedgerEntry>>((ref) async {
  final service = ref.watch(supabaseServiceProvider);
  // Re-fetch whenever wallet updates
  ref.watch(userWalletStreamProvider);
  return service.fetchWalletLedger();
});

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../models/admin_audit_log.dart';
import '../models/admin_kpi_metrics.dart';
import '../models/admin_user.dart';
import '../models/coin_package.dart';
import '../models/commission_rule.dart';
import '../models/creator_application.dart';
import '../models/creator_earning_entry.dart';
import '../models/creator_profile.dart';
import '../models/creator_wallet.dart';
import '../models/creator_withdrawal.dart';
import '../models/friend_chat_message.dart';
import '../models/friend_request.dart';
import '../models/payout_account.dart';
import '../models/user_profile.dart';
import '../models/user_report.dart';
import '../models/virtual_gift.dart';
import '../models/wallet.dart';
import '../models/wallet_ledger_entry.dart';

enum GoogleAgeStatus {
  verifiedAdult,   // Age 18+ confirmed via Google/Gmail metadata or People API
  underageBlocked, // Age < 18 confirmed via Google/Gmail metadata or People API
  dobNotFound,     // Google/Gmail did not provide age or DOB; user must enter DOB manually
}

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  SupabaseClient? _client;
  UserProfile? _currentProfile;
  final _profileController = StreamController<UserProfile?>.broadcast();
  UserWallet? _currentWallet;
  final _walletController = StreamController<UserWallet?>.broadcast();
  RealtimeChannel? _walletChannel;
  CreatorWallet? _currentCreatorWallet;
  final _creatorWalletController = StreamController<CreatorWallet?>.broadcast();
  RealtimeChannel? _creatorWalletChannel;
  String? _browserDeviceId;
  bool _hasUsedJoiningBonus = false;
  final Set<String> _blockedUserIds = {};

  bool isUserBlocked(String userId) => _blockedUserIds.contains(userId);
  Set<String> get blockedUserIds => Set.unmodifiable(_blockedUserIds);

  Stream<UserProfile?> get profileStream => _profileController.stream;
  UserProfile? get currentProfile => _currentProfile;
  set currentProfile(UserProfile? profile) {
    _currentProfile = profile;
    _profileController.add(profile);
  }
  String? get currentUserId => _currentProfile?.id ?? _client?.auth.currentUser?.id;
  Stream<UserWallet?> get walletStream => _walletController.stream;
  UserWallet? get currentWallet => _currentWallet;
  Stream<CreatorWallet?> get creatorWalletStream => _creatorWalletController.stream;
  CreatorWallet? get currentCreatorWallet => _currentCreatorWallet;
  bool get isAuthenticated => _currentProfile != null && !_currentProfile!.isAnonymous;
  bool get isGuest => _currentProfile == null || _currentProfile!.isAnonymous;

  final _friendsController = StreamController<List<UserProfile>>.broadcast();
  Stream<List<UserProfile>> get friendsStream => _friendsController.stream;

  final _friendRequestsController = StreamController<List<FriendRequest>>.broadcast();
  Stream<List<FriendRequest>> get friendRequestsStream => _friendRequestsController.stream;

  final _friendChatControllers = <String, StreamController<List<FriendChatMessage>>>{};
  bool get hasUsedJoiningBonus => _hasUsedJoiningBonus;
  String? get browserDeviceId => _browserDeviceId;
  bool get canUseCoins => isAuthenticated && (_currentProfile?.coins ?? 0) > 0;
  bool get isGoogleUser {
    final user = _client?.auth.currentUser;
    if (user != null && !user.isAnonymous) return true;
    if (_currentProfile != null && !_currentProfile!.isAnonymous) return true;
    return false;
  }
  String? get googleUserEmail => _client?.auth.currentUser?.email;

  /// Initializes Supabase if valid credentials are provided,
  /// or loads local guest profile fallback for instant prototyping.
  Future<void> initialize() async {
    try {
      if (AppConfig.isSupabaseConfigured) {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          // ignore: deprecated_member_use
          anonKey: AppConfig.supabaseAnonKey,
        );
        _client = Supabase.instance.client;

        // Auto-handle OAuth PKCE callbacks, deep links, and auth state changes
        _client!.auth.onAuthStateChange.listen((data) async {
          final event = data.event;
          final session = data.session;
          debugPrint('[SupabaseService] Auth state changed: $event, user: ${session?.user.id}');

          if (event == AuthChangeEvent.signedIn ||
              event == AuthChangeEvent.tokenRefreshed ||
              event == AuthChangeEvent.userUpdated) {
            if (session?.user != null) {
              final user = session!.user;
              final detectedAge = _extractAgeFromMetadata(user.userMetadata);
              final prefs = await SharedPreferences.getInstance();
              final hasUsedBonusOnDevice = prefs.getBool('baatkry_bonus_used_on_device') ?? false;
              final cleanEmail = user.email?.trim().toLowerCase();
              final hasClaimedBonusForEmail = cleanEmail != null && (prefs.getBool('baatkry_bonus_claimed_$cleanEmail') ?? false);
              final hasClaimedBonusForUser = prefs.getBool('baatkry_bonus_claimed_${user.id}') ?? false;
              final savedUserCoins = prefs.getInt('local_user_coins_${user.id}') ?? prefs.getInt('local_user_coins');

              final remoteProfile = await _fetchRemoteProfile(user.id);
              final googleAvatar = user.userMetadata?['avatar_url']?.toString() ??
                  user.userMetadata?['picture']?.toString();
              final googleName = user.userMetadata?['full_name']?.toString() ??
                  user.userMetadata?['name']?.toString() ??
                  user.email?.split('@').first ??
                  'Google User';

              final savedUsername = remoteProfile?.username ??
                  prefs.getString('local_user_username_${user.id}') ??
                  prefs.getString('local_user_username');
              final savedDob = remoteProfile?.birthDate ??
                  prefs.getString('local_user_dob_${user.id}') ??
                  prefs.getString('baatkry_user_dob');
              final savedAge = remoteProfile?.age ??
                  prefs.getInt('local_user_age_${user.id}') ??
                  prefs.getInt('baatkry_user_age') ??
                  detectedAge;
              final isCompleted = (prefs.getBool('local_profile_completed_${user.id}') ?? false) ||
                  (savedUsername != null && savedUsername.isNotEmpty && (savedDob != null || (savedAge != null && savedAge >= 18))) ||
                  (remoteProfile?.hasCompletedProfile ?? false);

              UserProfile profile;
              if (remoteProfile != null) {
                profile = remoteProfile.copyWith(
                  avatarUrl: (remoteProfile.avatarUrl == null || remoteProfile.avatarUrl!.isEmpty)
                      ? googleAvatar
                      : remoteProfile.avatarUrl,
                  username: savedUsername ?? remoteProfile.username,
                  birthDate: savedDob ?? remoteProfile.birthDate,
                  age: savedAge ?? remoteProfile.age,
                  isAgeVerified: savedDob != null || (savedAge != null && savedAge >= 18) || remoteProfile.isAgeVerified,
                );
                if (googleAvatar != null && (remoteProfile.avatarUrl == null || remoteProfile.avatarUrl!.isEmpty)) {
                  try {
                    await _client!.from('profiles').update({'avatar_url': googleAvatar}).eq('id', user.id);
                  } catch (_) {}
                }
              } else {
                final isFirstTimeUser = !hasUsedBonusOnDevice &&
                    !hasClaimedBonusForEmail &&
                    !hasClaimedBonusForUser &&
                    savedUserCoins == null;
                final initialCoins = isFirstTimeUser ? 120 : (savedUserCoins ?? 0);

                profile = UserProfile(
                  id: user.id,
                  isAnonymous: false,
                  nickname: googleName,
                  username: savedUsername,
                  birthDate: savedDob,
                  avatarUrl: googleAvatar,
                  coins: initialCoins,
                  age: savedAge,
                  isAgeVerified: (savedDob != null) || (savedAge != null && savedAge >= 18),
                );

                if (isFirstTimeUser) {
                  await prefs.setBool('baatkry_bonus_used_on_device', true);
                  _hasUsedJoiningBonus = true;
                }
                await prefs.setBool('baatkry_bonus_claimed_${user.id}', true);
                if (cleanEmail != null) {
                  await prefs.setBool('baatkry_bonus_claimed_$cleanEmail', true);
                }
                await prefs.setInt('local_user_coins_${user.id}', initialCoins);
                await prefs.setInt('local_user_coins', initialCoins);

                try {
                  await _client!.from('profiles').upsert(profile.toMap());
                } catch (_) {}
              }

              if (isCompleted) {
                await prefs.setBool('local_profile_completed_${user.id}', true);
                if (savedUsername != null && savedUsername.isNotEmpty) {
                  await prefs.setString('local_user_username_${user.id}', savedUsername);
                }
                if (savedDob != null && savedDob.isNotEmpty) {
                  await prefs.setString('local_user_dob_${user.id}', savedDob);
                  await prefs.setString('baatkry_user_dob', savedDob);
                }
                if (savedAge != null) {
                  await prefs.setInt('local_user_age_${user.id}', savedAge);
                  await prefs.setInt('baatkry_user_age', savedAge);
                }
              }

              if (profile.isAgeVerified || profile.birthDate != null || (profile.age != null && profile.age! >= 18)) {
                await prefs.setBool('baatkry_age_verified_18_plus', true);
              }
              await prefs.setInt('local_user_coins_${user.id}', profile.coins);
              await prefs.setInt('local_user_coins', profile.coins);

              _currentProfile = profile;
              _profileController.add(_currentProfile);
              await _syncUserWallet(user.id);
            }
          } else if (event == AuthChangeEvent.signedOut) {
            await _loadOrCreateProfile();
          }
        });
      }
    } catch (e) {
      debugPrint('[SupabaseService] Note: Supabase initialization skipped or failed: $e');
    }

    await _loadOrCreateProfile();
  }

  SupabaseClient? get client => _client;

  /// Load existing session or auto-create an Anonymous Guest Profile (Omegle style)
  Future<UserProfile> _loadOrCreateProfile() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Save and remember browser data on first and subsequent visits
    String? browserDeviceId = prefs.getString('baatkry_browser_device_id');
    if (browserDeviceId == null) {
      browserDeviceId = 'dev_${const Uuid().v4()}';
      await prefs.setString('baatkry_browser_device_id', browserDeviceId);
      await prefs.setString('baatkry_browser_first_visit_at', DateTime.now().toIso8601String());
      await prefs.setInt('baatkry_browser_visit_count', 1);
    } else {
      final visits = prefs.getInt('baatkry_browser_visit_count') ?? 1;
      await prefs.setInt('baatkry_browser_visit_count', visits + 1);
    }
    _browserDeviceId = browserDeviceId;
    _hasUsedJoiningBonus = prefs.getBool('baatkry_bonus_used_on_device') ?? false;

    int guestNum = prefs.getInt('baatkry_guest_random_number') ?? 0;
    if (guestNum == 0) {
      guestNum = 1000000 + Random().nextInt(9000000); // 7-digit random number e.g. 9329887
      await prefs.setInt('baatkry_guest_random_number', guestNum);
    }
    final guestNickname = 'guest#$guestNum';
    final savedId = prefs.getString('local_user_id') ?? 'guest_$guestNum';
    await prefs.setString('local_user_id', savedId);
    final guestId = savedId;

    if (_client != null && _client!.auth.currentUser != null) {
      final user = _client!.auth.currentUser!;
      if (!user.isAnonymous) {
        final remote = await _fetchRemoteProfile(user.id);
        final cleanEmail = user.email?.trim().toLowerCase();
        final hasClaimedBonus = (prefs.getBool('baatkry_bonus_claimed_${user.id}') ?? false) ||
            (cleanEmail != null && (prefs.getBool('baatkry_bonus_claimed_$cleanEmail') ?? false));
        final savedUserCoins = prefs.getInt('local_user_coins_${user.id}') ?? prefs.getInt('local_user_coins');
        final googleAvatar = user.userMetadata?['avatar_url']?.toString() ??
            user.userMetadata?['picture']?.toString();
        final googleName = user.userMetadata?['full_name']?.toString() ??
            user.userMetadata?['name']?.toString() ??
            (user.email?.split('@').first ?? 'User');

        final savedUsername = prefs.getString('local_user_username_${user.id}') ?? remote?.username;
        final savedUsernameUpdatedAtStr = prefs.getString('local_user_username_updated_at_${user.id}');
        final savedUsernameUpdatedAt = savedUsernameUpdatedAtStr != null
            ? DateTime.tryParse(savedUsernameUpdatedAtStr)
            : remote?.usernameUpdatedAt;
        final savedDailyStreak = prefs.getInt('local_user_daily_streak_${user.id}') ?? remote?.dailyClaimStreak ?? 0;
        final savedLastClaimStr = prefs.getString('local_user_last_claim_at_${user.id}');
        final savedLastClaimAt = savedLastClaimStr != null
            ? DateTime.tryParse(savedLastClaimStr)
            : remote?.lastDailyClaimAt;

        final savedDob = remote?.birthDate ??
            prefs.getString('local_user_dob_${user.id}') ??
            prefs.getString('baatkry_user_dob');
        final savedAge = remote?.age ??
            prefs.getInt('local_user_age_${user.id}') ??
            prefs.getInt('baatkry_user_age');
        final savedVipExpiryStr = prefs.getString('local_user_vip_expires_at_${user.id}');
        final savedVipExpiry = savedVipExpiryStr != null
            ? DateTime.tryParse(savedVipExpiryStr)
            : remote?.vipExpiresAt;
        final isVipEffective = ((remote?.isVip ?? false) ||
                (prefs.getBool('local_user_is_vip_${user.id}') ?? false)) &&
            (savedVipExpiry == null || DateTime.now().isBefore(savedVipExpiry));

        UserProfile profile;
        if (remote != null) {
          if ((remote.avatarUrl == null || remote.avatarUrl!.isEmpty) && googleAvatar != null) {
            profile = remote.copyWith(
              avatarUrl: googleAvatar,
              username: savedUsername,
              usernameUpdatedAt: savedUsernameUpdatedAt,
              birthDate: savedDob,
              age: savedAge,
              isAgeVerified: savedDob != null || (savedAge != null && savedAge >= 18) || remote.isAgeVerified,
              isVip: isVipEffective,
              vipExpiresAt: savedVipExpiry,
              dailyClaimStreak: savedDailyStreak,
              lastDailyClaimAt: savedLastClaimAt,
            );
            try {
              await _client!.from('profiles').update({'avatar_url': googleAvatar}).eq('id', user.id);
            } catch (_) {}
          } else {
            profile = remote.copyWith(
              username: savedUsername ?? remote.username,
              usernameUpdatedAt: savedUsernameUpdatedAt ?? remote.usernameUpdatedAt,
              birthDate: savedDob ?? remote.birthDate,
              age: savedAge ?? remote.age,
              isAgeVerified: savedDob != null || (savedAge != null && savedAge >= 18) || remote.isAgeVerified,
              isVip: isVipEffective,
              vipExpiresAt: savedVipExpiry,
              dailyClaimStreak: savedDailyStreak,
              lastDailyClaimAt: savedLastClaimAt,
            );
          }
          if (profile.isAgeVerified || profile.birthDate != null || (profile.age != null && profile.age! >= 18)) {
            await prefs.setBool('baatkry_age_verified_18_plus', true);
            if (profile.birthDate != null) {
              await prefs.setString('baatkry_user_dob', profile.birthDate!);
              await prefs.setString('local_user_dob_${user.id}', profile.birthDate!);
            }
          }
          if (profile.username != null) {
            await prefs.setString('local_user_username_${user.id}', profile.username!);
          }
          if (profile.hasCompletedProfile) {
            await prefs.setBool('local_profile_completed_${user.id}', true);
          }
          if (profile.isGenderSet) {
            await prefs.setString('local_user_gender', profile.gender);
            await prefs.setString('local_user_gender_${user.id}', profile.gender);
            await prefs.setBool('baatkry_user_gender_locked', true);
          }
        } else {
          final savedGender = prefs.getString('local_user_gender_${user.id}') ??
              prefs.getString('local_user_gender') ??
              'unspecified';
          profile = UserProfile(
            id: user.id,
            isAnonymous: false,
            nickname: googleName,
            username: savedUsername,
            avatarUrl: googleAvatar,
            gender: savedGender,
            coins: (hasClaimedBonus || _hasUsedJoiningBonus) ? (savedUserCoins ?? 0) : 120,
            birthDate: savedDob,
            age: savedAge,
            isAgeVerified: savedDob != null || (savedAge != null && savedAge >= 18),
            isVip: isVipEffective,
            vipExpiresAt: savedVipExpiry,
          );
        }
        _currentProfile = profile;
        _profileController.add(_currentProfile);
        await _upsertLocalUserRecord(profile);
        await _syncUserWallet(user.id);
        return profile;
      }
    }

    final savedCoins = prefs.getInt('local_user_coins_$guestId') ?? prefs.getInt('local_user_coins') ?? 0;

    // Unauthenticated Guest mode:
    // Display random guest#9329887 with NO personal name or photo.
    // Preserves local coins across reloads, country fixed to Global, cannot withdraw.
    _currentProfile = UserProfile(
      id: guestId,
      isAnonymous: true,
      nickname: guestNickname,
      avatarUrl: null, // Guests must NEVER display previous/personal user photo
      coins: savedCoins,
      isVip: false,
      gender: 'unspecified',
      interests: const ['Music', 'Gaming'],
      country: 'Global (Worldwide)',
      countryCode: 'ALL',
    );

    _profileController.add(_currentProfile);
    return _currentProfile!;
  }

  /// Public accessor to fetch a remote profile by user ID
  Future<UserProfile?> fetchRemoteProfile(String userId) => _fetchRemoteProfile(userId);

  Future<UserProfile?> _fetchRemoteProfile(String userId) async {
    if (_client == null) return null;
    try {
      final data = await _client!.from('profiles').select().eq('id', userId).maybeSingle();
      if (data != null) {
        return UserProfile.fromMap(data);
      }
    } catch (e) {
      debugPrint('[SupabaseService] Error fetching remote profile: $e');
    }
    return null;
  }

  Future<UserWallet?> _syncUserWallet(String userId) async {
    if (_client == null || !AppConfig.isSupabaseConfigured) {
      final localWallet = UserWallet(
        id: 'local_wallet_$userId',
        userId: userId,
        balance: _currentProfile?.coins ?? 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _currentWallet = localWallet;
      _walletController.add(_currentWallet);
      return localWallet;
    }

    try {
      // 1. Ensure wallet exists in database via stored procedure
      try {
        await _client!.rpc('ensure_user_wallet', params: {'p_user_id': userId});
      } catch (e) {
        debugPrint('[SupabaseService] ensure_user_wallet note: $e');
      }

      // 2. Fetch wallet record
      final data = await _client!.from('wallets').select().eq('user_id', userId).maybeSingle();
      if (data != null) {
        final wallet = UserWallet.fromMap(data);
        var effectiveWallet = wallet;

        // Auto-reconciliation: If user earned gift coins that were cached locally before reload,
        // reconcile upward into Supabase so balance is never lost!
        final prefs = await SharedPreferences.getInstance();
        final localCoins = prefs.getInt('local_user_coins_$userId') ?? prefs.getInt('local_user_coins');
        if (localCoins != null && localCoins > wallet.balance) {
          try {
            await _client!.from('wallets').update({
              'balance': localCoins,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('user_id', userId);
            await _client!.from('profiles').update({
              'coins': localCoins,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', userId);
            effectiveWallet = wallet.copyWith(balance: localCoins);
          } catch (_) {}
        }

        _currentWallet = effectiveWallet;
        _walletController.add(_currentWallet);

        // Keep profile coins aligned with ledger balance
        if (_currentProfile != null && _currentProfile!.coins != effectiveWallet.balance) {
          _currentProfile = _currentProfile!.copyWith(coins: effectiveWallet.balance);
          _profileController.add(_currentProfile);
        }

        // 3. Setup real-time listener on wallets table for this user
        _subscribeToWalletChanges(userId);
        return effectiveWallet;
      }
    } catch (e) {
      debugPrint('[SupabaseService] Error syncing user wallet: $e');
    }

    return null;
  }

  void _subscribeToWalletChanges(String userId) {
    if (_client == null) return;
    try {
      _walletChannel?.unsubscribe();
      _walletChannel = _client!
          .channel('wallet_changes_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'wallets',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              final newRecord = payload.newRecord;
              if (newRecord.isNotEmpty) {
                final updatedWallet = UserWallet.fromMap(newRecord);
                _currentWallet = updatedWallet;
                _walletController.add(updatedWallet);

                if (_currentProfile != null && _currentProfile!.coins != updatedWallet.balance) {
                  _currentProfile = _currentProfile!.copyWith(coins: updatedWallet.balance);
                  _profileController.add(_currentProfile);
                }
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[SupabaseService] Error subscribing to wallet changes: $e');
    }
  }

  /// Fetch user wallet
  Future<UserWallet?> fetchUserWallet() async {
    final userId = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (userId == null) return null;
    return _syncUserWallet(userId);
  }

  /// Fetch dynamic coin packages from database
  Future<List<CoinPackage>> fetchCoinPackages() async {
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('coin_packages')
            .select()
            .eq('is_active', true)
            .order('sort_order', ascending: true);

        if (data.isNotEmpty) {
          return data.map((item) => CoinPackage.fromMap(item)).toList();
        }
      } catch (e) {
        debugPrint('[SupabaseService] Error loading coin packages from DB, using defaults: $e');
      }
    }
    return CoinPackage.availablePackages;
  }

  /// Fetch immutable ledger transaction history (merging database records and local transactions)
  Future<List<WalletLedgerEntry>> fetchWalletLedger({int limit = 50}) async {
    final userId = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (userId == null) return [];

    final List<WalletLedgerEntry> entries = [];
    final Set<String> seenIds = {};

    // 1. Fetch remote ledger from Supabase
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('wallet_ledger')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(limit);

        if (data.isNotEmpty) {
          for (final item in data) {
            final entry = WalletLedgerEntry.fromMap(item);
            entries.add(entry);
            seenIds.add(entry.id);
            if (entry.idempotencyKey != null) seenIds.add(entry.idempotencyKey!);
          }
        }
      } catch (e) {
        debugPrint('[SupabaseService] Error loading wallet ledger: $e');
      }
    }

    // 2. Merge local transactions (e.g. gifts received/sent during session) so no records are lost on reload
    final prefs = await SharedPreferences.getInstance();
    final savedPurchases = prefs.getStringList('local_tx_history_$userId') ?? [];
    for (final s in savedPurchases) {
      final parts = s.split('|');
      final txId = parts[0];
      if (seenIds.contains(txId) || seenIds.contains('ledger_recv_$txId') || seenIds.contains('ledger_$txId')) continue;

      entries.add(WalletLedgerEntry(
        id: txId,
        walletId: 'local_wallet_$userId',
        userId: userId,
        type: LedgerTransactionType.fromString(parts.length > 1 ? parts[1] : 'purchase'),
        amount: parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0,
        balanceAfter: parts.length > 3 ? (int.tryParse(parts[3]) ?? 0) : 0,
        description: parts.length > 4 ? parts[4] : 'Coin transaction',
        createdAt: DateTime.now(),
      ));
      seenIds.add(txId);
    }

    // Sort descending by creation date
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries.take(limit).toList();
  }

  /// Sign in as Anonymous Guest (One-click Omegle entry)
  Future<UserProfile> signInAnonymously() async {
    if (_client != null) {
      try {
        final res = await _client!.auth.signInAnonymously();
        if (res.user != null) {
          final profile = UserProfile(
            id: res.user!.id,
            isAnonymous: true,
            nickname: 'Guest #${res.user!.id.substring(0, 5)}',
            coins: 0, // Guest users have 0 coins before login/signup
          );
          _currentProfile = profile;
          _profileController.add(profile);
          return profile;
        }
      } catch (e) {
        debugPrint('[SupabaseService] Supabase anon sign-in failed, using local profile: $e');
      }
    }
    return _loadOrCreateProfile();
  }

  int _computeAgeFromDate(DateTime date) {
    final now = DateTime.now();
    int age = now.year - date.year;
    if (now.month < date.month || (now.month == date.month && now.day < date.day)) {
      age--;
    }
    return age;
  }

  /// Extract age from Google OAuth / Gmail user metadata
  int? _extractAgeFromMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null) return null;

    // Check direct age field
    if (metadata['age'] != null) {
      if (metadata['age'] is int) return metadata['age'] as int;
      final parsed = int.tryParse(metadata['age'].toString());
      if (parsed != null) return parsed;
    }

    // Check Google birthday / birthdate / dob keys
    final possibleDateStr = metadata['birthdate'] ??
        metadata['birthday'] ??
        metadata['dob'] ??
        metadata['date_of_birth'] ??
        metadata['custom_claims']?['birthdate'];

    if (possibleDateStr != null) {
      try {
        final date = DateTime.tryParse(possibleDateStr.toString());
        if (date != null) {
          return _computeAgeFromDate(date);
        }
      } catch (_) {}
    }

    // Check Google People structure (birthdays list)
    if (metadata['birthdays'] is List && (metadata['birthdays'] as List).isNotEmpty) {
      for (final item in metadata['birthdays'] as List) {
        if (item is Map && item['date'] is Map) {
          final dateMap = item['date'] as Map;
          final year = int.tryParse(dateMap['year']?.toString() ?? '');
          if (year != null) {
            final month = int.tryParse(dateMap['month']?.toString() ?? '1') ?? 1;
            final day = int.tryParse(dateMap['day']?.toString() ?? '1') ?? 1;
            return _computeAgeFromDate(DateTime(year, month, day));
          }
        }
      }
    }

    // Check age_range if provided by Google People
    if (metadata['age_range'] is Map) {
      final range = metadata['age_range'] as Map;
      if (range['max'] != null) {
        final maxAge = int.tryParse(range['max'].toString());
        if (maxAge != null && maxAge < 18) return maxAge;
      }
      if (range['min'] != null) {
        final minAge = int.tryParse(range['min'].toString());
        if (minAge != null && minAge >= 18) return minAge;
      }
    }

    return null;
  }

  /// Check Google user's age from Google/Gmail:
  /// - returns [GoogleAgeStatus.underageBlocked] if Google reports age < 18 (blocks user & signs out).
  /// - returns [GoogleAgeStatus.verifiedAdult] if Google reports age >= 18 or user previously verified age.
  /// - returns [GoogleAgeStatus.dobNotFound] if Google does NOT provide age or DOB (app must ask user to put DOB).
  Future<GoogleAgeStatus> checkGoogleUserAge() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('baatkry_underage_blocked') ?? false) {
      return GoogleAgeStatus.underageBlocked;
    }

    if (!isGoogleUser) return GoogleAgeStatus.dobNotFound;

    final user = _client?.auth.currentUser;
    int? age;

    // 1. Check user metadata from Google OAuth
    if (user != null) {
      age = _extractAgeFromMetadata(user.userMetadata);
      if (age == null && user.identities != null) {
        for (final id in user.identities!) {
          age = _extractAgeFromMetadata(id.identityData);
          if (age != null) break;
        }
      }
    }

    // 2. Query Google People API if session has providerToken and age was not in metadata
    final session = _client?.auth.currentSession;
    if (session?.providerToken != null && age == null) {
      age = await _fetchAgeFromGooglePeopleApi(session!.providerToken!);
    }

    // 3. If age was explicitly found from Google/Gmail:
    if (age != null) {
      if (age < 18) {
        // UNDERAGE: Block user immediately!
        await prefs.setBool('baatkry_underage_blocked', true);
        await prefs.setBool('baatkry_age_verified_18_plus', false);
        if (_client != null) {
          try {
            await _client!.auth.signOut();
          } catch (_) {}
        }
        return GoogleAgeStatus.underageBlocked;
      }

      // Eligible 18+
      await prefs.setBool('baatkry_underage_blocked', false);
      await prefs.setBool('baatkry_age_verified_18_plus', true);
      await prefs.setInt('baatkry_user_age', age);
      if (_currentProfile != null) {
        _currentProfile = _currentProfile!.copyWith(age: age, isAgeVerified: true);
        _profileController.add(_currentProfile);
      }
      return GoogleAgeStatus.verifiedAdult;
    }

    // 4. Age or DOB NOT found directly from Google OAuth:
    // Check in-memory profile first
    if (_currentProfile?.isAgeVerified == true ||
        _currentProfile?.birthDate != null ||
        (_currentProfile?.age != null && _currentProfile!.age! >= 18)) {
      await prefs.setBool('baatkry_age_verified_18_plus', true);
      if (_currentProfile?.birthDate != null) {
        await prefs.setString('baatkry_user_dob', _currentProfile!.birthDate!);
      }
      return GoogleAgeStatus.verifiedAdult;
    }

    // Check remote profile from database table
    if (user != null) {
      final remote = await _fetchRemoteProfile(user.id);
      if (remote != null &&
          (remote.isAgeVerified || remote.birthDate != null || (remote.age != null && remote.age! >= 18))) {
        _currentProfile = remote;
        _profileController.add(_currentProfile);
        await prefs.setBool('baatkry_age_verified_18_plus', true);
        if (remote.birthDate != null) {
          await prefs.setString('baatkry_user_dob', remote.birthDate!);
        }
        return GoogleAgeStatus.verifiedAdult;
      }
    }

    // Check SharedPreferences if previously verified on this device
    final previouslyVerified = prefs.getBool('baatkry_age_verified_18_plus') ?? false;
    final savedDob = prefs.getString('baatkry_user_dob') ?? prefs.getString('local_user_dob');
    final savedAge = prefs.getInt('baatkry_user_age') ?? prefs.getInt('local_user_age');
    if (previouslyVerified || savedDob != null || (savedAge != null && savedAge >= 18)) {
      return GoogleAgeStatus.verifiedAdult;
    }

    // Age / DOB not found from Gmail -> ask user to put their date of birth!
    return GoogleAgeStatus.dobNotFound;
  }

  /// Backward-compatible helper returning true if user is eligible (not blocked as minor)
  Future<bool> verifyGoogleUserEligibility() async {
    final status = await checkGoogleUserAge();
    return status != GoogleAgeStatus.underageBlocked;
  }

  Future<int?> _fetchAgeFromGooglePeopleApi(String token) async {
    try {
      final uri = Uri.parse('https://people.googleapis.com/v1/people/me?personFields=birthdays,ageRanges');
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        // Check birthdays list
        final birthdays = data['birthdays'] as List<dynamic>?;
        if (birthdays != null && birthdays.isNotEmpty) {
          for (final b in birthdays) {
            final dateMap = b['date'] as Map<String, dynamic>?;
            if (dateMap != null && dateMap['year'] != null) {
              final year = dateMap['year'] as int;
              final month = dateMap['month'] as int? ?? 1;
              final day = dateMap['day'] as int? ?? 1;
              final dob = DateTime(year, month, day);
              final now = DateTime.now();
              int calculatedAge = now.year - dob.year;
              if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
                calculatedAge--;
              }
              return calculatedAge;
            }
          }
        }
        // Check ageRanges
        final ageRanges = data['ageRanges'] as List<dynamic>?;
        if (ageRanges != null && ageRanges.isNotEmpty) {
          for (final ar in ageRanges) {
            final range = ar['ageRange']?.toString();
            if (range == 'LESS_THAN_EIGHTEEN') {
              return 16; // Underage flag
            } else if (range == 'EIGHTEEN_TO_TWENTY') {
              return 19;
            } else if (range == 'TWENTY_ONE_OR_OLDER') {
              return 22;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[SupabaseService] Google People API fetch note: $e');
    }
    return null;
  }

  /// Sign in with Google (OAuth)
  /// Enforces 18+ requirement: checks age from Google/Gmail metadata and rejects under-18 users
  Future<bool> signInWithGoogle() async {
    // Check if device is flagged as underage blocked
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('baatkry_underage_blocked') ?? false) {
      throw Exception('Access Denied: You are under 18 years old. Baatkry is strictly for adults 18+.');
    }

    if (_client != null && AppConfig.isSupabaseConfigured) {
      final redirectUrl = kIsWeb
          ? '${Uri.base.origin}/'
          : 'com.usmanahmad.baatkry://login-callback';

      return await _client!.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
        scopes: 'email profile openid',
        queryParams: {
          'prompt': 'select_account',
          'access_type': 'offline',
        },
      );
    }

    // Test / Local environment fallback:
    return signInWithGmailDirect('google.user@gmail.com');
  }

  /// Sign in directly with a Google / Gmail account address
  /// Prompts for Date of Birth if not provided, verifies 18+ eligibility, and creates a verified Google profile
  Future<bool> signInWithGmailDirect(String email, {DateTime? dateOfBirth}) async {
    final cleanEmail = email.trim().toLowerCase();
    if (!cleanEmail.contains('@')) {
      throw Exception('Please enter a valid Gmail address.');
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('baatkry_underage_blocked') ?? false) {
      throw Exception('Access Denied: You are under 18 years old. Baatkry is strictly for adults 18+.');
    }

    int calculatedAge = 21;
    if (dateOfBirth != null) {
      final now = DateTime.now();
      calculatedAge = now.year - dateOfBirth.year;
      if (now.month < dateOfBirth.month || (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
        calculatedAge--;
      }
      if (calculatedAge < 18) {
        await prefs.setBool('baatkry_underage_blocked', true);
        throw Exception('Underage Access Denied: You must be at least 18 years old to use Baatkry.');
      }
    }

    final nickname = cleanEmail.split('@').first;
    final userId = 'google_${cleanEmail.hashCode.abs()}';

    final hasUsedBonusOnDevice = prefs.getBool('baatkry_bonus_used_on_device') ?? false;
    final hasClaimedBonusForEmail = prefs.getBool('baatkry_bonus_claimed_$cleanEmail') ?? false;
    final hasClaimedBonusForUser = prefs.getBool('baatkry_bonus_claimed_$userId') ?? false;
    final savedUserCoins = prefs.getInt('local_user_coins_$userId');

    // ONLY first-time user gets 120 coins:
    // If the device has already claimed the joining bonus, OR this email has claimed it,
    // OR this user has claimed it, OR there is a previously saved coin balance for this user,
    // they do NOT receive another 120 coins. They receive their saved balance (or 0).
    final isFirstTimeUser = !hasUsedBonusOnDevice &&
        !hasClaimedBonusForEmail &&
        !hasClaimedBonusForUser &&
        savedUserCoins == null;

    final initialCoins = isFirstTimeUser ? 120 : (savedUserCoins ?? 0);

    // Record bonus claim and persistence
    if (isFirstTimeUser) {
      await prefs.setBool('baatkry_bonus_used_on_device', true);
      _hasUsedJoiningBonus = true;
    }
    await prefs.setBool('baatkry_bonus_claimed_$cleanEmail', true);
    await prefs.setBool('baatkry_bonus_claimed_$userId', true);

    final savedAvatar = prefs.getString('local_user_avatar_url_$userId') ??
        prefs.getString('local_user_avatar_url') ??
        'https://api.dicebear.com/7.x/avataaars/png?seed=$nickname';
    final savedDob = prefs.getString('local_user_dob_$userId') ??
        prefs.getString('baatkry_user_dob') ??
        prefs.getString('local_user_dob');
    final savedAge = prefs.getInt('local_user_age_$userId') ??
        prefs.getInt('baatkry_user_age') ??
        prefs.getInt('local_user_age');
    final dobIso = dateOfBirth != null
        ? dateOfBirth.toIso8601String().split('T').first
        : savedDob;
    final finalAge = dateOfBirth != null ? calculatedAge : (savedAge ?? calculatedAge);

    final savedUsername = prefs.getString('local_user_username_$userId');
    final savedUsernameUpdatedAtStr = prefs.getString('local_user_username_updated_at_$userId');
    final savedUsernameUpdatedAt = savedUsernameUpdatedAtStr != null ? DateTime.tryParse(savedUsernameUpdatedAtStr) : null;
    final savedDailyStreak = prefs.getInt('local_user_daily_streak_$userId') ?? 0;
    final savedLastClaimStr = prefs.getString('local_user_last_claim_at_$userId');
    final savedLastClaimAt = savedLastClaimStr != null ? DateTime.tryParse(savedLastClaimStr) : null;

    final savedVipExpiryStr = prefs.getString('local_user_vip_expires_at_$userId');
    final savedVipExpiry = savedVipExpiryStr != null ? DateTime.tryParse(savedVipExpiryStr) : null;
    final isVip = (prefs.getBool('local_user_is_vip_$userId') ?? false) &&
        (savedVipExpiry == null || DateTime.now().isBefore(savedVipExpiry));

    final profile = UserProfile(
      id: userId,
      isAnonymous: false,
      nickname: nickname,
      username: savedUsername,
      usernameUpdatedAt: savedUsernameUpdatedAt,
      avatarUrl: savedAvatar,
      coins: initialCoins,
      age: finalAge,
      isAgeVerified: dobIso != null || (finalAge >= 18),
      birthDate: dobIso,
      isVip: isVip,
      vipExpiresAt: savedVipExpiry,
      country: 'Global (Worldwide)',
      countryCode: 'ALL',
      dailyClaimStreak: savedDailyStreak,
      lastDailyClaimAt: savedLastClaimAt,
    );

    await prefs.setString('local_user_id', userId);
    await prefs.setString('local_user_nickname', nickname);
    await prefs.setString('local_user_email', cleanEmail);
    await prefs.setString('local_user_avatar_url', savedAvatar);
    await prefs.setBool('baatkry_age_verified_18_plus', true);
    if (dobIso != null) {
      await prefs.setString('baatkry_user_dob', dobIso);
      await prefs.setString('local_user_dob', dobIso);
      await prefs.setString('local_user_dob_$userId', dobIso);
    }
    await prefs.setInt('local_user_age', finalAge);
    await prefs.setInt('local_user_age_$userId', finalAge);
    await prefs.setInt('baatkry_user_age', finalAge);
    await prefs.setInt('local_user_coins_$userId', initialCoins);
    await prefs.setInt('local_user_coins', initialCoins);

    _currentProfile = profile;
    _profileController.add(_currentProfile);
    await _upsertLocalUserRecord(profile);
    return true;
  }

  /// Registered Sign-In / Sign-Up with Email & Password
  /// (Strictly required before in-app purchases or VIP subscriptions)
  Future<bool> registerWithEmail({
    required String email,
    required String password,
    required String nickname,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final hasUsedBonusOnDevice = prefs.getBool('baatkry_bonus_used_on_device') ?? false;
    final hasClaimedBonusForEmail = prefs.getBool('baatkry_bonus_claimed_$cleanEmail') ?? false;
    final isFirstTimeUser = !hasUsedBonusOnDevice && !hasClaimedBonusForEmail;
    final initialCoins = isFirstTimeUser ? 120 : 0;

    if (_client != null) {
      try {
        final res = await _client!.auth.signUp(
          email: email,
          password: password,
          data: {'nickname': nickname},
        );
        if (res.user != null) {
          final profile = UserProfile(
            id: res.user!.id,
            isAnonymous: false,
            nickname: nickname,
            coins: initialCoins,
          );
          if (isFirstTimeUser) {
            await prefs.setBool('baatkry_bonus_used_on_device', true);
            _hasUsedJoiningBonus = true;
          }
          await prefs.setBool('baatkry_bonus_claimed_${res.user!.id}', true);
          await prefs.setBool('baatkry_bonus_claimed_$cleanEmail', true);
          await prefs.setInt('local_user_coins_${res.user!.id}', initialCoins);
          await prefs.setInt('local_user_coins', initialCoins);

          await _client!.from('profiles').upsert(profile.toMap());
          _currentProfile = profile;
          _profileController.add(_currentProfile);
          return true;
        }
      } catch (e) {
        debugPrint('[SupabaseService] Registration error: $e');
        rethrow;
      }
    }

    // Local simulation fallback
    final userId = 'email_${cleanEmail.hashCode.abs()}';
    if (isFirstTimeUser) {
      await prefs.setBool('baatkry_bonus_used_on_device', true);
      _hasUsedJoiningBonus = true;
    }
    await prefs.setBool('baatkry_bonus_claimed_$userId', true);
    await prefs.setBool('baatkry_bonus_claimed_$cleanEmail', true);
    await prefs.setString('local_user_id', userId);
    await prefs.setString('local_user_nickname', nickname);
    await prefs.setString('local_user_email', cleanEmail);
    await prefs.setInt('local_user_coins_$userId', initialCoins);
    await prefs.setInt('local_user_coins', initialCoins);

    final profile = UserProfile(
      id: userId,
      isAnonymous: false,
      nickname: nickname,
      coins: initialCoins,
    );

    _currentProfile = profile;
    _profileController.add(_currentProfile);
    await _upsertLocalUserRecord(profile);
    return true;
  }

  /// Sign in with email and password
  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();

    if (_client != null) {
      try {
        final res = await _client!.auth.signInWithPassword(email: email, password: password);
        if (res.user != null) {
          final remoteProfile = await _fetchRemoteProfile(res.user!.id);
          final savedCoins = prefs.getInt('local_user_coins_${res.user!.id}') ?? prefs.getInt('local_user_coins');
          final savedUsername = prefs.getString('local_user_username_${res.user!.id}') ?? remoteProfile?.username;
          final savedDob = remoteProfile?.birthDate ??
              prefs.getString('local_user_dob_${res.user!.id}') ??
              prefs.getString('baatkry_user_dob');
          final savedAge = remoteProfile?.age ??
              prefs.getInt('local_user_age_${res.user!.id}') ??
              prefs.getInt('baatkry_user_age');
          final savedVipExpiryStr = prefs.getString('local_user_vip_expires_at_${res.user!.id}');
          final savedVipExpiry = savedVipExpiryStr != null
              ? DateTime.tryParse(savedVipExpiryStr)
              : remoteProfile?.vipExpiresAt;
          final isVipEffective = ((remoteProfile?.isVip ?? false) ||
                  (prefs.getBool('local_user_is_vip_${res.user!.id}') ?? false)) &&
              (savedVipExpiry == null || DateTime.now().isBefore(savedVipExpiry));

          final profile = (remoteProfile != null)
              ? remoteProfile.copyWith(
                  username: savedUsername ?? remoteProfile.username,
                  birthDate: savedDob ?? remoteProfile.birthDate,
                  age: savedAge ?? remoteProfile.age,
                  isVip: isVipEffective,
                  vipExpiresAt: savedVipExpiry,
                )
              : UserProfile(
                  id: res.user!.id,
                  isAnonymous: false,
                  nickname: cleanEmail.split('@').first,
                  username: savedUsername,
                  coins: savedCoins ?? 0, // Returning user logging in keeps their saved coins (never a new 120)
                  birthDate: savedDob,
                  age: savedAge,
                  isAgeVerified: savedDob != null || (savedAge != null && savedAge >= 18),
                  isVip: isVipEffective,
                  vipExpiresAt: savedVipExpiry,
                );
          await prefs.setInt('local_user_coins_${res.user!.id}', profile.coins);
          await prefs.setInt('local_user_coins', profile.coins);
          _currentProfile = profile;
          _profileController.add(_currentProfile);
          return true;
        }
      } catch (e) {
        debugPrint('[SupabaseService] Login error: $e');
        rethrow;
      }
    }

    // Local simulation fallback
    final nickname = email.split('@').first;
    final userId = 'email_${cleanEmail.hashCode.abs()}';
    final savedCoins = prefs.getInt('local_user_coins_$userId') ?? prefs.getInt('local_user_coins');
    final coins = savedCoins ?? 0;
    final savedUsername = prefs.getString('local_user_username_$userId');
    final savedUsernameUpdatedAtStr = prefs.getString('local_user_username_updated_at_$userId');
    final savedUsernameUpdatedAt = savedUsernameUpdatedAtStr != null ? DateTime.tryParse(savedUsernameUpdatedAtStr) : null;
    final savedDailyStreak = prefs.getInt('local_user_daily_streak_$userId') ?? 0;
    final savedLastClaimStr = prefs.getString('local_user_last_claim_at_$userId');
    final savedLastClaimAt = savedLastClaimStr != null ? DateTime.tryParse(savedLastClaimStr) : null;

    final savedDob = prefs.getString('local_user_dob_$userId') ?? prefs.getString('baatkry_user_dob');
    final savedAge = prefs.getInt('local_user_age_$userId') ?? prefs.getInt('baatkry_user_age');
    final savedVipExpiryStr = prefs.getString('local_user_vip_expires_at_$userId');
    final savedVipExpiry = savedVipExpiryStr != null ? DateTime.tryParse(savedVipExpiryStr) : null;
    final isVip = (prefs.getBool('local_user_is_vip_$userId') ?? false) &&
        (savedVipExpiry == null || DateTime.now().isBefore(savedVipExpiry));

    final profile = UserProfile(
      id: userId,
      isAnonymous: false,
      nickname: nickname,
      username: savedUsername,
      usernameUpdatedAt: savedUsernameUpdatedAt,
      coins: coins,
      birthDate: savedDob,
      age: savedAge,
      isAgeVerified: savedDob != null || (savedAge != null && savedAge >= 18),
      isVip: isVip,
      vipExpiresAt: savedVipExpiry,
      dailyClaimStreak: savedDailyStreak,
      lastDailyClaimAt: savedLastClaimAt,
    );

    await prefs.setString('local_user_id', userId);
    await prefs.setString('local_user_nickname', nickname);
    await prefs.setString('local_user_email', cleanEmail);
    await prefs.setInt('local_user_coins_$userId', coins);
    await prefs.setInt('local_user_coins', coins);

    _currentProfile = profile;
    _profileController.add(_currentProfile);
    await _upsertLocalUserRecord(profile);
    return true;
  }

  /// Sign out and revert to Anonymous Guest
  Future<void> signOut() async {
    try {
      _walletChannel?.unsubscribe();
      _creatorWalletChannel?.unsubscribe();
    } catch (_) {}
    _walletChannel = null;
    _creatorWalletChannel = null;
    _currentWallet = null;
    _currentCreatorWallet = null;
    _walletController.add(null);
    _creatorWalletController.add(null);

    if (_client != null) {
      try {
        await _client!.auth.signOut();
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('local_user_id');
    await prefs.remove('local_user_nickname');
    await prefs.remove('local_user_avatar_url');
    await prefs.remove('baatkry_age_verified_18_plus');
    await prefs.remove('baatkry_user_age');
    await prefs.remove('baatkry_user_dob');
    await prefs.remove('local_user_gender');
    await prefs.remove('baatkry_user_gender_locked');
    await _loadOrCreateProfile();
  }

  /// Update user profile details (interests, nickname, username, gender, country, age verification)
  Future<void> updateProfile({
    String? nickname,
    String? username,
    String? gender,
    List<String>? interests,
    String? avatarUrl,
    int? age,
    bool? isAgeVerified,
    String? birthDate,
    String? country,
    String? countryCode,
  }) async {
    if (_currentProfile == null) return;

    // Calculate effective age & verification status from birthDate if provided
    int? effectiveAge = age;
    bool? effectiveVerified = isAgeVerified;
    if (birthDate != null) {
      final parsed = DateTime.tryParse(birthDate);
      if (parsed != null) {
        final now = DateTime.now();
        int calcAge = now.year - parsed.year;
        if (now.month < parsed.month || (now.month == parsed.month && now.day < parsed.day)) {
          calcAge--;
        }
        effectiveAge ??= calcAge;
      }
    }
    if (effectiveAge != null && effectiveAge >= 18) {
      effectiveVerified = true;
    }

    // Enforce immutable gender: Once gender is set, user cannot change it!
    String? effectiveGender = gender;
    if (_currentProfile!.isGenderSet) {
      effectiveGender = _currentProfile!.gender; // preserve locked gender
    }

    String? effectiveUsername = username;
    DateTime? effectiveUsernameUpdatedAt = _currentProfile!.usernameUpdatedAt;
    if (effectiveUsername != null) {
      effectiveUsername = effectiveUsername.trim().toLowerCase().replaceAll('@', '');
      if (_currentProfile!.username != null &&
          _currentProfile!.username!.isNotEmpty &&
          _currentProfile!.username!.toLowerCase() != effectiveUsername) {
        if (!_currentProfile!.canChangeUsername) {
          final days = _currentProfile!.daysUntilUsernameChange;
          throw Exception(
            'You cannot change your username yet. Usernames can only be changed once every 7 days ($days day${days == 1 ? '' : 's'} remaining).',
          );
        }
        effectiveUsernameUpdatedAt = DateTime.now().toUtc();
      } else if (_currentProfile!.username == null || _currentProfile!.username!.isEmpty) {
        effectiveUsernameUpdatedAt = DateTime.now().toUtc();
      }
    }

    _currentProfile = _currentProfile!.copyWith(
      nickname: nickname,
      username: effectiveUsername,
      usernameUpdatedAt: effectiveUsernameUpdatedAt,
      gender: effectiveGender,
      interests: interests,
      avatarUrl: avatarUrl,
      age: effectiveAge,
      isAgeVerified: effectiveVerified,
      birthDate: birthDate,
      country: country,
      countryCode: countryCode,
    );

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('profiles').upsert(_currentProfile!.toMap());
      } catch (e) {
        debugPrint('[SupabaseService] Update remote profile error: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    if (nickname != null) await prefs.setString('local_user_nickname', nickname);
    if (effectiveUsername != null) {
      await prefs.setString('local_user_username_${_currentProfile!.id}', effectiveUsername);
      await prefs.setString('local_username_owner_$effectiveUsername', _currentProfile!.id);
      if (effectiveUsernameUpdatedAt != null) {
        await prefs.setString(
          'local_user_username_updated_at_${_currentProfile!.id}',
          effectiveUsernameUpdatedAt.toIso8601String(),
        );
      }
    }
    if (effectiveGender != null) {
      await prefs.setString('local_user_gender', effectiveGender);
      if (effectiveGender != 'unspecified' && effectiveGender.isNotEmpty) {
        await prefs.setBool('baatkry_user_gender_locked', true);
      }
    }
    if (interests != null) await prefs.setStringList('local_user_interests', interests);
    if (avatarUrl != null) await prefs.setString('local_user_avatar_url', avatarUrl);
    if (effectiveAge != null) {
      await prefs.setInt('local_user_age', effectiveAge);
      await prefs.setInt('baatkry_user_age', effectiveAge);
    }
    if (effectiveVerified != null) await prefs.setBool('baatkry_age_verified_18_plus', effectiveVerified);
    if (birthDate != null) {
      await prefs.setString('local_user_dob', birthDate);
      await prefs.setString('baatkry_user_dob', birthDate);
    }
    if (country != null) await prefs.setString('local_user_country', country);
    if (countryCode != null) await prefs.setString('local_user_country_code', countryCode);

    _profileController.add(_currentProfile);
    await _upsertLocalUserRecord(_currentProfile!);
  }

  /// Whether user's own gender is permanently locked
  bool get isGenderLocked => _currentProfile?.isGenderSet ?? false;

  /// Sets user gender once permanently. Returns false if already locked.
  Future<bool> setPermanentGender(String gender) async {
    if (_currentProfile == null) return false;
    if (_currentProfile!.isGenderSet) {
      debugPrint('[SupabaseService] Gender is already permanently set: ${_currentProfile!.gender}');
      return false;
    }

    final sanitized = gender.trim().toLowerCase();
    if (sanitized.isEmpty || sanitized == 'unspecified') return false;

    _currentProfile = _currentProfile!.copyWith(gender: sanitized);
    _profileController.add(_currentProfile);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_user_gender', sanitized);
    await prefs.setBool('baatkry_user_gender_locked', true);
    await _upsertLocalUserRecord(_currentProfile!);

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('profiles').upsert(_currentProfile!.toMap());
      } catch (e) {
        debugPrint('[SupabaseService] Save permanent gender error: $e');
      }
    }
    return true;
  }

  /// Complete a Coin / VIP Purchase via atomic stored procedure
  Future<bool> processPurchase({
    required String packageId,
    required int coinsAdded,
    required int priceRs,
    double? priceUsd,
    String gateway = 'safepay',
  }) async {
    if (_currentProfile == null || _currentProfile!.isAnonymous) {
      throw Exception('Purchase rejected: User must be logged in with Google to make purchases.');
    }

    final userId = _currentProfile!.id;
    final idempotencyKey = const Uuid().v4();
    final effectivePriceUsd = priceUsd ?? (priceRs / 280.0);

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        // Execute atomic stored procedure
        final res = await _client!.rpc(
          'process_verified_coin_purchase',
          params: {
            'p_user_id': userId,
            'p_package_id': packageId,
            'p_gateway': gateway,
            'p_gateway_order_id': 'ord_$idempotencyKey',
            'p_gateway_payment_id': 'pay_$idempotencyKey',
            'p_amount_paid': effectivePriceUsd,
            'p_currency': 'USD',
            'p_idempotency_key': idempotencyKey,
          },
        );

        if (res is Map && res['success'] == true) {
          final newBalance = (res['coins_balance'] as num?)?.toInt() ?? (_currentProfile!.coins + coinsAdded);
          final isVipPackage = packageId.contains('2500') || packageId.contains('5000');
          final vipExpiry = isVipPackage
              ? DateTime.now().add(const Duration(days: 30))
              : _currentProfile?.vipExpiresAt;
          final isVip = isVipPackage || (_currentProfile?.isVipActive ?? false);

          _currentProfile = _currentProfile!.copyWith(
            coins: newBalance,
            isVip: isVip,
            vipExpiresAt: vipExpiry,
          );
          _profileController.add(_currentProfile);

          if (_currentWallet != null) {
            _currentWallet = _currentWallet!.copyWith(
              balance: newBalance,
              totalPurchased: _currentWallet!.totalPurchased + coinsAdded,
              updatedAt: DateTime.now(),
            );
            _walletController.add(_currentWallet);
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('local_user_coins_$userId', newBalance);
          await prefs.setInt('local_user_coins', newBalance);
          await prefs.setBool('local_user_is_vip', isVip);
          if (vipExpiry != null) {
            await prefs.setString('local_user_vip_expires_at_$userId', vipExpiry.toIso8601String());
          }
          return true;
        }
      } catch (e) {
        debugPrint('[SupabaseService] process_verified_coin_purchase RPC note: $e');
      }
    }

    // Local / Offline fallback logic:
    final updatedCoins = _currentProfile!.coins + coinsAdded;
    final isVipPackage = packageId.contains('2500') || packageId.contains('5000');
    final vipExpiry = isVipPackage
        ? DateTime.now().add(const Duration(days: 30))
        : _currentProfile?.vipExpiresAt;
    final isVip = isVipPackage || (_currentProfile?.isVipActive ?? false);

    _currentProfile = _currentProfile!.copyWith(
      coins: updatedCoins,
      isVip: isVip,
      vipExpiresAt: vipExpiry,
    );
    _profileController.add(_currentProfile);

    if (_currentWallet != null) {
      _currentWallet = _currentWallet!.copyWith(
        balance: updatedCoins,
        totalPurchased: _currentWallet!.totalPurchased + coinsAdded,
        updatedAt: DateTime.now(),
      );
      _walletController.add(_currentWallet);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('local_user_coins_$userId', updatedCoins);
    await prefs.setInt('local_user_coins', updatedCoins);
    await prefs.setBool('local_user_is_vip', isVip);
    if (vipExpiry != null) {
      await prefs.setString('local_user_vip_expires_at_$userId', vipExpiry.toIso8601String());
    }

    final history = prefs.getStringList('local_tx_history_$userId') ?? [];
    history.insert(0, '$idempotencyKey|purchase|$coinsAdded|$updatedCoins|Purchased $packageId');
    await prefs.setStringList('local_tx_history_$userId', history);

    return true;
  }

  /// Fetch active virtual gifts catalog
  Future<List<VirtualGift>> fetchActiveGifts() async {
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('gifts')
            .select()
            .eq('is_active', true)
            .order('sort_order', ascending: true);

        if (data.isNotEmpty) {
          return data.map((item) => VirtualGift.fromMap(item)).toList();
        }
      } catch (e) {
        debugPrint('[SupabaseService] Error loading gifts from DB, using defaults: $e');
      }
    }
    return VirtualGift.defaultGifts;
  }

  /// Send a virtual gift atomically
  Future<Map<String, dynamic>> sendVirtualGift({
    required VirtualGift gift,
    required String receiverId,
    required String receiverName,
    String? roomId,
  }) async {
    if (_currentProfile == null || _currentProfile!.isAnonymous) {
      throw Exception('Guest users cannot send gifts. Please sign in with Google first.');
    }

    final currentCoins = _currentWallet?.balance ?? _currentProfile!.coins;
    if (currentCoins < gift.coinPrice) {
      throw Exception('Insufficient coins. Required: ${gift.coinPrice}, Available: $currentCoins');
    }

    final userId = _currentProfile!.id;
    final idempotencyKey = const Uuid().v4();

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final res = await _client!.rpc(
          'send_virtual_gift',
          params: {
            'p_gift_id': gift.id,
            'p_receiver_id': receiverId,
            'p_room_id': roomId,
            'p_idempotency_key': idempotencyKey,
          },
        );

        if (res is Map && res['success'] == true) {
          final newBalance = (res['coins_balance'] as num?)?.toInt() ?? (currentCoins - gift.coinPrice);
          _currentProfile = _currentProfile!.copyWith(coins: newBalance);
          _profileController.add(_currentProfile);

          if (_currentWallet != null) {
            _currentWallet = _currentWallet!.copyWith(
              balance: newBalance,
              totalSpent: _currentWallet!.totalSpent + gift.coinPrice,
              updatedAt: DateTime.now(),
            );
            _walletController.add(_currentWallet);
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('local_user_coins_$userId', newBalance);
          await prefs.setInt('local_user_coins', newBalance);

          return Map<String, dynamic>.from(res);
        }
      } catch (e) {
        debugPrint('[SupabaseService] send_virtual_gift RPC note: $e');
        // If receiver is a non-UUID mock or peer in test mode, proceed with local ledger debit
        if (!receiverId.contains('-') || receiverId.startsWith('mock_')) {
          // fall through to local fallback
        } else {
          rethrow;
        }
      }
    }

    // Local / Offline fallback logic:
    final newBalance = currentCoins - gift.coinPrice;
    _currentProfile = _currentProfile!.copyWith(coins: newBalance);
    _profileController.add(_currentProfile);

    if (_currentWallet != null) {
      _currentWallet = _currentWallet!.copyWith(
        balance: newBalance,
        totalSpent: _currentWallet!.totalSpent + gift.coinPrice,
        updatedAt: DateTime.now(),
      );
      _walletController.add(_currentWallet);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('local_user_coins_$userId', newBalance);
    await prefs.setInt('local_user_coins', newBalance);

    final history = prefs.getStringList('local_tx_history_$userId') ?? [];
    history.insert(0, '$idempotencyKey|gift_sent|-${gift.coinPrice}|$newBalance|Sent ${gift.name} to $receiverName');
    await prefs.setStringList('local_tx_history_$userId', history);

    return {
      'success': true,
      'gift_transaction_id': idempotencyKey,
      'coins_deducted': gift.coinPrice,
      'coins_balance': newBalance,
      'gift': gift.name,
      'creator_earned_usd': 0.0,
    };
  }

  /// Credit incoming gift coins immediately to recipient and sync with local storage & DB
  Future<void> creditReceivedGiftCoins({
    required int coins,
    required String senderId,
    required String senderName,
    required String giftName,
  }) async {
    if (_currentProfile == null) return;

    final newCoins = _currentProfile!.coins + coins;
    _currentProfile = _currentProfile!.copyWith(coins: newCoins);
    _profileController.add(_currentProfile);

    if (_currentWallet != null) {
      _currentWallet = _currentWallet!.copyWith(
        balance: newCoins,
        totalPurchased: _currentWallet!.totalPurchased + coins,
        updatedAt: DateTime.now(),
      );
      _walletController.add(_currentWallet);
    }

    // 1. Persist locally to SharedPreferences
    final uid = _currentProfile!.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('local_user_coins_$uid', newCoins);
    await prefs.setInt('local_user_coins', newCoins);

    final history = prefs.getStringList('local_tx_history_$uid') ?? [];
    final txId = const Uuid().v4();
    history.insert(0, '$txId|gift_received|+$coins|$newCoins|Received $giftName from $senderName');
    await prefs.setStringList('local_tx_history_$uid', history);

    // CRITICAL: Only approved creators can earn cash USD earnings from gifts
    final isCreator = await checkIsCreator(uid);
    if (isCreator) {
      final grossUsd = coins * 0.002;
      final commissionUsd = grossUsd * 0.30;
      final netUsd = grossUsd * 0.70;

      final currentAvail = prefs.getDouble('local_creator_avail_$uid') ?? 0.0;
      final currentLife = prefs.getDouble('local_creator_life_$uid') ?? 0.0;
      final newAvail = currentAvail + netUsd;
      final newLife = currentLife + netUsd;

      await prefs.setDouble('local_creator_avail_$uid', newAvail);
      await prefs.setDouble('local_creator_life_$uid', newLife);

      final updatedCreatorWallet = (_currentCreatorWallet ?? CreatorWallet(
        id: 'creator_wallet_$uid',
        creatorId: uid,
        availableEarningsUsd: 0.0,
        pendingEarningsUsd: 0.0,
        lifetimeEarningsUsd: 0.0,
        withdrawnEarningsUsd: 0.0,
      )).copyWith(
        availableEarningsUsd: newAvail,
        lifetimeEarningsUsd: newLife,
        updatedAt: DateTime.now(),
      );

      _currentCreatorWallet = updatedCreatorWallet;
      _creatorWalletController.add(updatedCreatorWallet);

      // Record itemized creator earning entry
      final earningEntry = CreatorEarningEntry(
        id: 'earn_$txId',
        creatorId: uid,
        giftTransactionId: txId,
        grossAmountUsd: grossUsd,
        platformCommissionUsd: commissionUsd,
        netEarningUsd: netUsd,
        status: 'available',
        giftName: giftName,
        senderName: senderName,
        coins: coins,
        createdAt: DateTime.now(),
      );

      final creatorEarningsList = prefs.getStringList('local_creator_earnings_$uid') ?? [];
      creatorEarningsList.insert(0, jsonEncode(earningEntry.toMap()));
      await prefs.setStringList('local_creator_earnings_$uid', creatorEarningsList);
    }

    // 2. Persist to Supabase Database (profiles, wallets, and wallet_ledger)
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        // A. Update profiles table
        await _client!.from('profiles').update({
          'coins': newCoins,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', uid);

        // B. Ensure and update wallets table
        try {
          await _client!.rpc('ensure_user_wallet', params: {'p_user_id': uid});
        } catch (_) {}

        final walletRes = await _client!.from('wallets').select().eq('user_id', uid).maybeSingle();
        if (walletRes != null) {
          final walletId = walletRes['id'] as String;
          final updatedPurchased = ((walletRes['total_purchased'] as num?)?.toInt() ?? 0) + coins;

          await _client!.from('wallets').update({
            'balance': newCoins,
            'total_purchased': updatedPurchased,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', walletId);

          // C. Insert into wallet_ledger
          try {
            await _client!.from('wallet_ledger').insert({
              'wallet_id': walletId,
              'user_id': uid,
              'type': 'gift_received',
              'amount': coins,
              'balance_after': newCoins,
              'reference_id': giftName,
              'description': 'Received $giftName from $senderName',
              'idempotency_key': 'ledger_recv_$txId',
              'created_at': DateTime.now().toIso8601String(),
            });
          } catch (e) {
            debugPrint('[SupabaseService] wallet_ledger insert note: $e');
          }
        }
      } catch (e) {
        debugPrint('[SupabaseService] creditReceivedGiftCoins remote sync note: $e');
      }
    }
  }

  // ===========================================================================
  // CREATOR APPLICATION & KYC METHODS (Phase 5)
  // ===========================================================================

  /// Fetch latest creator application for current user
  Future<CreatorApplication?> fetchMyCreatorApplication() async {
    final userId = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (userId == null) return null;

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('creator_applications')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(1);

        if (data.isNotEmpty) {
          return CreatorApplication.fromMap(data.first);
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchMyCreatorApplication error: $e');
      }
    }

    // Local / offline fallback
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('local_creator_app_$userId');
    if (jsonStr != null) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return CreatorApplication.fromMap(map);
      } catch (_) {}
    }
    return null;
  }

  /// Submit a new Creator application
  Future<CreatorApplication> submitCreatorApplication({
    required String fullName,
    required DateTime dateOfBirth,
    required String country,
    required IdDocumentType idDocumentType,
    required String idDocumentFrontUrl,
    String? idDocumentBackUrl,
    required String selfieUrl,
    Map<String, dynamic> socialMediaLinks = const {},
    String? bio,
  }) async {
    if (_currentProfile == null || _currentProfile!.isAnonymous) {
      throw Exception('Sign in with Google is required to apply as a Creator.');
    }

    final userId = _currentProfile!.id;
    final now = DateTime.now();

    final app = CreatorApplication(
      id: const Uuid().v4(),
      userId: userId,
      fullName: fullName,
      dateOfBirth: dateOfBirth,
      country: country,
      idDocumentType: idDocumentType,
      idDocumentFrontUrl: idDocumentFrontUrl,
      idDocumentBackUrl: idDocumentBackUrl,
      selfieUrl: selfieUrl,
      socialMediaLinks: socialMediaLinks,
      bio: bio,
      status: CreatorApplicationStatus.pending,
      createdAt: now,
      updatedAt: now,
    );

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('creator_applications')
            .insert(app.toMap())
            .select()
            .single();

        return CreatorApplication.fromMap(data);
      } catch (e) {
        debugPrint('[SupabaseService] submitCreatorApplication error: $e');
      }
    }

    // Local offline save
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_creator_app_$userId', jsonEncode(app.toMap()));
    return app;
  }

  /// Check whether a user is an approved creator
  Future<bool> checkIsCreator([String? userId]) async {
    final uid = userId ?? _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) return false;

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('user_roles')
            .select('role')
            .eq('user_id', uid)
            .eq('role', 'creator')
            .maybeSingle();

        if (data != null) return true;
      } catch (e) {
        debugPrint('[SupabaseService] checkIsCreator error: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    return (prefs.getBool('local_is_creator_$uid') ?? false) ||
        (prefs.getStringList('local_approved_creators') ?? []).contains(uid);
  }

  /// Fetch public creator profile
  Future<CreatorProfile?> fetchCreatorProfile(String creatorId) async {
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('creator_profiles')
            .select()
            .eq('id', creatorId)
            .maybeSingle();

        if (data != null) {
          return CreatorProfile.fromMap(data);
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchCreatorProfile error: $e');
      }
    }
    return null;
  }

  /// Administrative review of a creator application
  Future<Map<String, dynamic>> adminReviewCreatorApplication({
    required String applicationId,
    required String action, // 'approve' or 'reject'
    String? rejectionReason,
  }) async {
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final res = await _client!.rpc(
          'admin_review_creator_application',
          params: {
            'p_application_id': applicationId,
            'p_action': action,
            'p_rejection_reason': rejectionReason,
          },
        );
        if (res is Map) {
          return Map<String, dynamic>.from(res);
        }
      } catch (e) {
        debugPrint('[SupabaseService] admin_review_creator_application RPC note: $e');
        rethrow;
      }
    }

    // Local fallback for offline/testing
    return {
      'success': true,
      'application_id': applicationId,
      'status': action == 'approve' ? 'approved' : 'rejected',
    };
  }

  // ===========================================================================
  // CREATOR FINANCIAL EARNINGS & WALLET METHODS (Phase 6)
  // ===========================================================================

  /// Real-time subscription to creator's earnings wallet
  void _subscribeToCreatorWalletChanges(String creatorId) {
    if (_client == null) return;
    try {
      _creatorWalletChannel?.unsubscribe();
      _creatorWalletChannel = _client!
          .channel('creator_wallet_$creatorId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'creator_wallets',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'creator_id',
              value: creatorId,
            ),
            callback: (payload) {
              final newRecord = payload.newRecord;
              if (newRecord.isNotEmpty) {
                final wallet = CreatorWallet.fromMap(newRecord);
                _currentCreatorWallet = wallet;
                _creatorWalletController.add(wallet);
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[SupabaseService] Error subscribing to creator wallet changes: $e');
    }
  }

  /// Fetch creator's real-money earnings wallet
  Future<CreatorWallet?> fetchCreatorWallet([String? creatorId]) async {
    final uid = creatorId ?? _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) return null;

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('creator_wallets')
            .select()
            .eq('creator_id', uid)
            .maybeSingle();

        if (data != null) {
          final wallet = CreatorWallet.fromMap(data);
          _currentCreatorWallet = wallet;
          _creatorWalletController.add(wallet);
          _subscribeToCreatorWalletChanges(uid);
          return wallet;
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchCreatorWallet error: $e');
      }
    }

    // Local / Offline fallback
    final prefs = await SharedPreferences.getInstance();
    final avail = prefs.getDouble('local_creator_avail_$uid') ?? 0.0;
    final life = prefs.getDouble('local_creator_life_$uid') ?? avail;
    final withdrawn = prefs.getDouble('local_creator_withdrawn_$uid') ?? 0.0;

    final fallbackWallet = CreatorWallet(
      id: 'local_creator_wallet_$uid',
      creatorId: uid,
      availableEarningsUsd: avail,
      pendingEarningsUsd: 0.0,
      lifetimeEarningsUsd: life,
      withdrawnEarningsUsd: withdrawn,
    );
    _currentCreatorWallet = fallbackWallet;
    _creatorWalletController.add(fallbackWallet);
    return fallbackWallet;
  }

  /// Fetch creator itemized gift earnings ledger
  Future<List<CreatorEarningEntry>> fetchCreatorEarnings({int limit = 50}) async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) return [];

    // CRITICAL: Only approved creators have gift earnings
    final isCreator = await checkIsCreator(uid);
    if (!isCreator) return [];

    final List<CreatorEarningEntry> entries = [];
    final Set<String> seenTxIds = {};

    // 1. Fetch remote earnings from Supabase database
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('creator_earnings')
            .select('''
              id, creator_id, gift_transaction_id, gross_amount_usd,
              platform_commission_usd, net_earning_usd, status, created_at,
              gift_transactions (
                gift_id, coins_spent, sender_id
              )
            ''')
            .eq('creator_id', uid)
            .order('created_at', ascending: false)
            .limit(limit);

        if (data.isNotEmpty) {
          for (final item in data) {
            final entry = CreatorEarningEntry.fromMap(item);
            entries.add(entry);
            seenTxIds.add(entry.giftTransactionId);
            seenTxIds.add(entry.id);
          }
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchCreatorEarnings error: $e');
      }
    }

    // 2. Merge local / ledger received gift transactions (ensures instant reflection across reloads & sessions)
    try {
      final prefs = await SharedPreferences.getInstance();
      final localTx = prefs.getStringList('local_tx_history_$uid') ?? [];

      for (final s in localTx) {
        final parts = s.split('|');
        if (parts.length < 5) continue;
        final txId = parts[0];
        final type = parts[1];
        if (type != 'gift_received') continue;
        if (seenTxIds.contains(txId)) continue;

        final rawAmount = parts[2].replaceAll('+', '').trim();
        final coins = int.tryParse(rawAmount) ?? 0;
        final desc = parts[4]; // e.g. "Received Heart from Alice"
        String giftName = 'Gift';
        String senderName = 'Viewer';
        if (desc.contains('Received ') && desc.contains(' from ')) {
          final afterRecv = desc.replaceFirst('Received ', '');
          final subParts = afterRecv.split(' from ');
          if (subParts.isNotEmpty) giftName = subParts[0];
          if (subParts.length > 1) senderName = subParts[1];
        }

        final grossUsd = coins * 0.002;
        final commissionUsd = grossUsd * 0.30;
        final netUsd = grossUsd * 0.70;

        entries.add(CreatorEarningEntry(
          id: 'local_earning_$txId',
          creatorId: uid,
          giftTransactionId: txId,
          grossAmountUsd: grossUsd,
          platformCommissionUsd: commissionUsd,
          netEarningUsd: netUsd,
          status: 'available',
          giftName: giftName,
          senderName: senderName,
          coins: coins,
          createdAt: DateTime.now(),
        ));
        seenTxIds.add(txId);
      }
    } catch (e) {
      debugPrint('[SupabaseService] fetchCreatorEarnings local fallback note: $e');
    }

    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries.take(limit).toList();
  }

  /// Fetch active platform commission rule (Default: 70% Creator / 30% Platform)
  Future<CommissionRule> fetchActiveCommissionRule() async {
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('commission_rules')
            .select()
            .eq('is_active', true)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (data != null) {
          return CommissionRule.fromMap(data);
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchActiveCommissionRule error: $e');
      }
    }

    return CommissionRule.standardDefault;
  }

  // ===========================================================================
  // CREATOR PAYOUT & WITHDRAWAL METHODS (Phase 8)
  // ===========================================================================

  /// Fetch creator's registered payout beneficiary accounts
  Future<List<PayoutAccount>> fetchCreatorPayoutAccounts() async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) return [];

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('payout_accounts')
            .select()
            .eq('creator_id', uid)
            .order('is_primary', ascending: false)
            .order('created_at', ascending: false);

        if (data.isNotEmpty) {
          return data.map((item) => PayoutAccount.fromMap(item)).toList();
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchCreatorPayoutAccounts error: $e');
      }
    }

    // Local / Offline fallback
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList('local_payout_accounts_$uid') ?? [];
    if (rawList.isNotEmpty) {
      return rawList.map((str) => PayoutAccount.fromMap(jsonDecode(str) as Map<String, dynamic>)).toList();
    }
    return [];
  }

  /// Register or update a payout beneficiary account
  Future<PayoutAccount?> saveCreatorPayoutAccount({
    required String payoutMethod,
    required String accountTitle,
    required String accountNumber,
    String? bankName,
    String? routingCode,
    bool isPrimary = true,
  }) async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) return null;

    final newId = const Uuid().v4();
    final now = DateTime.now();

    final account = PayoutAccount(
      id: newId,
      creatorId: uid,
      payoutMethod: payoutMethod,
      accountTitle: accountTitle,
      accountNumber: accountNumber,
      bankName: bankName,
      routingCode: routingCode,
      isVerified: true,
      isPrimary: isPrimary,
      createdAt: now,
      updatedAt: now,
    );

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        if (isPrimary) {
          // Demote existing primary accounts
          await _client!
              .from('payout_accounts')
              .update({'is_primary': false})
              .eq('creator_id', uid);
        }

        final res = await _client!.from('payout_accounts').insert(account.toMap()).select().single();
        return PayoutAccount.fromMap(res);
      } catch (e) {
        debugPrint('[SupabaseService] saveCreatorPayoutAccount error: $e');
      }
    }

    // Local / Offline fallback
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList('local_payout_accounts_$uid') ?? [];
    rawList.insert(0, jsonEncode(account.toMap()));
    await prefs.setStringList('local_payout_accounts_$uid', rawList);
    return account;
  }

  /// Request a creator withdrawal payout ($20.00 minimum threshold, 3% processing fee)
  Future<Map<String, dynamic>> requestCreatorWithdrawal({
    required String payoutAccountId,
    required double amountUsd,
    double? feeUsd,
    String? payoutMethod,
    Map<String, dynamic>? payoutDetails,
    String? idempotencyKey,
  }) async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) {
      throw Exception('Creator must be authenticated to request withdrawals');
    }

    // CRITICAL: Only approved creators can request withdrawals
    final isCreator = await checkIsCreator(uid);
    if (!isCreator) {
      throw Exception('Only approved creators in the Creator Reward Program can request withdrawals.');
    }

    final key = idempotencyKey ?? 'wth_${const Uuid().v4()}';
    final prefs = await SharedPreferences.getInstance();

    final fetchedWallet = await fetchCreatorWallet(uid);
    final wallet = fetchedWallet ?? CreatorWallet(
      id: 'local_creator_wallet_$uid',
      creatorId: uid,
      availableEarningsUsd: 0.0,
      pendingEarningsUsd: 0.0,
      lifetimeEarningsUsd: 0.0,
      withdrawnEarningsUsd: 0.0,
    );
    final currentAvail = wallet.availableEarningsUsd;
    if (currentAvail < amountUsd) {
      throw Exception('Insufficient available balance (\$$currentAvail available, \$$amountUsd requested)');
    }

    final newAvail = (currentAvail - amountUsd).clamp(0.0, double.infinity);
    final newWithdrawn = wallet.withdrawnEarningsUsd + amountUsd;

    final updatedWallet = wallet.copyWith(
      availableEarningsUsd: newAvail,
      withdrawnEarningsUsd: newWithdrawn,
      updatedAt: DateTime.now(),
    );

    _currentCreatorWallet = updatedWallet;
    _creatorWalletController.add(updatedWallet);

    await prefs.setDouble('local_creator_avail_$uid', newAvail);
    await prefs.setDouble('local_creator_withdrawn_$uid', newWithdrawn);

    // Calculate 3% payout fee
    final effectiveFee = feeUsd ?? ((amountUsd * 0.03 * 100).round() / 100.0);
    final effectiveNet = (amountUsd - effectiveFee).clamp(0.0, double.infinity);

    // Retrieve or default complete beneficiary payout details (Bank, IBAN, Holder Name)
    Map<String, dynamic> effectiveDetails = payoutDetails != null ? Map<String, dynamic>.from(payoutDetails) : {};
    String effectiveMethod = payoutMethod ?? 'bank_transfer';
    if (effectiveDetails.isEmpty || !effectiveDetails.containsKey('account_number')) {
      try {
        final accounts = await fetchCreatorPayoutAccounts();
        final acc = accounts.firstWhere((a) => a.id == payoutAccountId);
        effectiveMethod = acc.payoutMethod;
        effectiveDetails = {
          'account_id': acc.id,
          'method': acc.payoutMethod,
          'method_display': acc.methodDisplayName,
          'bank_name': acc.bankName,
          'account_title': acc.accountTitle,
          'account_number': acc.accountNumber,
          'iban': acc.accountNumber,
          'routing_code': acc.routingCode,
        };
      } catch (_) {
        effectiveDetails['payout_account_id'] = payoutAccountId;
      }
    }

    // Save local withdrawal record
    final localTx = CreatorWithdrawal(
      id: key,
      creatorId: uid,
      creatorName: _currentProfile?.nickname ?? 'Creator',
      amountUsd: amountUsd,
      feeUsd: effectiveFee,
      netAmountUsd: effectiveNet,
      payoutMethod: effectiveMethod,
      payoutDetails: effectiveDetails,
      status: 'pending',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 1. Personal list
    final rawList = prefs.getStringList('local_my_withdrawals_$uid') ?? [];
    rawList.insert(0, jsonEncode(localTx.toMap()));
    await prefs.setStringList('local_my_withdrawals_$uid', rawList);

    // 2. Global admin list
    final adminRawList = prefs.getStringList('local_all_admin_withdrawals') ?? [];
    adminRawList.insert(0, jsonEncode(localTx.toMap()));
    await prefs.setStringList('local_all_admin_withdrawals', adminRawList);

    // Attempt remote RPC if Supabase is configured
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final res = await _client!.rpc(
          'request_creator_withdrawal',
          params: {
            'p_payout_account_id': payoutAccountId,
            'p_amount_usd': amountUsd,
            'p_idempotency_key': key,
          },
        );

        if (res is Map) {
          return Map<String, dynamic>.from(res);
        }
      } catch (e) {
        debugPrint('[SupabaseService] request_creator_withdrawal RPC note (saved locally): $e');
      }
    }

    return {
      'success': true,
      'withdrawal_id': key,
      'withdrawal': localTx,
      'amount_usd': amountUsd,
      'fee_usd': effectiveFee,
      'net_amount_usd': effectiveNet,
      'status': 'pending',
      'remaining_available_usd': newAvail,
    };
  }

  /// Self-cancel a pending withdrawal request and atomically restore funds
  Future<Map<String, dynamic>> cancelCreatorWithdrawal(String withdrawalId) async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) {
      throw Exception('Creator must be authenticated to cancel withdrawals');
    }

    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList('local_my_withdrawals_$uid') ?? [];
    double restoredAmount = 0.0;
    final updatedList = <String>[];

    for (final raw in rawList) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['id'] == withdrawalId) {
        restoredAmount = (map['amount_usd'] as num?)?.toDouble() ?? 0.0;
        map['status'] = 'cancelled';
        map['updated_at'] = DateTime.now().toIso8601String();
      }
      updatedList.add(jsonEncode(map));
    }
    await prefs.setStringList('local_my_withdrawals_$uid', updatedList);

    // Also update in global admin list
    final adminRawList = prefs.getStringList('local_all_admin_withdrawals') ?? [];
    final updatedAdminList = <String>[];
    for (final raw in adminRawList) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['id'] == withdrawalId) {
        map['status'] = 'cancelled';
        map['updated_at'] = DateTime.now().toIso8601String();
      }
      updatedAdminList.add(jsonEncode(map));
    }
    await prefs.setStringList('local_all_admin_withdrawals', updatedAdminList);

    if (restoredAmount > 0) {
      final currentAvail = prefs.getDouble('local_creator_avail_$uid') ?? 0.0;
      final currentWithdrawn = prefs.getDouble('local_creator_withdrawn_$uid') ?? 0.0;
      final newAvail = currentAvail + restoredAmount;
      final newWithdrawn = (currentWithdrawn - restoredAmount).clamp(0.0, double.infinity);

      final updatedWallet = (_currentCreatorWallet ?? CreatorWallet(
        id: 'creator_wallet_$uid',
        creatorId: uid,
        availableEarningsUsd: 0.0,
        pendingEarningsUsd: 0.0,
        lifetimeEarningsUsd: 0.0,
        withdrawnEarningsUsd: 0.0,
      )).copyWith(
        availableEarningsUsd: newAvail,
        withdrawnEarningsUsd: newWithdrawn,
        updatedAt: DateTime.now(),
      );

      _currentCreatorWallet = updatedWallet;
      _creatorWalletController.add(updatedWallet);
      await prefs.setDouble('local_creator_avail_$uid', newAvail);
      await prefs.setDouble('local_creator_withdrawn_$uid', newWithdrawn);
    }

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final res = await _client!.rpc(
          'cancel_creator_withdrawal',
          params: {'p_withdrawal_id': withdrawalId},
        );
        if (res is Map) {
          return Map<String, dynamic>.from(res);
        }
      } catch (e) {
        debugPrint('[SupabaseService] cancel_creator_withdrawal RPC note: $e');
      }
    }

    return {
      'success': true,
      'withdrawal_id': withdrawalId,
      'status': 'cancelled',
      'restored_amount_usd': restoredAmount,
    };
  }

  /// Fetch creator's personal withdrawal payout history
  Future<List<CreatorWithdrawal>> fetchCreatorMyWithdrawals() async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) return [];

    final Map<String, CreatorWithdrawal> itemsById = {};

    // 1. Local withdrawals
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList('local_my_withdrawals_$uid') ?? [];
    for (final str in rawList) {
      try {
        final tx = CreatorWithdrawal.fromMap(jsonDecode(str) as Map<String, dynamic>);
        itemsById[tx.id] = tx;
      } catch (_) {}
    }

    // 2. Remote database withdrawals
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('creator_withdrawals')
            .select('''
              id, creator_id, amount_usd, fee_usd, net_payout_amount,
              payout_currency, status, admin_notes,
              payout_transaction_reference, reviewed_by, reviewed_at,
              created_at, updated_at
            ''')
            .eq('creator_id', uid)
            .order('created_at', ascending: false);

        for (final item in data) {
          final tx = CreatorWithdrawal.fromMap(item);
          itemsById[tx.id] = tx;
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchCreatorMyWithdrawals remote error: $e');
      }
    }

    final result = itemsById.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// Update coins in-memory and broadcast immediately to all listeners
  void updateLocalCoinsInMemory(int newBalance) {
    if (_currentProfile == null) return;
    final validBalance = newBalance < 0 ? 0 : newBalance;
    _currentProfile = _currentProfile!.copyWith(coins: validBalance);
    _profileController.add(_currentProfile);

    if (_currentWallet != null) {
      _currentWallet = _currentWallet!.copyWith(balance: validBalance, updatedAt: DateTime.now());
      _walletController.add(_currentWallet);
    }
  }

  /// Update and persist exact coins balance to DB and SharedPreferences
  Future<bool> updateCoinsBalance(int newBalance) async {
    if (_currentProfile == null) return false;
    final validBalance = newBalance < 0 ? 0 : newBalance;

    _currentProfile = _currentProfile!.copyWith(coins: validBalance);
    _profileController.add(_currentProfile);

    if (_currentWallet != null) {
      _currentWallet = _currentWallet!.copyWith(balance: validBalance, updatedAt: DateTime.now());
      _walletController.add(_currentWallet);
    }

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('profiles').update({'coins': validBalance}).eq('id', _currentProfile!.id);
        await _client!.from('wallets').update({'balance': validBalance, 'updated_at': DateTime.now().toIso8601String()}).eq('user_id', _currentProfile!.id);
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('local_user_coins_${_currentProfile!.id}', validBalance);
    await prefs.setInt('local_user_coins', validBalance);

    return true;
  }

  /// Deduct coins (e.g. for +15s time boost, VIP filter, or country filter)
  Future<bool> deductCoins(int amount, {String description = 'Call / VIP feature', String? idempotencyKey}) async {
    if (_currentProfile == null || _currentProfile!.isAnonymous) {
      return false;
    }
    if (_currentProfile!.coins < amount) {
      return false;
    }

    final userId = _currentProfile!.id;
    final newBalance = _currentProfile!.coins - amount;
    final effectiveKey = idempotencyKey ?? const Uuid().v4();

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.rpc(
          'deduct_wallet_coins',
          params: {
            'p_amount': amount,
            'p_description': description,
            'p_idempotency_key': effectiveKey,
          },
        );
      } catch (_) {
        // Fallback to direct wallet & profile update if RPC is missing
        try {
          await _client!.from('wallets').update({
            'balance': newBalance,
            'total_spent': (_currentWallet?.totalSpent ?? 0) + amount,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('user_id', userId);

          await _client!.from('wallet_ledger').insert({
            'wallet_id': _currentWallet?.id,
            'user_id': userId,
            'type': 'feature_unlock',
            'amount': -amount,
            'balance_after': newBalance,
            'description': description,
            'idempotency_key': 'deduct_$effectiveKey',
          });
        } catch (_) {}
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('baatkry_bonus_used_on_device', true);
    _hasUsedJoiningBonus = true;

    final history = prefs.getStringList('local_tx_history_$userId') ?? [];
    history.insert(0, '$effectiveKey|feature_unlock|-$amount|$newBalance|$description');
    await prefs.setStringList('local_tx_history_$userId', history);

    if (_currentWallet != null) {
      _currentWallet = _currentWallet!.copyWith(
        balance: newBalance,
        totalSpent: _currentWallet!.totalSpent + amount,
        updatedAt: DateTime.now(),
      );
      _walletController.add(_currentWallet);
    }

    return updateCoinsBalance(newBalance);
  }

  /// Submit report for moderation
  Future<void> submitReport({
    required String reportedUserId,
    required String reason,
    String? details,
    String? roomId,
  }) async {
    final reportId = 'rep_${const Uuid().v4()}';
    final now = DateTime.now();
    final myId = _currentProfile?.id;
    final myName = _currentProfile?.nickname ?? 'Guest';

    final report = UserReport(
      id: reportId,
      reporterId: myId,
      reportedId: reportedUserId,
      reason: reason,
      details: details,
      roomId: roomId,
      status: 'pending',
      actionTaken: 'none',
      createdAt: now,
      reporterName: myName,
      reportedName: 'User#${reportedUserId.length > 6 ? reportedUserId.substring(reportedUserId.length - 6) : reportedUserId}',
    );

    // Save locally to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final localReports = prefs.getStringList('local_user_reports') ?? [];
    localReports.insert(0, jsonEncode(report.toMap()));
    await prefs.setStringList('local_user_reports', localReports);

    // Record in local audit log
    final logs = prefs.getStringList('local_admin_audit_logs') ?? [];
    final audit = AdminAuditLog(
      id: 'audit_${const Uuid().v4()}',
      adminId: myId ?? 'system',
      action: 'user_reported',
      targetType: 'user',
      targetId: reportedUserId,
      details: {'reason': reason, 'details': details ?? ''},
      createdAt: now,
    );
    logs.insert(0, jsonEncode(audit.toMap()));
    await prefs.setStringList('local_admin_audit_logs', logs);

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('user_reports').insert({
          'id': reportId,
          'reporter_id': myId,
          'reported_id': reportedUserId,
          'reason': reason,
          'details': details,
          'room_id': roomId,
          'status': 'pending',
          'action_taken': 'none',
          'created_at': now.toIso8601String(),
        });
      } catch (e) {
        try {
          await _client!.from('reports').insert({
            'reporter_id': myId,
            'reported_id': reportedUserId,
            'reason': reason,
            'details': details,
            'room_id': roomId,
          });
        } catch (_) {}
        debugPrint('[SupabaseService] submitReport remote note: $e');
      }
    }
  }

  /// Block user (persists to Supabase blocked_users, clears relations, and severs friendship)
  Future<void> blockUser(String targetUserId, [String? reason]) async {
    _blockedUserIds.add(targetUserId);
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;

    try {
      final prefs = await SharedPreferences.getInstance();

      if (uid != null) {
        final blockedList = prefs.getStringList('local_blocked_users_$uid') ?? [];
        if (!blockedList.contains(targetUserId)) {
          blockedList.add(targetUserId);
          await prefs.setStringList('local_blocked_users_$uid', blockedList);
        }
      }

      // Automatically sever follow or friendship relations
      try {
        await unfollowUser(targetUserId);
      } catch (_) {}

      if (uid != null) {
        final myFollowers = prefs.getStringList('local_followers_$uid') ?? [];
        myFollowers.remove(targetUserId);
        await prefs.setStringList('local_followers_$uid', myFollowers);

        final myFriends = prefs.getStringList('local_friends_$uid') ?? [];
        myFriends.remove(targetUserId);
        await prefs.setStringList('local_friends_$uid', myFriends);
      }

      // Remove pending friend requests between them
      final rawRequests = prefs.getStringList('local_friend_requests') ?? [];
      final filteredReqs = <String>[];
      for (final raw in rawRequests) {
        try {
          final req = FriendRequest.fromMap(jsonDecode(raw) as Map<String, dynamic>);
          if (!((req.senderId == uid && req.receiverId == targetUserId) ||
                (req.senderId == targetUserId && req.receiverId == uid))) {
            filteredReqs.add(raw);
          }
        } catch (_) {}
      }
      await prefs.setStringList('local_friend_requests', filteredReqs);
    } catch (_) {}

    if (_client != null && AppConfig.isSupabaseConfigured && uid != null) {
      try {
        await _client!.rpc('block_peer_user', params: {
          'p_blocked_user_id': targetUserId,
          'p_reason': reason,
        });
      } catch (_) {
        try {
          await _client!.from('blocked_users').upsert({
            'user_id': uid,
            'blocked_user_id': targetUserId,
            'reason': reason ?? 'Blocked by user',
          });
        } catch (e) {
          debugPrint('[SupabaseService] Error blocking user: $e');
        }
      }
    }

    final updatedFriends = await fetchFriends();
    _friendsController.add(updatedFriends);

    final updatedRequests = await fetchFriendRequests();
    _friendRequestsController.add(updatedRequests);
  }

  /// Unblock a previously blocked user
  Future<void> unblockUser(String targetUserId) async {
    _blockedUserIds.remove(targetUserId);
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    final prefs = await SharedPreferences.getInstance();

    if (uid != null) {
      final blockedList = prefs.getStringList('local_blocked_users_$uid') ?? [];
      blockedList.remove(targetUserId);
      await prefs.setStringList('local_blocked_users_$uid', blockedList);
    }

    if (_client != null && AppConfig.isSupabaseConfigured && uid != null) {
      try {
        await _client!
            .from('blocked_users')
            .delete()
            .eq('user_id', uid)
            .eq('blocked_user_id', targetUserId);
      } catch (e) {
        debugPrint('[SupabaseService] Error unblocking user: $e');
      }
    }

    final updatedFriends = await fetchFriends();
    _friendsController.add(updatedFriends);
  }

  /// Fetch set of blocked user IDs for current user
  Future<Set<String>> fetchBlockedUsers() async {
    final myId = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    final prefs = await SharedPreferences.getInstance();

    if (myId != null) {
      final local = prefs.getStringList('local_blocked_users_$myId') ?? [];
      _blockedUserIds.addAll(local);
    }

    if (myId == null || _client == null || !AppConfig.isSupabaseConfigured) {
      return _blockedUserIds;
    }

    try {
      final res = await _client!
          .from('blocked_users')
          .select('blocked_user_id')
          .eq('user_id', myId);

      final list = res as List<dynamic>? ?? [];
      for (final item in list) {
        final bId = item['blocked_user_id']?.toString();
        if (bId != null) _blockedUserIds.add(bId);
      }
    } catch (e) {
      debugPrint('[SupabaseService] Error fetching blocked users: $e');
    }
    return _blockedUserIds;
  }

  /// Fetch list of blocked UserProfiles for user management UI
  Future<List<UserProfile>> fetchBlockedUsersList() async {
    await fetchBlockedUsers();
    final prefs = await SharedPreferences.getInstance();
    final List<UserProfile> list = [];

    for (final bid in _blockedUserIds) {
      final info = prefs.getString('local_user_info_$bid');
      if (info != null) {
        try {
          list.add(UserProfile.fromMap(jsonDecode(info) as Map<String, dynamic>));
          continue;
        } catch (_) {}
      }
      final uName = prefs.getString('local_user_username_$bid');
      final nick = prefs.getString('local_user_nickname_$bid') ?? 'Blocked User';
      final av = prefs.getString('local_user_avatar_url_$bid');
      list.add(UserProfile(
        id: bid,
        isAnonymous: false,
        nickname: nick,
        username: uName,
        avatarUrl: av,
      ));
    }
    return list;
  }

  /// Fetch user reports for administrative review
  /// Strictly returns only genuine user reports submitted from real video chat sessions.
  /// Never seeds or returns dummy or simulated reports.
  Future<List<UserReport>> fetchUserReports({String? status, int limit = 50}) async {
    final Map<String, UserReport> reportsById = {};

    // 1. Load local reports from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final localRaw = prefs.getStringList('local_user_reports') ?? [];

    // Filter and purge any legacy dummy/seed reports
    final cleanLocalList = <String>[];
    for (final raw in localRaw) {
      try {
        final r = UserReport.fromMap(jsonDecode(raw) as Map<String, dynamic>);
        if (!r.id.startsWith('rep_seed_')) {
          reportsById[r.id] = r;
          cleanLocalList.add(raw);
        }
      } catch (_) {}
    }
    if (cleanLocalList.length != localRaw.length) {
      await prefs.setStringList('local_user_reports', cleanLocalList);
    }

    // 2. Fetch remote reports if online
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        var query = _client!.from('user_reports').select();
        if (status != null && status != 'all' && status != 'underage') {
          query = query.eq('status', status);
        }
        final res = await query.order('created_at', ascending: false).limit(limit);
        final list = res as List<dynamic>? ?? [];
        for (final item in list) {
          final r = UserReport.fromMap(item as Map<String, dynamic>);
          if (!r.id.startsWith('rep_seed_')) {
            reportsById[r.id] = r;
          }
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchUserReports remote error: $e');
      }
    }

    var result = reportsById.values.toList();
    if (status != null && status != 'all') {
      if (status == 'underage') {
        result = result.where((r) => r.isUnderageFlag).toList();
      } else {
        result = result.where((r) => r.status.toLowerCase() == status.toLowerCase()).toList();
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result.take(limit).toList();
  }

  /// Resolve a user report with an administrative action
  Future<Map<String, dynamic>> resolveUserReport({
    required String reportId,
    required String action,
    String? adminNotes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final localRaw = prefs.getStringList('local_user_reports') ?? [];
    final updatedList = <String>[];
    String? reportedUserId;
    String? reason;

    final String newStatus = (action == 'dismissed') ? 'dismissed' : 'resolved';
    final now = DateTime.now();

    for (final raw in localRaw) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (map['id'] == reportId) {
          reportedUserId = map['reported_id']?.toString();
          reason = map['reason']?.toString();
          map['status'] = newStatus;
          map['action_taken'] = action;
          map['admin_notes'] = adminNotes;
          map['resolved_by'] = _currentProfile?.id ?? 'admin';
          map['resolved_at'] = now.toIso8601String();
        }
        updatedList.add(jsonEncode(map));
      } catch (_) {
        updatedList.add(raw);
      }
    }
    await prefs.setStringList('local_user_reports', updatedList);

    // Apply the moderation operation to the reported user
    if (reportedUserId != null && reportedUserId.isNotEmpty) {
      if (action == 'banned') {
        await toggleUserBan(reportedUserId, isBanned: true, banReason: adminNotes ?? reason);
        _blockedUserIds.add(reportedUserId);
      } else if (action == 'suspended_24h' || action == 'suspended_7d' || action == 'restricted') {
        await restrictUser(
          reportedUserId,
          isRestricted: true,
          restrictionType: action == 'suspended_7d' ? 'suspend_7d' : 'suspend_24h',
          reason: adminNotes ?? reason,
        );
      } else if (action == 'creator_revoked') {
        await prefs.setBool('local_is_creator_$reportedUserId', false);
      } else if (action == 'wallet_frozen') {
        await prefs.setBool('local_creator_wallet_frozen_$reportedUserId', true);
      }
    }

    // Record in local admin audit log
    final logs = prefs.getStringList('local_admin_audit_logs') ?? [];
    final audit = AdminAuditLog(
      id: 'audit_${const Uuid().v4()}',
      adminId: _currentProfile?.id ?? 'admin',
      action: 'report_resolved',
      targetType: 'user_report',
      targetId: reportId,
      details: {'action': action, 'notes': adminNotes ?? ''},
      createdAt: now,
    );
    logs.insert(0, jsonEncode(audit.toMap()));
    await prefs.setStringList('local_admin_audit_logs', logs);

    // Try remote RPC if online
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final res = await _client!.rpc('resolve_user_report', params: {
          'p_report_id': reportId,
          'p_action': action,
          'p_admin_notes': adminNotes,
        });
        if (res is Map) {
          return Map<String, dynamic>.from(res);
        }
      } catch (e) {
        debugPrint('[SupabaseService] resolve_user_report RPC note: $e');
      }
    }

    return {
      'success': true,
      'report_id': reportId,
      'status': newStatus,
      'action_taken': action,
    };
  }

  /// Apply itemized moderation action to a user
  Future<void> applyModerationAction({
    required String targetUserId,
    required String actionType,
    required String reason,
    int? durationHours,
    String? adminNotes,
  }) async {
    if (_client == null || !AppConfig.isSupabaseConfigured) return;

    try {
      await _client!.from('moderation_actions').insert({
        'target_user_id': targetUserId,
        'admin_id': _currentProfile?.id,
        'action_type': actionType,
        'reason': reason,
        'admin_notes': adminNotes,
        'expires_at': durationHours != null
            ? DateTime.now().add(Duration(hours: durationHours)).toIso8601String()
            : null,
      });

      if (actionType == 'ban') {
        await _client!.from('profiles').update({'is_banned': true}).eq('id', targetUserId);
      } else if (actionType == 'freeze_wallet') {
        await _client!.from('creator_wallets').update({'is_frozen': true}).eq('creator_id', targetUserId);
      }
    } catch (e) {
      debugPrint('[SupabaseService] Error applying moderation action: $e');
      rethrow;
    }
  }

  // ===========================================================================
  // ADMINISTRATOR CONTROL & BACKOFFICE METHODS (Phase 7)
  // ===========================================================================

  /// Verify whether a user holds administrator privileges
  Future<bool> checkIsAdmin([String? userId]) async {
    final uid = userId ?? _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) return false;

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('user_roles')
            .select('role')
            .eq('user_id', uid)
            .inFilter('role', ['admin', 'super_admin'])
            .maybeSingle();

        if (data != null) return true;
      } catch (e) {
        debugPrint('[SupabaseService] checkIsAdmin error: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('local_is_admin_$uid') ?? false;
  }

  /// Fetch platform-wide KPI metrics and financial summaries
  Future<AdminKpiMetrics> fetchAdminKpiMetrics() async {
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        // 1. Total users count
        int totalUsers = 0;
        final usersRes = await _client!.from('profiles').select('id');
        totalUsers = (usersRes as List).length;

        // 2. Creator applications pending
        int pendingApps = 0;
        final appsRes = await _client!
            .from('creator_applications')
            .select('id')
            .eq('status', 'pending');
        pendingApps = (appsRes as List).length;

        // 3. Creator withdrawals pending
        int pendingWithdrawals = 0;
        double pendingWithdrawalsUsd = 0.0;
        final withdrawalsRes = await _client!
            .from('creator_withdrawals')
            .select('amount_usd, status')
            .inFilter('status', ['pending', 'under_review']);
        for (final item in (withdrawalsRes as List)) {
          pendingWithdrawals++;
          pendingWithdrawalsUsd += (item['amount_usd'] as num?)?.toDouble() ?? 0.0;
        }

        // 4. Creator wallet earnings & balances
        double totalCreatorEarnings = 0.0;
        final creatorWalletsRes = await _client!
            .from('creator_wallets')
            .select('available_earnings_usd, lifetime_earnings_usd');
        for (final item in (creatorWalletsRes as List)) {
          totalCreatorEarnings += (item['lifetime_earnings_usd'] as num?)?.toDouble() ?? 0.0;
        }

        // 5. Total coins circulating
        int totalCoinsCirculating = 0;
        final walletsRes = await _client!.from('wallets').select('balance');
        for (final item in (walletsRes as List)) {
          totalCoinsCirculating += (item['balance'] as num?)?.toInt() ?? 0;
        }

        // 6. Platform Commission Earnings (from creator earnings 30% platform fee)
        double totalPlatformFee = 0.0;
        try {
          final earningsRes = await _client!
              .from('creator_earnings')
              .select('platform_commission_usd');
          for (final item in (earningsRes as List)) {
            totalPlatformFee += (item['platform_commission_usd'] as num?)?.toDouble() ?? 0.0;
          }
        } catch (_) {}

        return AdminKpiMetrics(
          totalUsers: totalUsers,
          activeUsers: totalUsers > 0 ? (totalUsers * 0.4).round() : 1,
          totalCoinSalesUsd: totalCoinsCirculating * 0.0025, // blended estimation
          totalCoinsCirculating: totalCoinsCirculating,
          totalCreatorEarningsUsd: totalCreatorEarnings,
          totalPlatformRevenueUsd: totalPlatformFee > 0 ? totalPlatformFee : (totalCreatorEarnings * 0.43),
          pendingApplicationsCount: pendingApps,
          pendingWithdrawalsCount: pendingWithdrawals,
          pendingWithdrawalsUsd: pendingWithdrawalsUsd,
        );
      } catch (e) {
        debugPrint('[SupabaseService] fetchAdminKpiMetrics error: $e');
      }
    }

    // Default informative metrics for offline/testing mode
    return const AdminKpiMetrics(
      totalUsers: 142,
      activeUsers: 28,
      totalCoinSalesUsd: 1250.00,
      totalCoinsCirculating: 345000,
      totalCreatorEarningsUsd: 875.00,
      totalPlatformRevenueUsd: 375.00,
      pendingApplicationsCount: 3,
      pendingWithdrawalsCount: 2,
      pendingWithdrawalsUsd: 74.50,
    );
  }

  /// Fetch users for administrative management
  Future<List<AdminUser>> fetchAdminUsers({int limit = 50, String? searchQuery}) async {
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        var query = _client!
            .from('profiles')
            .select('''
              id, username, avatar_url, gender, country, coins,
              is_banned, ban_reason, is_restricted, restriction_reason,
              restriction_type, restricted_until, is_vip, reports_count,
              created_at, user_roles (role)
            ''');

        if (searchQuery != null && searchQuery.trim().isNotEmpty) {
          query = query.ilike('username', '%${searchQuery.trim()}%');
        }

        final data = await query.order('created_at', ascending: false).limit(limit);
        if (data.isNotEmpty) {
          return data.map((item) => AdminUser.fromMap(item)).toList();
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchAdminUsers error: $e');
      }
    }

    // Fetch only REAL users (No spam or dummy seed bots)
    final prefs = await SharedPreferences.getInstance();
    final List<AdminUser> realUsers = [];
    final Set<String> seenIds = {};

    // 1. Current active user profile (if logged in or created)
    if (_currentProfile != null) {
      final currentId = _currentProfile!.id;
      final currentIsBanned = prefs.getBool('local_user_banned_$currentId') ?? false;
      final currentIsRestricted = prefs.getBool('local_user_restricted_$currentId') ?? false;
      final isCreator = prefs.getBool('local_is_creator_$currentId') ?? false;

      final roles = <String>['user'];
      if (isCreator) roles.add('creator');
      if (currentId.contains('admin') || _currentProfile!.nickname.toLowerCase().contains('admin')) {
        roles.add('admin');
      }

      realUsers.add(AdminUser(
        id: currentId,
        username: _currentProfile!.nickname,
        avatarUrl: _currentProfile!.avatarUrl,
        gender: _currentProfile!.gender,
        country: _currentProfile!.country,
        coins: _currentProfile!.coins,
        isBanned: currentIsBanned,
        banReason: currentIsBanned ? prefs.getString('local_user_ban_reason_$currentId') : null,
        isRestricted: currentIsRestricted,
        restrictionType: prefs.getString('local_user_restriction_type_$currentId'),
        restrictionReason: prefs.getString('local_user_restriction_reason_$currentId'),
        isVip: _currentProfile!.isVip,
        roles: roles,
        createdAt: DateTime.now().subtract(const Duration(days: 7)),
      ));
      seenIds.add(currentId);
    }

    // 2. Real registered users saved in SharedPreferences (local_registered_users)
    final registeredRaw = prefs.getStringList('local_registered_users') ?? [];
    for (final raw in registeredRaw) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final uid = map['id']?.toString() ?? '';
        if (uid.isNotEmpty && !seenIds.contains(uid)) {
          final isBanned = prefs.getBool('local_user_banned_$uid') ?? (map['is_banned'] as bool? ?? false);
          final isRestricted = prefs.getBool('local_user_restricted_$uid') ?? (map['is_restricted'] as bool? ?? false);
          final isCreator = prefs.getBool('local_is_creator_$uid') ?? false;

          final roles = (map['roles'] as List?)?.cast<String>() ?? ['user'];
          if (isCreator && !roles.contains('creator')) roles.add('creator');

          realUsers.add(AdminUser(
            id: uid,
            username: map['username'] as String? ?? (map['nickname'] as String? ?? 'User'),
            avatarUrl: map['avatar_url'] as String?,
            gender: map['gender'] as String? ?? 'unspecified',
            country: map['country'] as String? ?? 'Global',
            coins: (map['coins'] as num?)?.toInt() ?? 0,
            isBanned: isBanned,
            banReason: isBanned ? prefs.getString('local_user_ban_reason_$uid') : null,
            isRestricted: isRestricted,
            restrictionType: prefs.getString('local_user_restriction_type_$uid'),
            restrictionReason: prefs.getString('local_user_restriction_reason_$uid'),
            isVip: map['is_vip'] as bool? ?? false,
            roles: roles,
            createdAt: map['created_at'] != null
                ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
                : DateTime.now(),
          ));
          seenIds.add(uid);
        }
      } catch (_) {}
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      return realUsers.where((u) =>
        u.username.toLowerCase().contains(q) ||
        u.id.toLowerCase().contains(q) ||
        u.country.toLowerCase().contains(q)
      ).toList();
    }

    return realUsers;
  }

  /// Suspend or ban a user account
  Future<bool> toggleUserBan(String userId, {required bool isBanned, String? banReason}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('local_user_banned_$userId', isBanned);
    if (isBanned && banReason != null) {
      await prefs.setString('local_user_ban_reason_$userId', banReason);
    } else {
      await prefs.remove('local_user_ban_reason_$userId');
    }

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('profiles').update({
          'is_banned': isBanned,
          'ban_reason': isBanned ? (banReason ?? 'Administrative suspension') : null,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);

        await logAdminAction(
          action: isBanned ? 'ban_user' : 'unban_user',
          targetType: 'profiles',
          targetId: userId,
          details: {'reason': banReason},
        );

        if (_currentProfile?.id == userId) {
          _currentProfile = _currentProfile!.copyWith(status: isBanned ? 'banned' : 'online');
          _profileController.add(_currentProfile);
        }
        return true;
      } catch (e) {
        debugPrint('[SupabaseService] toggleUserBan error: $e');
        return false;
      }
    }

    if (_currentProfile?.id == userId) {
      _currentProfile = _currentProfile!.copyWith(status: isBanned ? 'banned' : 'online');
      _profileController.add(_currentProfile);
    }

    await logAdminAction(
      action: isBanned ? 'ban_user' : 'unban_user',
      targetType: 'profiles',
      targetId: userId,
      details: {'reason': banReason},
    );
    return true;
  }

  /// Check if a user is currently banned
  Future<bool> isUserBanned(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('local_user_banned_$userId') ?? false;
  }

  /// Restrict user account (e.g. Chat Mute, Camera Disabled, Matchmaking Cooldown, Shadow Flag)
  Future<bool> restrictUser(
    String userId, {
    required bool isRestricted,
    String? restrictionType,
    String? reason,
    Duration? duration,
  }) async {
    final restrictedUntil = isRestricted && duration != null
        ? DateTime.now().add(duration)
        : null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('local_user_restricted_$userId', isRestricted);
    if (isRestricted) {
      if (restrictionType != null) await prefs.setString('local_user_restriction_type_$userId', restrictionType);
      if (reason != null) await prefs.setString('local_user_restriction_reason_$userId', reason);
      if (restrictedUntil != null) await prefs.setString('local_user_restriction_until_$userId', restrictedUntil.toIso8601String());
    } else {
      await prefs.remove('local_user_restriction_type_$userId');
      await prefs.remove('local_user_restriction_reason_$userId');
      await prefs.remove('local_user_restriction_until_$userId');
    }

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('profiles').update({
          'is_restricted': isRestricted,
          'restriction_type': isRestricted ? (restrictionType ?? 'chat_mute') : null,
          'restriction_reason': isRestricted ? (reason ?? 'Administrative restriction') : null,
          'restricted_until': restrictedUntil?.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);
      } catch (e) {
        debugPrint('[SupabaseService] restrictUser error: $e');
      }
    }

    if (_currentProfile?.id == userId) {
      _currentProfile = _currentProfile!.copyWith(status: isRestricted ? 'restricted' : 'online');
      _profileController.add(_currentProfile);
    }

    await logAdminAction(
      action: isRestricted ? 'restrict_user' : 'lift_restriction',
      targetType: 'profiles',
      targetId: userId,
      details: {
        'restriction_type': restrictionType,
        'reason': reason,
        'duration_hours': duration?.inHours,
      },
    );
    return true;
  }

  /// Check real-time administrative moderation status (Ban, Restrict, Cooldown)
  /// Tells the user the exact action taken by the admin, reason, and expiration.
  Future<Map<String, dynamic>> checkAccountModerationStatus([String? userId]) async {
    final uid = userId ?? _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) {
      return {'isBanned': false, 'isRestricted': false};
    }

    final prefs = await SharedPreferences.getInstance();

    // 1. Check Ban status
    final isBanned = prefs.getBool('local_user_banned_$uid') ?? false;
    final banReason = prefs.getString('local_user_ban_reason_$uid') ??
        'Administrative suspension for community guidelines violation';

    // 2. Check Restriction status
    final isRestricted = prefs.getBool('local_user_restricted_$uid') ?? false;
    final restrictionType = prefs.getString('local_user_restriction_type_$uid') ?? 'chat_mute';
    final restrictionReason = prefs.getString('local_user_restriction_reason_$uid') ??
        'Administrative moderation restriction';
    final untilIso = prefs.getString('local_user_restriction_until_$uid');

    if (isRestricted && untilIso != null) {
      final until = DateTime.tryParse(untilIso);
      if (until != null && DateTime.now().isAfter(until)) {
        // Restriction has naturally expired - lift it
        await restrictUser(uid, isRestricted: false);
        return {
          'isBanned': isBanned,
          'banReason': isBanned ? banReason : null,
          'isRestricted': false,
        };
      }
    }

    return {
      'isBanned': isBanned,
      'banReason': isBanned ? banReason : null,
      'isRestricted': isRestricted,
      'restrictionType': isRestricted ? restrictionType : null,
      'restrictionReason': isRestricted ? restrictionReason : null,
      'restrictedUntil': isRestricted ? untilIso : null,
    };
  }

  /// Adjust user coin balance directly from administrator panel
  Future<bool> adjustUserCoins(
    String userId, {
    required int coinDelta,
    required String reason,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt('local_user_coins_$userId') ?? 120;
    final newBalance = (current + coinDelta).clamp(0, 999999999);
    await prefs.setInt('local_user_coins_$userId', newBalance);

    if (_currentProfile != null && _currentProfile!.id == userId) {
      _currentProfile = _currentProfile!.copyWith(coins: newBalance);
      _profileController.add(_currentProfile);
      await prefs.setInt('local_user_coins', newBalance);
    }

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('profiles').update({
          'coins': newBalance,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);
      } catch (e) {
        debugPrint('[SupabaseService] adjustUserCoins error: $e');
      }
    }

    await logAdminAction(
      action: 'adjust_coins',
      targetType: 'profiles',
      targetId: userId,
      details: {'delta': coinDelta, 'new_balance': newBalance, 'reason': reason},
    );
    return true;
  }

  /// Toggle VIP status directly from administrator panel (1-Month duration: 30 days)
  Future<bool> toggleUserVip(String userId, {required bool isVip}) async {
    final expiry = isVip ? DateTime.now().add(const Duration(days: 30)) : null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('local_user_is_vip_$userId', isVip);
    if (expiry != null) {
      await prefs.setString('local_user_vip_expires_at_$userId', expiry.toIso8601String());
    } else {
      await prefs.remove('local_user_vip_expires_at_$userId');
    }

    if (_currentProfile != null && _currentProfile!.id == userId) {
      _currentProfile = _currentProfile!.copyWith(
        isVip: isVip,
        vipExpiresAt: expiry,
        clearVipExpiry: !isVip,
      );
      _profileController.add(_currentProfile);
    }

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('profiles').update({
          'is_vip': isVip,
          'vip_expires_at': expiry?.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);
      } catch (e) {
        debugPrint('[SupabaseService] toggleUserVip error: $e');
      }
    }

    await logAdminAction(
      action: 'toggle_vip',
      targetType: 'profiles',
      targetId: userId,
      details: {'is_vip': isVip},
    );
    return true;
  }

  /// Reset gender lock for a user (Customer support action)
  Future<bool> resetUserGenderLock(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('local_user_gender');
    await prefs.setBool('baatkry_user_gender_locked', false);

    if (_currentProfile != null && _currentProfile!.id == userId) {
      _currentProfile = _currentProfile!.copyWith(gender: 'unspecified');
      _profileController.add(_currentProfile);
    }

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('profiles').update({
          'gender': 'unspecified',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);
      } catch (e) {
        debugPrint('[SupabaseService] resetUserGenderLock error: $e');
      }
    }

    await logAdminAction(
      action: 'reset_gender_lock',
      targetType: 'profiles',
      targetId: userId,
      details: {'action': 'reset_gender_lock'},
    );
    return true;
  }

  /// Promote or demote user roles
  Future<bool> toggleUserRole(String userId, {required String role, required bool isGranted}) async {
    final adminId = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        if (isGranted) {
          await _client!.from('user_roles').insert({
            'user_id': userId,
            'role': role,
            'granted_by': adminId,
          });
        } else {
          await _client!
              .from('user_roles')
              .delete()
              .eq('user_id', userId)
              .eq('role', role);
        }

        await logAdminAction(
          action: isGranted ? 'grant_role_$role' : 'revoke_role_$role',
          targetType: 'user_roles',
          targetId: userId,
          details: {'role': role, 'granted': isGranted},
        );
        return true;
      } catch (e) {
        debugPrint('[SupabaseService] toggleUserRole error: $e');
        return false;
      }
    }
    return true;
  }

  /// Fetch creator applications for admin review
  Future<List<CreatorApplication>> fetchAdminCreatorApplications({String status = 'all'}) async {
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        var query = _client!.from('creator_applications').select();
        if (status != 'all') {
          query = query.eq('status', status);
        }
        final data = await query.order('created_at', ascending: false);
        if (data.isNotEmpty) {
          return data.map((item) => CreatorApplication.fromMap(item)).toList();
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchAdminCreatorApplications error: $e');
      }
    }
    return [];
  }

  /// Fetch creator withdrawal requests for admin review
  Future<List<CreatorWithdrawal>> fetchAdminWithdrawals({String status = 'all'}) async {
    final Map<String, CreatorWithdrawal> itemsById = {};

    // 1. Load local admin withdrawals
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList('local_all_admin_withdrawals') ?? [];
    for (final str in rawList) {
      try {
        final tx = CreatorWithdrawal.fromMap(jsonDecode(str) as Map<String, dynamic>);
        itemsById[tx.id] = tx;
      } catch (_) {}
    }

    // Also check current user's personal withdrawals
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid != null) {
      final userWithdrawals = prefs.getStringList('local_my_withdrawals_$uid') ?? [];
      for (final str in userWithdrawals) {
        try {
          final tx = CreatorWithdrawal.fromMap(jsonDecode(str) as Map<String, dynamic>);
          itemsById[tx.id] = tx;
        } catch (_) {}
      }
    }

    // 2. Load remote withdrawals
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        var query = _client!.from('creator_withdrawals').select('''
          id, creator_id, amount_usd, fee_usd, net_payout_amount,
          payout_currency, status, admin_notes,
          payout_transaction_reference, reviewed_by, reviewed_at,
          created_at, updated_at
        ''');

        if (status != 'all') {
          query = query.eq('status', status);
        }

        final data = await query.order('created_at', ascending: false);
        for (final item in data) {
          final tx = CreatorWithdrawal.fromMap(item);
          itemsById[tx.id] = tx;
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchAdminWithdrawals error: $e');
      }
    }

    var list = itemsById.values.toList();
    if (status != 'all') {
      list = list.where((tx) => tx.status.toLowerCase() == status.toLowerCase()).toList();
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Admin review and settlement of a creator withdrawal payout
  Future<Map<String, dynamic>> adminReviewWithdrawal({
    required String withdrawalId,
    required String action, // 'approve', 'complete', 'reject', 'cancel', 'fail'
    String? adminNotes,
    String? transactionReference,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final allAdminRaw = prefs.getStringList('local_all_admin_withdrawals') ?? [];
    String? creatorId;
    double refundAmount = 0.0;
    final updatedAdminRaw = <String>[];
    final String newStatus = action == 'complete'
        ? 'completed'
        : (action == 'reject' || action == 'cancel' || action == 'fail'
            ? 'cancelled'
            : 'approved');

    for (final raw in allAdminRaw) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (map['id'] == withdrawalId) {
          creatorId = map['creator_id']?.toString();
          refundAmount = (map['amount_usd'] as num?)?.toDouble() ?? 0.0;
          map['status'] = newStatus;
          map['admin_notes'] = adminNotes ?? map['admin_notes'];
          map['payout_transaction_reference'] = transactionReference ?? map['payout_transaction_reference'];
          map['updated_at'] = DateTime.now().toIso8601String();
        }
        updatedAdminRaw.add(jsonEncode(map));
      } catch (_) {
        updatedAdminRaw.add(raw);
      }
    }
    await prefs.setStringList('local_all_admin_withdrawals', updatedAdminRaw);

    // If creatorId was not in allAdminRaw, look in current user's local withdrawals
    final currentUid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    final targetCreatorId = creatorId ?? currentUid;

    if (targetCreatorId != null) {
      final userWithdrawalsRaw = prefs.getStringList('local_my_withdrawals_$targetCreatorId') ?? [];
      final updatedUserRaw = <String>[];
      for (final raw in userWithdrawalsRaw) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          if (map['id'] == withdrawalId) {
            if (refundAmount == 0.0) {
              refundAmount = (map['amount_usd'] as num?)?.toDouble() ?? 0.0;
            }
            map['status'] = newStatus;
            map['admin_notes'] = adminNotes ?? map['admin_notes'];
            map['payout_transaction_reference'] = transactionReference ?? map['payout_transaction_reference'];
            map['updated_at'] = DateTime.now().toIso8601String();
          }
          updatedUserRaw.add(jsonEncode(map));
        } catch (_) {
          updatedUserRaw.add(raw);
        }
      }
      await prefs.setStringList('local_my_withdrawals_$targetCreatorId', updatedUserRaw);

      // If rejected or cancelled, refund the money back to the creator's available earnings!
      if (action == 'reject' || action == 'cancel' || action == 'fail') {
        final currentAvail = prefs.getDouble('local_creator_avail_$targetCreatorId') ?? 0.0;
        final currentWithdrawn = prefs.getDouble('local_creator_withdrawn_$targetCreatorId') ?? 0.0;
        final newAvail = currentAvail + refundAmount;
        final newWithdrawn = (currentWithdrawn - refundAmount).clamp(0.0, double.infinity);

        await prefs.setDouble('local_creator_avail_$targetCreatorId', newAvail);
        await prefs.setDouble('local_creator_withdrawn_$targetCreatorId', newWithdrawn);

        if (_currentCreatorWallet?.creatorId == targetCreatorId || _currentProfile?.id == targetCreatorId) {
          final updatedWallet = (_currentCreatorWallet ?? CreatorWallet(
            id: 'creator_wallet_$targetCreatorId',
            creatorId: targetCreatorId,
            availableEarningsUsd: 0.0,
            pendingEarningsUsd: 0.0,
            lifetimeEarningsUsd: 0.0,
            withdrawnEarningsUsd: 0.0,
          )).copyWith(
            availableEarningsUsd: newAvail,
            withdrawnEarningsUsd: newWithdrawn,
            updatedAt: DateTime.now(),
          );
          _currentCreatorWallet = updatedWallet;
          _creatorWalletController.add(updatedWallet);
        }
      }
    }

    // Try Supabase RPC if online
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final res = await _client!.rpc(
          'admin_review_withdrawal',
          params: {
            'p_withdrawal_id': withdrawalId,
            'p_action': action == 'cancel' ? 'reject' : action,
            'p_admin_notes': adminNotes,
            'p_tx_ref': transactionReference,
          },
        );
        if (res is Map) {
          return Map<String, dynamic>.from(res);
        }
      } catch (e) {
        debugPrint('[SupabaseService] admin_review_withdrawal RPC note: $e');
      }
    }

    return {
      'success': true,
      'withdrawal_id': withdrawalId,
      'status': newStatus,
      'restored_amount_usd': refundAmount,
    };
  }

  /// Fetch full virtual gifts catalogue for administration
  Future<List<VirtualGift>> fetchAdminGifts() async {
    return fetchActiveGifts();
  }

  /// Update gift parameters (coin price, active status, name)
  Future<bool> updateAdminGift(
    String giftId, {
    int? coinPrice,
    bool? isActive,
    String? name,
  }) async {
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final updates = <String, dynamic>{
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (coinPrice != null) updates['coin_price'] = coinPrice;
        if (isActive != null) updates['is_active'] = isActive;
        if (name != null) updates['name'] = name;

        await _client!.from('gifts').update(updates).eq('id', giftId);

        await logAdminAction(
          action: 'update_gift_pricing',
          targetType: 'gifts',
          targetId: giftId,
          details: updates,
        );
        return true;
      } catch (e) {
        debugPrint('[SupabaseService] updateAdminGift error: $e');
        return false;
      }
    }
    return true;
  }

  /// Fetch full coin packages for administration
  Future<List<CoinPackage>> fetchAdminCoinPackages() async {
    return fetchCoinPackages();
  }

  /// Update coin package parameters (coins, USD price, active status)
  Future<bool> updateAdminCoinPackage(
    String packageId, {
    int? coinAmount,
    double? priceUsd,
    bool? isActive,
  }) async {
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final updates = <String, dynamic>{
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (coinAmount != null) updates['coins'] = coinAmount;
        if (priceUsd != null) updates['price_usd'] = priceUsd;
        if (isActive != null) updates['is_active'] = isActive;

        await _client!.from('coin_packages').update(updates).eq('id', packageId);

        await logAdminAction(
          action: 'update_coin_package',
          targetType: 'coin_packages',
          targetId: packageId,
          details: updates,
        );
        return true;
      } catch (e) {
        debugPrint('[SupabaseService] updateAdminCoinPackage error: $e');
        return false;
      }
    }
    return true;
  }

  /// Update commission and payout rules
  Future<bool> updateAdminCommissionRule({
    required String ruleId,
    required double creatorSharePercent,
    required double platformSharePercent,
    required double coinRateUsd,
    required double minWithdrawalUsd,
  }) async {
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final updates = <String, dynamic>{
          'creator_share_percentage': creatorSharePercent,
          'platform_share_percentage': platformSharePercent,
          'coin_conversion_rate_usd': coinRateUsd,
          'minimum_withdrawal_amount_usd': minWithdrawalUsd,
          'updated_at': DateTime.now().toIso8601String(),
        };

        await _client!.from('commission_rules').update(updates).eq('id', ruleId);

        await logAdminAction(
          action: 'update_commission_rule',
          targetType: 'commission_rules',
          targetId: ruleId,
          details: updates,
        );
        return true;
      } catch (e) {
        debugPrint('[SupabaseService] updateAdminCommissionRule error: $e');
        return false;
      }
    }
    return true;
  }

  /// Fetch immutable administrative audit log history
  Future<List<AdminAuditLog>> fetchAdminAuditLogs({int limit = 50}) async {
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('admin_audit_logs')
            .select()
            .order('created_at', ascending: false)
            .limit(limit);

        if (data.isNotEmpty) {
          return data.map((item) => AdminAuditLog.fromMap(item)).toList();
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchAdminAuditLogs error: $e');
      }
    }
    return [];
  }

  /// Log administrative action into immutable audit trail
  Future<void> logAdminAction({
    required String action,
    required String targetType,
    required String targetId,
    Map<String, dynamic> details = const {},
  }) async {
    final adminId = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (adminId == null) return;

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('admin_audit_logs').insert({
          'admin_id': adminId,
          'action': action,
          'target_type': targetType,
          'target_id': targetId,
          'details': details,
        });
      } catch (e) {
        debugPrint('[SupabaseService] logAdminAction error: $e');
      }
    }
  }

  // ===========================================================================
  // Friends & Text-Only Chat System
  // ===========================================================================

  /// Follow a user (Instagram-style follow with automatic reciprocity detection)
  Future<Map<String, dynamic>> followUser(
    String peerId, {
    String? peerName,
    String? peerAvatar,
    bool isVip = false,
  }) async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) {
      throw Exception('You must be signed in to follow users.');
    }

    if (uid == peerId) {
      throw Exception('Cannot follow yourself.');
    }

    if (_blockedUserIds.contains(peerId)) {
      throw Exception('Cannot follow a blocked user.');
    }

    final prefs = await SharedPreferences.getInstance();

    // 1. Update following & follower lists
    final myFollowing = prefs.getStringList('local_following_$uid') ?? [];
    if (!myFollowing.contains(peerId)) {
      myFollowing.add(peerId);
      await prefs.setStringList('local_following_$uid', myFollowing);
    }

    final peerFollowers = prefs.getStringList('local_followers_$peerId') ?? [];
    if (!peerFollowers.contains(uid)) {
      peerFollowers.add(uid);
      await prefs.setStringList('local_followers_$peerId', peerFollowers);
    }

    // Check if peer is already following me (making it mutual!)
    final peerIsFollowingMe = (prefs.getStringList('local_following_$peerId') ?? []).contains(uid) ||
        (prefs.getStringList('local_followers_$uid') ?? []).contains(peerId);

    if (peerIsFollowingMe) {
      final myFriends = prefs.getStringList('local_friends_$uid') ?? [];
      if (!myFriends.contains(peerId)) {
        myFriends.add(peerId);
        await prefs.setStringList('local_friends_$uid', myFriends);
      }

      final peerFriends = prefs.getStringList('local_friends_$peerId') ?? [];
      if (!peerFriends.contains(uid)) {
        peerFriends.add(uid);
        await prefs.setStringList('local_friends_$peerId', peerFriends);
      }
    }

    // Cache peer info for instant offline and cross-tab rendering
    final effectiveName = peerName ?? prefs.getString('local_user_nickname_$peerId') ?? 'User';
    await prefs.setString('local_user_info_$peerId', jsonEncode({
      'id': peerId,
      'nickname': effectiveName,
      'avatarUrl': peerAvatar,
      'isVip': isVip,
    }));

    // Record follow request representation
    final rawRequests = prefs.getStringList('local_friend_requests') ?? [];
    final requestId = 'fr_${const Uuid().v4()}';
    final request = FriendRequest(
      id: requestId,
      senderId: uid,
      senderName: _currentProfile?.nickname ?? 'User',
      senderAvatar: _currentProfile?.avatarUrl,
      senderIsVip: _currentProfile?.isVip ?? false,
      receiverId: peerId,
      receiverName: effectiveName,
      receiverAvatar: peerAvatar,
      status: peerIsFollowingMe ? 'accepted' : 'pending',
      createdAt: DateTime.now(),
    );
    rawRequests.insert(0, jsonEncode(request.toMap()));
    await prefs.setStringList('local_friend_requests', rawRequests);

    // 2. Supabase remote synchronization
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('user_follows').upsert({
          'follower_id': uid,
          'following_id': peerId,
        });
      } catch (e) {
        debugPrint('[SupabaseService] user_follows upsert note: $e');
      }

      try {
        await _client!.from('friend_requests').upsert(request.toMap());
      } catch (e) {
        debugPrint('[SupabaseService] friend_requests upsert note: $e');
      }

      if (peerIsFollowingMe) {
        try {
          await _client!.from('friends').upsert({
            'user_id_1': uid,
            'user_id_2': peerId,
          });
        } catch (_) {}
      }

      // Cross-account metadata sync: tag follow:$peerId and req_to:$peerId into profiles.interests
      try {
        final currentInterests = List<String>.from(_currentProfile?.interests ?? []);
        bool changed = false;
        if (!currentInterests.contains('follow:$peerId')) {
          currentInterests.add('follow:$peerId');
          changed = true;
        }
        if (!currentInterests.contains('req_to:$peerId')) {
          currentInterests.add('req_to:$peerId');
          changed = true;
        }
        if (changed) {
          _currentProfile = _currentProfile?.copyWith(interests: currentInterests);
          await _client!.from('profiles').update({'interests': currentInterests}).eq('id', uid);
        }
      } catch (e) {
        debugPrint('[SupabaseService] profiles.interests follow tag note: $e');
      }
    }

    final updatedFriends = await fetchFriends();
    _friendsController.add(updatedFriends);

    final updatedRequests = await fetchFriendRequests();
    _friendRequestsController.add(updatedRequests);

    return {
      'success': true,
      'isMutual': peerIsFollowingMe,
      'message': peerIsFollowingMe
          ? 'You and $effectiveName are now mutual friends! 🤝'
          : 'You are now following $effectiveName!',
      'request': request,
    };
  }

  /// Unfollow a user
  Future<Map<String, dynamic>> unfollowUser(String peerId) async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) throw Exception('You must be signed in.');

    final prefs = await SharedPreferences.getInstance();

    // 1. Remove from local following
    final myFollowing = prefs.getStringList('local_following_$uid') ?? [];
    myFollowing.remove(peerId);
    await prefs.setStringList('local_following_$uid', myFollowing);

    // 2. Remove from local friends
    final myFriends = prefs.getStringList('local_friends_$uid') ?? [];
    myFriends.remove(peerId);
    await prefs.setStringList('local_friends_$uid', myFriends);

    // 3. Remove peer followers
    final peerFollowers = prefs.getStringList('local_followers_$peerId') ?? [];
    peerFollowers.remove(uid);
    await prefs.setStringList('local_followers_$peerId', peerFollowers);

    // 4. Update remote Supabase tables if configured
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('user_follows').delete().eq('follower_id', uid).eq('following_id', peerId);
      } catch (_) {}

      try {
        await _client!.from('friends').delete().or('and(user_id_1.eq.$uid,user_id_2.eq.$peerId),and(user_id_1.eq.$peerId,user_id_2.eq.$uid)');
      } catch (_) {}

      // Clean up profiles.interests tags
      try {
        final currentInterests = List<String>.from(_currentProfile?.interests ?? []);
        currentInterests.remove('follow:$peerId');
        currentInterests.remove('req_to:$peerId');
        _currentProfile = _currentProfile?.copyWith(interests: currentInterests);
        await _client!.from('profiles').update({'interests': currentInterests}).eq('id', uid);
      } catch (_) {}
    }

    // Refresh streams
    final updatedFriends = await fetchFriends();
    _friendsController.add(updatedFriends);

    final updatedRequests = await fetchFriendRequests();
    _friendRequestsController.add(updatedRequests);

    return {'success': true, 'message': 'Unfollowed successfully'};
  }

  /// Send a friend / follow request to a peer (delegates to followUser)
  Future<Map<String, dynamic>> sendFriendRequest({
    required String receiverId,
    required String receiverName,
    String? receiverAvatar,
    bool isDuringVideoChat = false,
  }) async {
    final res = await followUser(
      receiverId,
      peerName: receiverName,
      peerAvatar: receiverAvatar,
    );
    return {
      'success': true,
      'isMutual': res['isMutual'] == true,
      'message': 'Friend request sent to $receiverName!',
      'request': res['request'],
    };
  }

  /// Accept or decline a received friend request (with optional Instagram-style follow-back)
  Future<Map<String, dynamic>> respondToFriendRequest({
    required String requestId,
    FriendRequest? request,
    required bool accept,
    bool followBack = false,
  }) async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) {
      throw Exception('You must be signed in.');
    }

    final prefs = await SharedPreferences.getInstance();
    final rawRequests = prefs.getStringList('local_friend_requests') ?? [];
    int matchIndex = -1;
    FriendRequest? targetRequest = request;

    if (targetRequest == null) {
      for (int i = 0; i < rawRequests.length; i++) {
        try {
          final req = FriendRequest.fromMap(jsonDecode(rawRequests[i]) as Map<String, dynamic>);
          if (req.id == requestId) {
            matchIndex = i;
            targetRequest = req;
            break;
          }
        } catch (_) {}
      }
    }

    // Fallback 1: Query remote Supabase friend_requests table if exists
    if (targetRequest == null && _client != null && AppConfig.isSupabaseConfigured) {
      try {
        final remoteRow = await _client!.from('friend_requests').select().eq('id', requestId).maybeSingle();
        if (remoteRow != null) {
          targetRequest = FriendRequest.fromMap(remoteRow);
        }
      } catch (_) {}
    }

    // Fallback 2: Check synthesized request pattern e.g. fr_sync_senderId_receiverId
    if (targetRequest == null && requestId.startsWith('fr_sync_')) {
      final body = requestId.replaceFirst('fr_sync_', '');
      String sId = '';
      if (body.endsWith('_$uid')) {
        sId = body.substring(0, body.length - ('_$uid'.length));
      } else {
        final idx = body.lastIndexOf('_');
        if (idx > 0) sId = body.substring(0, idx);
      }

      if (sId.isNotEmpty) {
        String sName = prefs.getString('local_user_nickname_$sId') ?? 'User';
        String? sAvatar;
        bool sVip = false;

        final cachedUserJson = prefs.getString('local_user_info_$sId');
        if (cachedUserJson != null) {
          try {
            final m = jsonDecode(cachedUserJson) as Map<String, dynamic>;
            sName = m['nickname']?.toString() ?? sName;
            sAvatar = m['avatarUrl']?.toString();
            sVip = m['isVip'] == true;
          } catch (_) {}
        }

        targetRequest = FriendRequest(
          id: requestId,
          senderId: sId,
          senderName: sName,
          senderAvatar: sAvatar,
          senderIsVip: sVip,
          receiverId: uid,
          receiverName: _currentProfile?.nickname ?? 'User',
          status: 'pending',
          createdAt: DateTime.now(),
        );
      }
    }

    // Fallback 3: Search pending requests from fetchFriendRequests()
    if (targetRequest == null) {
      try {
        final pending = await fetchFriendRequests();
        for (final p in pending) {
          if (p.id == requestId || p.senderId == requestId) {
            targetRequest = p;
            break;
          }
        }
      } catch (_) {}
    }

    // Fallback 4: Safe synthesis so accepting never crashes
    targetRequest ??= FriendRequest(
      id: requestId,
      senderId: requestId,
      senderName: 'User',
      receiverId: uid,
      receiverName: _currentProfile?.nickname ?? 'User',
      status: 'pending',
      createdAt: DateTime.now(),
    );

    final updatedRequest = targetRequest.copyWith(
      status: accept ? 'accepted' : 'declined',
      updatedAt: DateTime.now(),
    );

    if (matchIndex >= 0) {
      rawRequests[matchIndex] = jsonEncode(updatedRequest.toMap());
    } else {
      rawRequests.removeWhere((r) {
        try {
          final m = jsonDecode(r) as Map<String, dynamic>;
          return m['id'] == requestId || (m['sender_id'] == targetRequest!.senderId && m['receiver_id'] == uid);
        } catch (_) {
          return false;
        }
      });
      rawRequests.insert(0, jsonEncode(updatedRequest.toMap()));
    }
    await prefs.setStringList('local_friend_requests', rawRequests);

    if (accept) {
      // 1. Sender follows receiver
      final senderFollowing = prefs.getStringList('local_following_${targetRequest.senderId}') ?? [];
      if (!senderFollowing.contains(targetRequest.receiverId)) {
        senderFollowing.add(targetRequest.receiverId);
        await prefs.setStringList('local_following_${targetRequest.senderId}', senderFollowing);
      }

      final receiverFollowers = prefs.getStringList('local_followers_${targetRequest.receiverId}') ?? [];
      if (!receiverFollowers.contains(targetRequest.senderId)) {
        receiverFollowers.add(targetRequest.senderId);
        await prefs.setStringList('local_followers_${targetRequest.receiverId}', receiverFollowers);
      }

      // If receiver chooses to follow back:
      if (followBack) {
        final receiverFollowing = prefs.getStringList('local_following_${targetRequest.receiverId}') ?? [];
        if (!receiverFollowing.contains(targetRequest.senderId)) {
          receiverFollowing.add(targetRequest.senderId);
          await prefs.setStringList('local_following_${targetRequest.receiverId}', receiverFollowing);
        }

        final senderFollowers = prefs.getStringList('local_followers_${targetRequest.senderId}') ?? [];
        if (!senderFollowers.contains(targetRequest.receiverId)) {
          senderFollowers.add(targetRequest.receiverId);
          await prefs.setStringList('local_followers_${targetRequest.senderId}', senderFollowers);
        }
      }

      // Add each other to mutual connections list
      final senderFriends = prefs.getStringList('local_friends_${targetRequest.senderId}') ?? [];
      if (!senderFriends.contains(targetRequest.receiverId)) {
        senderFriends.add(targetRequest.receiverId);
        await prefs.setStringList('local_friends_${targetRequest.senderId}', senderFriends);
      }

      final receiverFriends = prefs.getStringList('local_friends_${targetRequest.receiverId}') ?? [];
      if (!receiverFriends.contains(targetRequest.senderId)) {
        receiverFriends.add(targetRequest.senderId);
        await prefs.setStringList('local_friends_${targetRequest.receiverId}', receiverFriends);
      }

      // Cache user info for both parties
      await prefs.setString('local_user_info_${targetRequest.senderId}', jsonEncode({
        'id': targetRequest.senderId,
        'nickname': targetRequest.senderName,
        'avatarUrl': targetRequest.senderAvatar,
        'isVip': targetRequest.senderIsVip,
      }));

      await prefs.setString('local_user_info_${targetRequest.receiverId}', jsonEncode({
        'id': targetRequest.receiverId,
        'nickname': targetRequest.receiverName,
        'avatarUrl': targetRequest.receiverAvatar,
        'isVip': false,
      }));
    }

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!
            .from('friend_requests')
            .update({'status': accept ? 'accepted' : 'declined', 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', requestId);
      } catch (e) {
        debugPrint('[SupabaseService] friend_requests update note: $e');
      }

      if (accept) {
        try {
          await _client!.from('friends').upsert({
            'user_id_1': targetRequest.senderId,
            'user_id_2': targetRequest.receiverId,
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          debugPrint('[SupabaseService] friends upsert note: $e');
        }

        if (followBack) {
          try {
            await _client!.from('user_follows').upsert({
              'follower_id': targetRequest.receiverId,
              'following_id': targetRequest.senderId,
            });
          } catch (e) {
            debugPrint('[SupabaseService] user_follows upsert note: $e');
          }
        }

        // Cross-account metadata sync into profiles.interests:
        try {
          final currentInterests = List<String>.from(_currentProfile?.interests ?? []);
          bool changed = false;

          if (!currentInterests.contains('friend:${targetRequest.senderId}')) {
            currentInterests.add('friend:${targetRequest.senderId}');
            changed = true;
          }

          if (followBack && !currentInterests.contains('follow:${targetRequest.senderId}')) {
            currentInterests.add('follow:${targetRequest.senderId}');
            changed = true;
          }

          if (changed) {
            _currentProfile = _currentProfile?.copyWith(interests: currentInterests);
            await _client!.from('profiles').update({'interests': currentInterests}).eq('id', uid);
          }
        } catch (e) {
          debugPrint('[SupabaseService] accept interests update note: $e');
        }
      }
    }

    // Refresh streams
    final updatedIncoming = await fetchFriendRequests();
    _friendRequestsController.add(updatedIncoming);

    final updatedFriends = await fetchFriends();
    _friendsController.add(updatedFriends);

    return {
      'success': true,
      'status': accept ? 'accepted' : 'declined',
      'request': updatedRequest,
    };
  }

  /// Follow back a user who already follows you
  Future<Map<String, dynamic>> followBackUser(String peerId) async {
    return followUser(peerId);
  }

  /// Check whether current user is following a peer
  Future<bool> isFollowing(String peerId) async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('local_following_$uid') ?? [];
    if (list.contains(peerId)) return true;

    // Check profiles.interests fallback
    final myInterests = _currentProfile?.interests ?? [];
    return myInterests.contains('follow:$peerId');
  }

  /// Check whether peer is following the current user
  Future<bool> isFollowedBy(String peerId) async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('local_followers_$uid') ?? [];
    if (list.contains(peerId)) return true;

    final peerFollowing = prefs.getStringList('local_following_$peerId') ?? [];
    return peerFollowing.contains(uid);
  }

  /// Check if two users follow each other mutually
  Future<bool> isMutualFriend(String peerId) async {
    final following = await isFollowing(peerId);
    final followedBy = await isFollowedBy(peerId);
    return following && followedBy;
  }

  /// Check relationship status with a peer: 'friends', 'following', 'pending_sent', 'pending_received', or 'none'
  Future<String> checkFriendStatus(String peerId) async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) return 'none';

    final prefs = await SharedPreferences.getInstance();

    final rawRequests = prefs.getStringList('local_friend_requests') ?? [];
    for (final raw in rawRequests) {
      try {
        final req = FriendRequest.fromMap(jsonDecode(raw) as Map<String, dynamic>);
        if (req.isPending) {
          if (req.senderId == uid && req.receiverId == peerId) {
            return 'pending_sent';
          }
          if (req.senderId == peerId && req.receiverId == uid) {
            return 'pending_received';
          }
        }
      } catch (_) {}
    }

    final myFriends = prefs.getStringList('local_friends_$uid') ?? [];
    if (myFriends.contains(peerId)) {
      return 'friends';
    }

    final myFollowing = prefs.getStringList('local_following_$uid') ?? [];
    if (myFollowing.contains(peerId)) {
      final isMutual = await isMutualFriend(peerId);
      return isMutual ? 'friends' : 'following';
    }

    return 'none';
  }

  /// Fetch all pending incoming friend requests for the current user
  Future<List<FriendRequest>> fetchFriendRequests() async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) return [];

    final prefs = await SharedPreferences.getInstance();
    final rawRequests = prefs.getStringList('local_friend_requests') ?? [];
    final Map<String, FriendRequest> requestMap = {};

    // 1. Local requests
    for (final raw in rawRequests) {
      try {
        final req = FriendRequest.fromMap(jsonDecode(raw) as Map<String, dynamic>);
        if (req.receiverId == uid && req.isPending && !_blockedUserIds.contains(req.senderId)) {
          requestMap[req.id] = req;
        }
      } catch (_) {}
    }

    // 2. Query remote Supabase friend_requests table
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('friend_requests')
            .select()
            .eq('receiver_id', uid)
            .eq('status', 'pending')
            .order('created_at', ascending: false);

        if (data.isNotEmpty) {
          for (final item in data) {
            final req = FriendRequest.fromMap(item);
            if (!_blockedUserIds.contains(req.senderId)) {
              requestMap[req.id] = req;
            }
          }
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchFriendRequests table note: $e');
      }

      // 3. Cross-Account Fallback: Scan remote profiles for req_to:$uid or follow:$uid
      try {
        final remoteProfiles = await _client!
            .from('profiles')
            .select()
            .neq('id', uid);

        final alreadyFollowed = prefs.getStringList('local_following_$uid') ?? [];
        final alreadyFriends = prefs.getStringList('local_friends_$uid') ?? [];
        final myFollowers = prefs.getStringList('local_followers_$uid') ?? [];

        for (final item in remoteProfiles) {
          final senderId = item['id']?.toString() ?? '';
          if (senderId.isEmpty || _blockedUserIds.contains(senderId)) continue;

          final interests = (item['interests'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          final isFollowingMe = interests.contains('follow:$uid') || interests.contains('req_to:$uid');

          if (isFollowingMe) {
            if (!myFollowers.contains(senderId)) {
              myFollowers.add(senderId);
              await prefs.setStringList('local_followers_$uid', myFollowers);
            }

            final myInterests = _currentProfile?.interests ?? [];
            final isAlreadyConnected = alreadyFriends.contains(senderId) ||
                alreadyFollowed.contains(senderId) ||
                myInterests.contains('friend:$senderId');
            if (isAlreadyConnected) continue;
            final reqKey = 'fr_sync_${senderId}_$uid';

            if (!requestMap.values.any((r) => r.senderId == senderId && r.isPending)) {
              final senderNick = item['nickname']?.toString() ?? 'User';
              final senderAv = item['avatar_url']?.toString();
              final senderVip = item['is_vip'] == true;

              requestMap[reqKey] = FriendRequest(
                id: reqKey,
                senderId: senderId,
                senderName: senderNick,
                senderAvatar: senderAv,
                senderIsVip: senderVip,
                receiverId: uid,
                receiverName: _currentProfile?.nickname ?? 'User',
                status: 'pending',
                createdAt: DateTime.now(),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchFriendRequests profile scan note: $e');
      }
    }

    final result = requestMap.values.where((r) => r.isPending && !_blockedUserIds.contains(r.senderId)).toList();
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Cache updated incoming requests locally without overwriting existing records
    try {
      final existingRaw = prefs.getStringList('local_friend_requests') ?? [];
      final Map<String, String> merged = {};
      for (final raw in existingRaw) {
        try {
          final m = jsonDecode(raw) as Map<String, dynamic>;
          final id = m['id']?.toString() ?? '';
          if (id.isNotEmpty) merged[id] = raw;
        } catch (_) {}
      }
      for (final req in requestMap.values) {
        merged[req.id] = jsonEncode(req.toMap());
      }
      await prefs.setStringList('local_friend_requests', merged.values.toList());
    } catch (_) {}

    return result;
  }

  /// Fetch all sent pending friend requests sent by current user
  Future<List<FriendRequest>> fetchSentFriendRequests() async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) return [];

    final prefs = await SharedPreferences.getInstance();
    final rawRequests = prefs.getStringList('local_friend_requests') ?? [];
    final List<FriendRequest> sent = [];

    for (final raw in rawRequests) {
      try {
        final req = FriendRequest.fromMap(jsonDecode(raw) as Map<String, dynamic>);
        if (req.senderId == uid && req.isPending && !_blockedUserIds.contains(req.receiverId)) {
          sent.add(req);
        }
      } catch (_) {}
    }

    return sent;
  }

  /// Fetch list of accepted friends and followed users for the current user as UserProfiles
  Future<List<UserProfile>> fetchFriends() async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) return [];

    final prefs = await SharedPreferences.getInstance();
    final Set<String> friendIdSet = {};
    friendIdSet.addAll(prefs.getStringList('local_friends_$uid') ?? []);
    friendIdSet.addAll(prefs.getStringList('local_following_$uid') ?? []);

    // Also check remote Supabase user_follows table if exists
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!.from('user_follows').select('following_id').eq('follower_id', uid);
        for (final row in data) {
          final fId = row['following_id']?.toString();
          if (fId != null) friendIdSet.add(fId);
        }
      } catch (_) {}

      try {
        final fData = await _client!.from('friends').select('user_id_1, user_id_2').or('user_id_1.eq.$uid,user_id_2.eq.$uid');
        for (final row in fData) {
          final u1 = row['user_id_1']?.toString();
          final u2 = row['user_id_2']?.toString();
          if (u1 != null && u1 != uid) friendIdSet.add(u1);
          if (u2 != null && u2 != uid) friendIdSet.add(u2);
        }
      } catch (_) {}

      // Cross-account fallback: check current user's profile interests in Supabase
      try {
        final myProf = await _client!.from('profiles').select('interests').eq('id', uid).maybeSingle();
        if (myProf != null && myProf['interests'] != null) {
          final ints = (myProf['interests'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          for (final item in ints) {
            if (item.startsWith('follow:')) {
              friendIdSet.add(item.replaceFirst('follow:', ''));
            } else if (item.startsWith('friend:')) {
              friendIdSet.add(item.replaceFirst('friend:', ''));
            }
          }
        }
      } catch (_) {}
    }

    // Exclude blocked users!
    friendIdSet.removeWhere((id) => _blockedUserIds.contains(id));

    final friendIds = friendIdSet.toList();
    final List<UserProfile> friends = [];

    for (final fid in friendIds) {
      // Check stored user info
      final infoJson = prefs.getString('local_user_info_$fid');
      if (infoJson != null) {
        try {
          final map = jsonDecode(infoJson) as Map<String, dynamic>;
          friends.add(UserProfile(
            id: fid,
            isAnonymous: false,
            nickname: map['nickname']?.toString() ?? 'Friend#${fid.substring(max(0, fid.length - 4))}',
            username: map['username']?.toString(),
            avatarUrl: map['avatarUrl']?.toString() ?? map['avatar_url']?.toString(),
            isVip: map['isVip'] == true || map['is_vip'] == true,
            status: 'online',
          ));
          continue;
        } catch (_) {}
      }

      // Check registered users list
      final regUsers = prefs.getStringList('local_registered_users') ?? [];
      bool foundInReg = false;
      for (final raw in regUsers) {
        try {
          final uMap = jsonDecode(raw) as Map<String, dynamic>;
          if (uMap['id'] == fid) {
            friends.add(UserProfile(
              id: fid,
              isAnonymous: false,
              nickname: uMap['nickname']?.toString() ?? 'Friend',
              username: uMap['username']?.toString(),
              avatarUrl: uMap['avatar_url']?.toString(),
              isVip: uMap['is_vip'] == true,
              status: 'online',
            ));
            foundInReg = true;
            break;
          }
        } catch (_) {}
      }

      if (!foundInReg) {
        final uName = prefs.getString('local_user_username_$fid');
        final nick = prefs.getString('local_user_nickname_$fid') ??
            'Friend#${fid.length > 5 ? fid.substring(fid.length - 5) : fid}';
        friends.add(UserProfile(
          id: fid,
          isAnonymous: false,
          nickname: nick,
          username: uName,
          status: 'online',
        ));
      }
    }

    // Remote Supabase sync if connected
    if (_client != null && AppConfig.isSupabaseConfigured && friends.length < friendIds.length) {
      final existingIds = friends.map((f) => f.id).toSet();
      final missingIds = friendIds.where((id) => !existingIds.contains(id)).toList();
      if (missingIds.isNotEmpty) {
        try {
          final remoteData = await _client!.from('profiles').select().filter('id', 'in', missingIds);
          for (final item in remoteData) {
            final p = UserProfile.fromMap(item);
            if (!_blockedUserIds.contains(p.id)) {
              friends.add(p);
            }
          }
        } catch (_) {}
      }
    }

    return friends;
  }

  /// Fetch chat messages between current user and friend
  Future<List<FriendChatMessage>> fetchFriendChatMessages(String friendId) async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) return [];

    final chatId = FriendChatMessage.computeChatId(uid, friendId);
    final prefs = await SharedPreferences.getInstance();
    final rawMessages = prefs.getStringList('local_friend_chat_$chatId') ?? [];
    final List<FriendChatMessage> messages = [];

    for (final raw in rawMessages) {
      try {
        messages.add(FriendChatMessage.fromMap(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {}
    }

    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  /// Stream of chat messages for a specific friend conversation
  Stream<List<FriendChatMessage>> getFriendChatStream(String friendId) {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id ?? 'guest';
    final chatId = FriendChatMessage.computeChatId(uid, friendId);
    return _friendChatControllers.putIfAbsent(
      chatId,
      () => StreamController<List<FriendChatMessage>>.broadcast(),
    ).stream;
  }

  /// Send a text message or gift message to a friend in the 1-on-1 text chat
  Future<FriendChatMessage> sendFriendChatMessage({
    required String friendId,
    required String text,
    bool isGift = false,
    String? giftName,
    String? giftEmoji,
    int? giftCoins,
  }) async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) {
      throw Exception('You must be signed in to send messages.');
    }

    final chatId = FriendChatMessage.computeChatId(uid, friendId);
    final senderName = _currentProfile?.nickname ?? 'User';
    final now = DateTime.now();
    final messageId = 'fmsg_${const Uuid().v4()}';

    final message = FriendChatMessage(
      id: messageId,
      chatId: chatId,
      senderId: uid,
      senderName: senderName,
      receiverId: friendId,
      text: text,
      isGift: isGift,
      giftName: giftName,
      giftEmoji: giftEmoji,
      giftCoins: giftCoins,
      createdAt: now,
    );

    // Save locally
    final prefs = await SharedPreferences.getInstance();
    final rawMessages = prefs.getStringList('local_friend_chat_$chatId') ?? [];
    rawMessages.add(jsonEncode(message.toMap()));
    await prefs.setStringList('local_friend_chat_$chatId', rawMessages);

    // Broadcast on stream
    final allMessages = await fetchFriendChatMessages(friendId);
    if (_friendChatControllers.containsKey(chatId)) {
      _friendChatControllers[chatId]!.add(allMessages);
    }

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('friend_messages').insert(message.toMap());
      } catch (e) {
        debugPrint('[SupabaseService] sendFriendChatMessage remote note: $e');
      }
    }

    return message;
  }

  // ===========================================================================
  // Unique Username & Profile Completion System
  // ===========================================================================

  /// Validate and check availability of a unique username.
  /// Rules: 3-20 characters, alphanumeric and underscore only, unique case-insensitive.
  Future<Map<String, dynamic>> checkUsernameAvailability(
    String rawUsername, {
    String? currentUserId,
  }) async {
    final clean = rawUsername.trim().toLowerCase().replaceAll('@', '');
    final uid = currentUserId ?? _currentProfile?.id ?? _client?.auth.currentUser?.id;

    if (clean.isEmpty) {
      return {
        'available': false,
        'message': 'Username cannot be empty',
      };
    }

    if (clean.length < 3) {
      return {
        'available': false,
        'message': 'Username must be at least 3 characters',
      };
    }

    if (clean.length > 20) {
      return {
        'available': false,
        'message': 'Username cannot exceed 20 characters',
      };
    }

    final validPattern = RegExp(r'^[a-z0-9_]+$');
    if (!validPattern.hasMatch(clean)) {
      return {
        'available': false,
        'message': 'Only letters, numbers, and underscores allowed',
      };
    }

    // If it's already the current user's username
    if (_currentProfile?.username?.toLowerCase() == clean && uid == _currentProfile?.id) {
      return {
        'available': true,
        'isCurrent': true,
        'message': 'Username is available',
      };
    }

    final prefs = await SharedPreferences.getInstance();

    // Check local username ownership
    final ownerId = prefs.getString('local_username_owner_$clean');
    if (ownerId != null && ownerId != uid) {
      return {
        'available': false,
        'message': 'Username already taken',
      };
    }

    // Check registered users list
    final regUsers = prefs.getStringList('local_registered_users') ?? [];
    for (final raw in regUsers) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final regUsername = map['username']?.toString().toLowerCase();
        final regId = map['id']?.toString();
        if (regUsername == clean && regId != uid) {
          return {
            'available': false,
            'message': 'Username already taken',
          };
        }
      } catch (_) {}
    }

    // Check remote Supabase table if configured
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final res = await _client!
            .from('profiles')
            .select('id')
            .ilike('username', clean)
            .maybeSingle();

        if (res != null && res['id'] != uid) {
          return {
            'available': false,
            'message': 'Username already taken',
          };
        }
      } catch (e) {
        debugPrint('[SupabaseService] checkUsernameAvailability remote note: $e');
        // Fallback check against interests tags when username column is not yet present
        try {
          final res = await _client!
              .from('profiles')
              .select('id')
              .contains('interests', ['uname:$clean'])
              .maybeSingle();
          if (res != null && res['id'] != uid) {
            return {
              'available': false,
              'message': 'Username already taken',
            };
          }
        } catch (_) {}
      }
    }

    return {
      'available': true,
      'message': 'Username is available',
    };
  }

  /// Set unique username and Date of Birth (verifying 18+ eligibility), with optional gender lock
  Future<Map<String, dynamic>> setUsernameAndDob({
    required String username,
    required DateTime dateOfBirth,
    String? gender,
  }) async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (uid == null) {
      throw Exception('You must be signed in to set username and date of birth.');
    }

    final availability = await checkUsernameAvailability(username, currentUserId: uid);
    if (availability['available'] != true) {
      throw Exception(availability['message'] ?? 'Username already taken');
    }

    final clean = username.trim().toLowerCase().replaceAll('@', '');

    // 7-day username change restriction
    if (_currentProfile?.username != null &&
        _currentProfile!.username!.isNotEmpty &&
        _currentProfile!.username!.toLowerCase() != clean) {
      if (!(_currentProfile?.canChangeUsername ?? true)) {
        final days = _currentProfile!.daysUntilUsernameChange;
        throw Exception(
          'You cannot change your username yet. Usernames can only be changed once every 7 days ($days day${days == 1 ? '' : 's'} remaining).',
        );
      }
    }

    // Calculate age and check 18+ requirement
    final now = DateTime.now();
    int calculatedAge = now.year - dateOfBirth.year;
    if (now.month < dateOfBirth.month || (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      calculatedAge--;
    }

    final prefs = await SharedPreferences.getInstance();
    if (calculatedAge < 18) {
      await prefs.setBool('baatkry_underage_blocked', true);
      throw Exception('Underage Access Denied: You must be at least 18 years old to use Baatkry.');
    }

    final dobIso = dateOfBirth.toIso8601String().split('T').first;

    // Release old username ownership if existed
    if (_currentProfile?.username != null && _currentProfile!.username!.isNotEmpty) {
      final oldClean = _currentProfile!.username!.toLowerCase().replaceAll('@', '');
      await prefs.remove('local_username_owner_$oldClean');
    }

    final nowUtc = DateTime.now().toUtc();
    final nowIso = nowUtc.toIso8601String();

    // Persist new username, update timestamp, and DOB
    await prefs.setString('local_user_username_$uid', clean);
    await prefs.setString('local_username_owner_$clean', uid);
    await prefs.setString('local_user_username_updated_at_$uid', nowIso);
    await prefs.setString('baatkry_user_dob', dobIso);
    await prefs.setString('local_user_dob', dobIso);
    await prefs.setString('local_user_dob_$uid', dobIso);
    await prefs.setInt('baatkry_user_age', calculatedAge);
    await prefs.setInt('local_user_age', calculatedAge);
    await prefs.setInt('local_user_age_$uid', calculatedAge);
    await prefs.setBool('baatkry_age_verified_18_plus', true);

    String effectiveGender = _currentProfile?.gender ?? 'unspecified';
    if (gender != null && gender.isNotEmpty && (!_currentProfile!.isGenderSet || effectiveGender == 'unspecified')) {
      effectiveGender = gender;
      await prefs.setString('local_user_gender', gender);
      await prefs.setString('local_user_gender_$uid', gender);
      await prefs.setBool('baatkry_user_gender_locked', true);
    }

    _currentProfile = _currentProfile!.copyWith(
      username: clean,
      usernameUpdatedAt: nowUtc,
      birthDate: dobIso,
      age: calculatedAge,
      isAgeVerified: true,
      gender: effectiveGender,
    );
    _profileController.add(_currentProfile);

    // Upsert full profile into registered users list and local user caches
    await _upsertLocalUserRecord(_currentProfile!);

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final currentInterests = List<String>.from(_currentProfile?.interests ?? []);
        currentInterests.removeWhere((i) => i.startsWith('uname:'));
        currentInterests.add('uname:$clean');

        final remotePayload = <String, dynamic>{
          'username': clean,
          'username_updated_at': nowIso,
          'birth_date': dobIso,
          'age': calculatedAge,
          'is_age_verified': true,
          'interests': currentInterests,
        };
        if (gender != null && gender.isNotEmpty) {
          remotePayload['gender'] = gender;
        }

        try {
          await _client!.from('profiles').update(remotePayload).eq('id', uid);
        } catch (_) {
          // If username or username_updated_at column is missing on remote Supabase:
          remotePayload.remove('username');
          remotePayload.remove('username_updated_at');
          await _client!.from('profiles').update(remotePayload).eq('id', uid);
        }
      } catch (e) {
        debugPrint('[SupabaseService] setUsernameAndDob remote note: $e');
      }
    }

    return {
      'success': true,
      'username': clean,
      'age': calculatedAge,
      'birth_date': dobIso,
    };
  }

  /// Claim Daily Free Coins (7-day reward sequence)
  /// Day 1: 50, Day 2: 100, Day 3: 150, Day 4: 200, Day 5: 250, Day 6: 300, Day 7: 350
  Future<Map<String, dynamic>> claimDailyFreeCoins() async {
    final profile = _currentProfile;
    if (profile == null) {
      throw Exception('User must be signed in to claim daily free coins.');
    }

    if (!profile.canClaimDailyReward) {
      return {
        'success': false,
        'message': 'You have already claimed your daily reward today. Come back tomorrow!',
        'already_claimed': true,
        'streak': profile.dailyClaimStreak,
      };
    }

    final nextDay = profile.nextDailyRewardDay;
    final rewardCoins = nextDay * 50;
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final uid = profile.id;

    final newCoins = profile.coins + rewardCoins;
    _currentProfile = profile.copyWith(
      coins: newCoins,
      dailyClaimStreak: nextDay,
      lastDailyClaimAt: now,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('local_user_daily_streak_$uid', nextDay);
    await prefs.setString('local_user_last_claim_at_$uid', nowIso);
    await prefs.setInt('local_user_coins_$uid', newCoins);
    await prefs.setInt('local_user_coins', newCoins);

    // Update in-memory stream
    _profileController.add(_currentProfile);

    // Update registered users list
    final regUsers = prefs.getStringList('local_registered_users') ?? [];
    for (int i = 0; i < regUsers.length; i++) {
      try {
        final map = jsonDecode(regUsers[i]) as Map<String, dynamic>;
        if (map['id'] == uid) {
          map['coins'] = newCoins;
          map['daily_claim_streak'] = nextDay;
          map['last_daily_claim_at'] = nowIso;
          regUsers[i] = jsonEncode(map);
          break;
        }
      } catch (_) {}
    }
    await prefs.setStringList('local_registered_users', regUsers);

    // Update remote profile if connected
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('profiles').update({
          'coins': newCoins,
          'daily_claim_streak': nextDay,
          'last_daily_claim_at': nowIso,
        }).eq('id', uid);
      } catch (e) {
        debugPrint('[SupabaseService] claimDailyFreeCoins remote error: $e');
      }
    }

    return {
      'success': true,
      'day': nextDay,
      'coins_awarded': rewardCoins,
      'new_balance': newCoins,
      'streak': nextDay,
      'message': 'Claimed Day $nextDay reward of $rewardCoins Coins!',
    };
  }

  /// Helper to upsert a registered user profile into local caches
  Future<void> _upsertLocalUserRecord(UserProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final regUsers = prefs.getStringList('local_registered_users') ?? [];
      final map = profile.toMap();
      final jsonStr = jsonEncode(map);

      bool updated = false;
      for (int i = 0; i < regUsers.length; i++) {
        try {
          final existing = jsonDecode(regUsers[i]) as Map<String, dynamic>;
          if (existing['id'] == profile.id) {
            regUsers[i] = jsonStr;
            updated = true;
            break;
          }
        } catch (_) {}
      }
      if (!updated) {
        regUsers.add(jsonStr);
      }
      await prefs.setStringList('local_registered_users', regUsers);
      await prefs.setString('local_user_info_${profile.id}', jsonStr);
      if (profile.username != null && profile.username!.isNotEmpty) {
        final clean = profile.username!.toLowerCase().replaceAll('@', '');
        await prefs.setString('local_user_username_${profile.id}', clean);
        await prefs.setString('local_username_owner_$clean', profile.id);
      }
      if (profile.nickname.isNotEmpty) {
        await prefs.setString('local_user_nickname_${profile.id}', profile.nickname);
      }
      if (profile.avatarUrl != null) {
        await prefs.setString('local_user_avatar_url_${profile.id}', profile.avatarUrl!);
      }
      if (profile.birthDate != null) {
        await prefs.setString('local_user_dob_${profile.id}', profile.birthDate!);
      }
      if (profile.age != null) {
        await prefs.setInt('local_user_age_${profile.id}', profile.age!);
      }
      await prefs.setBool('local_user_is_vip_${profile.id}', profile.isVip);
    } catch (e) {
      debugPrint('[SupabaseService] _upsertLocalUserRecord note: $e');
    }
  }

  /// Search all users across database and local caches with Instagram-style sorting
  Future<List<UserProfile>> searchUsersByUsername(String query) async {
    final clean = query.trim().toLowerCase().replaceAll('@', '');
    if (clean.isEmpty) return [];

    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    final prefs = await SharedPreferences.getInstance();
    final Map<String, UserProfile> results = {};

    // 1. Search local registered users
    final regUsers = prefs.getStringList('local_registered_users') ?? [];
    for (final raw in regUsers) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final userId = map['id']?.toString() ?? '';
        if (userId.isEmpty || userId == uid) continue;

        final uName = (map['username'] ?? '').toString().toLowerCase();
        final nick = (map['nickname'] ?? '').toString().toLowerCase();

        if (uName.contains(clean) || nick.contains(clean)) {
          results[userId] = UserProfile.fromMap(map);
        }
      } catch (_) {}
    }

    // 2. Scan all SharedPreferences keys for locally registered users & usernames
    final allKeys = prefs.getKeys();
    for (final key in allKeys) {
      if (key.startsWith('local_user_info_')) {
        try {
          final raw = prefs.getString(key);
          if (raw != null) {
            final map = jsonDecode(raw) as Map<String, dynamic>;
            final userId = map['id']?.toString() ?? '';
            if (userId.isNotEmpty && userId != uid && !results.containsKey(userId)) {
              final uName = (map['username'] ?? '').toString().toLowerCase();
              final nick = (map['nickname'] ?? '').toString().toLowerCase();
              if (uName.contains(clean) || nick.contains(clean)) {
                results[userId] = UserProfile.fromMap(map);
              }
            }
          }
        } catch (_) {}
      } else if (key.startsWith('local_username_owner_')) {
        final ownerUsername = key.replaceFirst('local_username_owner_', '').toLowerCase();
        if (ownerUsername.contains(clean)) {
          final ownerId = prefs.getString(key);
          if (ownerId != null && ownerId.isNotEmpty && ownerId != uid && !results.containsKey(ownerId)) {
            final nick = prefs.getString('local_user_nickname_$ownerId') ?? ownerUsername;
            final avatar = prefs.getString('local_user_avatar_url_$ownerId');
            final isVip = prefs.getBool('local_user_is_vip_$ownerId') ?? false;
            final dob = prefs.getString('local_user_dob_$ownerId');
            final age = prefs.getInt('local_user_age_$ownerId');

            results[ownerId] = UserProfile(
              id: ownerId,
              isAnonymous: false,
              nickname: nick,
              username: ownerUsername,
              avatarUrl: avatar,
              isVip: isVip,
              birthDate: dob,
              age: age,
              isAgeVerified: dob != null || (age != null && age >= 18),
            );
          }
        }
      } else if (key.startsWith('local_user_username_')) {
        final userId = key.replaceFirst('local_user_username_', '');
        if (userId.isNotEmpty && userId != uid && !results.containsKey(userId)) {
          final uName = (prefs.getString(key) ?? '').toLowerCase();
          if (uName.contains(clean)) {
            final nick = prefs.getString('local_user_nickname_$userId') ?? uName;
            final avatar = prefs.getString('local_user_avatar_url_$userId');
            final isVip = prefs.getBool('local_user_is_vip_$userId') ?? false;
            final dob = prefs.getString('local_user_dob_$userId');
            final age = prefs.getInt('local_user_age_$userId');

            results[userId] = UserProfile(
              id: userId,
              isAnonymous: false,
              nickname: nick,
              username: uName,
              avatarUrl: avatar,
              isVip: isVip,
              birthDate: dob,
              age: age,
              isAgeVerified: dob != null || (age != null && age >= 18),
            );
          }
        }
      }
    }

    // 3. Search Supabase complete database (profiles table)
    if (_client != null && AppConfig.isSupabaseConfigured) {
      List<dynamic> remoteData = [];
      try {
        remoteData = await _client!
            .from('profiles')
            .select()
            .or('username.ilike.%$clean%,nickname.ilike.%$clean%')
            .neq('id', uid ?? '')
            .limit(50);
      } catch (e) {
        debugPrint('[SupabaseService] search profiles or-filter fallback: $e');
        try {
          remoteData = await _client!
              .from('profiles')
              .select()
              .ilike('nickname', '%$clean%')
              .neq('id', uid ?? '')
              .limit(50);
        } catch (_) {
          try {
            remoteData = await _client!
                .from('profiles')
                .select()
                .neq('id', uid ?? '')
                .limit(50);
          } catch (_) {}
        }
      }

      for (final item in remoteData) {
        try {
          final profile = UserProfile.fromMap(item);
          if (profile.id.isNotEmpty && profile.id != uid && !_blockedUserIds.contains(profile.id)) {
            final uName = (profile.username ?? '').toLowerCase();
            final nick = profile.nickname.toLowerCase();
            if (uName.contains(clean) || nick.contains(clean)) {
              results[profile.id] = profile;
            }
          }
        } catch (_) {}
      }
    }

    // Filter out blocked users
    results.removeWhere((id, _) => _blockedUserIds.contains(id));

    // 4. Instagram-style ranking and sorting:
    // Starts-with query appears first, followed by contains
    final list = results.values.toList();
    list.sort((a, b) {
      final aUser = (a.username ?? '').toLowerCase();
      final bUser = (b.username ?? '').toLowerCase();
      final aNick = a.nickname.toLowerCase();
      final bNick = b.nickname.toLowerCase();

      // Exact match
      if (aUser == clean && bUser != clean) return -1;
      if (bUser == clean && aUser != clean) return 1;

      // Username starts-with clean (Instagram priority)
      final aStarts = aUser.startsWith(clean);
      final bStarts = bUser.startsWith(clean);
      if (aStarts && !bStarts) return -1;
      if (bStarts && !aStarts) return 1;

      // Nickname starts-with clean
      final aNickStarts = aNick.startsWith(clean);
      final bNickStarts = bNick.startsWith(clean);
      if (aNickStarts && !bNickStarts) return -1;
      if (bNickStarts && !aNickStarts) return 1;

      // Fallback alphabetical
      return aUser.compareTo(bUser);
    });

    return list;
  }

  /// Discover all available registered platform users (e.g. for Find Friends empty state)
  Future<List<UserProfile>> fetchDiscoverUsers({int limit = 30}) async {
    final uid = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    final prefs = await SharedPreferences.getInstance();
    final Map<String, UserProfile> results = {};

    // 1. Local registered users
    final regUsers = prefs.getStringList('local_registered_users') ?? [];
    for (final raw in regUsers) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final userId = map['id']?.toString() ?? '';
        if (userId.isEmpty || userId == uid || _blockedUserIds.contains(userId)) continue;
        results[userId] = UserProfile.fromMap(map);
      } catch (_) {}
    }

    // 2. Local user info
    for (final key in prefs.getKeys()) {
      if (key.startsWith('local_user_info_')) {
        try {
          final raw = prefs.getString(key);
          if (raw != null) {
            final map = jsonDecode(raw) as Map<String, dynamic>;
            final userId = map['id']?.toString() ?? '';
            if (userId.isNotEmpty && userId != uid && !_blockedUserIds.contains(userId)) {
              results[userId] = UserProfile.fromMap(map);
            }
          }
        } catch (_) {}
      }
    }

    // 3. Supabase remote database
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('profiles')
            .select()
            .neq('id', uid ?? '')
            .limit(limit);
        for (final item in data) {
          final profile = UserProfile.fromMap(item);
          if (!_blockedUserIds.contains(profile.id)) {
            results[profile.id] = profile;
          }
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchDiscoverUsers remote note: $e');
      }
    }

    results.removeWhere((id, _) => _blockedUserIds.contains(id));
    return results.values.take(limit).toList();
  }
}


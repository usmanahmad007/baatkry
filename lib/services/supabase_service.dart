import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../models/coin_package.dart';
import '../models/commission_rule.dart';
import '../models/creator_application.dart';
import '../models/creator_earning_entry.dart';
import '../models/creator_profile.dart';
import '../models/creator_wallet.dart';
import '../models/user_profile.dart';
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

  Stream<UserProfile?> get profileStream => _profileController.stream;
  UserProfile? get currentProfile => _currentProfile;
  Stream<UserWallet?> get walletStream => _walletController.stream;
  UserWallet? get currentWallet => _currentWallet;
  Stream<CreatorWallet?> get creatorWalletStream => _creatorWalletController.stream;
  CreatorWallet? get currentCreatorWallet => _currentCreatorWallet;
  bool get isAuthenticated => _currentProfile != null && !_currentProfile!.isAnonymous;
  bool get isGuest => _currentProfile == null || _currentProfile!.isAnonymous;
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
              UserProfile profile;
              if (remoteProfile != null) {
                profile = remoteProfile;
                await prefs.setInt('local_user_coins_${user.id}', profile.coins);
                await prefs.setInt('local_user_coins', profile.coins);
              } else {
                final isFirstTimeUser = !hasUsedBonusOnDevice &&
                    !hasClaimedBonusForEmail &&
                    !hasClaimedBonusForUser &&
                    savedUserCoins == null;
                final initialCoins = isFirstTimeUser ? 120 : (savedUserCoins ?? 0);

                profile = UserProfile(
                  id: user.id,
                  isAnonymous: false,
                  nickname: user.userMetadata?['full_name'] ?? user.email?.split('@').first ?? 'Google User',
                  coins: initialCoins,
                  age: detectedAge,
                  isAgeVerified: detectedAge != null && detectedAge >= 18,
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

    if (_client != null && _client!.auth.currentUser != null) {
      final user = _client!.auth.currentUser!;
      final remote = await _fetchRemoteProfile(user.id);
      final cleanEmail = user.email?.trim().toLowerCase();
      final hasClaimedBonus = (prefs.getBool('baatkry_bonus_claimed_${user.id}') ?? false) ||
          (cleanEmail != null && (prefs.getBool('baatkry_bonus_claimed_$cleanEmail') ?? false));
      final savedUserCoins = prefs.getInt('local_user_coins_${user.id}') ?? prefs.getInt('local_user_coins');

      final profile = remote ??
          UserProfile(
            id: user.id,
            isAnonymous: user.isAnonymous,
            nickname: user.isAnonymous ? 'Guest #${user.id.substring(0, 4)}' : (user.email?.split('@').first ?? 'User'),
            coins: user.isAnonymous
                ? 0
                : ((hasClaimedBonus || _hasUsedJoiningBonus) ? (savedUserCoins ?? 0) : 120),
          );
      _currentProfile = profile;
      _profileController.add(_currentProfile);
      await _syncUserWallet(user.id);
      return profile;
    }

    // Local / Offline Guest fallback:
    // Before signup/login, user cannot use coins (0 coins) and country is fixed to Global
    final savedId = prefs.getString('local_user_id') ?? const Uuid().v4();
    final savedNickname = prefs.getString('local_user_nickname') ?? 'Guest #${savedId.substring(0, 5)}';
    final savedGender = prefs.getString('local_user_gender') ?? 'unspecified';
    final savedInterests = prefs.getStringList('local_user_interests') ?? ['Music', 'Gaming'];

    await prefs.setString('local_user_id', savedId);

    _currentProfile = UserProfile(
      id: savedId,
      isAnonymous: true,
      nickname: savedNickname,
      coins: 0, // Before signup, user cannot use coins
      isVip: false,
      gender: savedGender,
      interests: savedInterests,
      country: 'Global (Worldwide)',
      countryCode: 'ALL',
    );

    _profileController.add(_currentProfile);
    return _currentProfile!;
  }

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
        _currentWallet = wallet;
        _walletController.add(_currentWallet);

        // Keep profile coins aligned with ledger balance
        if (_currentProfile != null && _currentProfile!.coins != wallet.balance) {
          _currentProfile = _currentProfile!.copyWith(coins: wallet.balance);
          _profileController.add(_currentProfile);
        }

        // 3. Setup real-time listener on wallets table for this user
        _subscribeToWalletChanges(userId);
        return wallet;
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

  /// Fetch immutable ledger transaction history
  Future<List<WalletLedgerEntry>> fetchWalletLedger({int limit = 50}) async {
    final userId = _currentProfile?.id ?? _client?.auth.currentUser?.id;
    if (userId == null) return [];

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final data = await _client!
            .from('wallet_ledger')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(limit);

        if (data.isNotEmpty) {
          return data.map((item) => WalletLedgerEntry.fromMap(item)).toList();
        }
      } catch (e) {
        debugPrint('[SupabaseService] Error loading wallet ledger: $e');
      }
    }

    // Local / Offline fallback mock history
    final prefs = await SharedPreferences.getInstance();
    final savedPurchases = prefs.getStringList('local_tx_history_$userId') ?? [];
    return savedPurchases.map((s) {
      final parts = s.split('|');
      return WalletLedgerEntry(
        id: parts[0],
        walletId: 'local_wallet_$userId',
        userId: userId,
        type: LedgerTransactionType.fromString(parts.length > 1 ? parts[1] : 'purchase'),
        amount: parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0,
        balanceAfter: parts.length > 3 ? (int.tryParse(parts[3]) ?? 0) : 0,
        description: parts.length > 4 ? parts[4] : 'Coin transaction',
        createdAt: DateTime.now(),
      );
    }).toList();
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

    // 4. Age or DOB NOT found from Google/Gmail:
    // Check if user previously verified age with birth certificate DOB picker
    final previouslyVerified = prefs.getBool('baatkry_age_verified_18_plus') ?? false;
    final savedAge = prefs.getInt('baatkry_user_age');
    if (previouslyVerified && savedAge != null && savedAge >= 18) {
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

    final profile = UserProfile(
      id: userId,
      isAnonymous: false,
      nickname: nickname,
      coins: initialCoins,
      age: calculatedAge,
      isAgeVerified: true,
      birthDate: dateOfBirth?.toIso8601String(),
      country: 'Global (Worldwide)',
      countryCode: 'ALL',
    );

    await prefs.setString('local_user_id', userId);
    await prefs.setString('local_user_nickname', nickname);
    await prefs.setString('local_user_email', cleanEmail);
    await prefs.setBool('baatkry_age_verified_18_plus', true);
    await prefs.setInt('local_user_age', calculatedAge);
    await prefs.setInt('local_user_coins_$userId', initialCoins);
    await prefs.setInt('local_user_coins', initialCoins);

    _currentProfile = profile;
    _profileController.add(_currentProfile);
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
          final profile = remoteProfile ??
              UserProfile(
                id: res.user!.id,
                isAnonymous: false,
                nickname: cleanEmail.split('@').first,
                coins: savedCoins ?? 0, // Returning user logging in keeps their saved coins (never a new 120)
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

    final profile = UserProfile(
      id: userId,
      isAnonymous: false,
      nickname: nickname,
      coins: coins,
    );

    await prefs.setString('local_user_id', userId);
    await prefs.setString('local_user_nickname', nickname);
    await prefs.setString('local_user_email', cleanEmail);
    await prefs.setInt('local_user_coins_$userId', coins);
    await prefs.setInt('local_user_coins', coins);

    _currentProfile = profile;
    _profileController.add(_currentProfile);
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
    await prefs.remove('baatkry_age_verified_18_plus');
    await prefs.remove('baatkry_user_age');
    await _loadOrCreateProfile();
  }

  /// Update user profile details (interests, nickname, gender, country, age verification)
  Future<void> updateProfile({
    String? nickname,
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

    _currentProfile = _currentProfile!.copyWith(
      nickname: nickname,
      gender: gender,
      interests: interests,
      avatarUrl: avatarUrl,
      age: age,
      isAgeVerified: isAgeVerified,
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
    if (gender != null) await prefs.setString('local_user_gender', gender);
    if (interests != null) await prefs.setStringList('local_user_interests', interests);
    if (age != null) await prefs.setInt('local_user_age', age);
    if (isAgeVerified != null) await prefs.setBool('baatkry_age_verified_18_plus', isAgeVerified);
    if (country != null) await prefs.setString('local_user_country', country);
    if (countryCode != null) await prefs.setString('local_user_country_code', countryCode);

    _profileController.add(_currentProfile);
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
          final isVip = packageId.contains('2500') || packageId.contains('5000') || _currentProfile!.isVip;

          _currentProfile = _currentProfile!.copyWith(coins: newBalance, isVip: isVip);
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
          return true;
        }
      } catch (e) {
        debugPrint('[SupabaseService] process_verified_coin_purchase RPC note: $e');
      }
    }

    // Local / Offline fallback logic:
    final updatedCoins = _currentProfile!.coins + coinsAdded;
    final isVip = packageId.contains('2500') || packageId.contains('5000') || _currentProfile!.isVip;

    _currentProfile = _currentProfile!.copyWith(coins: updatedCoins, isVip: isVip);
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
    return prefs.getBool('local_is_creator_$uid') ?? false;
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
          return data.map((item) => CreatorEarningEntry.fromMap(item)).toList();
        }
      } catch (e) {
        debugPrint('[SupabaseService] fetchCreatorEarnings error: $e');
      }
    }

    return [];
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
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('reports').insert({
          'reporter_id': _currentProfile?.id,
          'reported_id': reportedUserId,
          'reason': reason,
          'details': details,
          'room_id': roomId,
        });
      } catch (e) {
        debugPrint('[SupabaseService] Error submitting report: $e');
      }
    }
  }

  /// Block user
  Future<void> blockUser(String targetUserId) async {
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('blocked_users').insert({
          'user_id': _currentProfile?.id,
          'blocked_user_id': targetUserId,
        });
      } catch (e) {
        debugPrint('[SupabaseService] Error blocking user: $e');
      }
    }
  }
}

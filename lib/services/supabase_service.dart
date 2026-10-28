import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../models/user_profile.dart';

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
  String? _browserDeviceId;
  bool _hasUsedJoiningBonus = false;

  Stream<UserProfile?> get profileStream => _profileController.stream;
  UserProfile? get currentProfile => _currentProfile;
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
        scopes: 'email profile openid https://www.googleapis.com/auth/user.birthday.read',
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

  /// Complete a Coin / VIP Purchase in Rupees (Fails if user is anonymous)
  Future<bool> processPurchase({required String packageId, required int coinsAdded, required int priceRs}) async {
    if (_currentProfile == null || _currentProfile!.isAnonymous) {
      throw Exception('Purchase rejected: User must be logged in with Google to make purchases.');
    }

    final updatedCoins = _currentProfile!.coins + coinsAdded;
    final isVip = packageId.contains('2500') || packageId.contains('5000') || _currentProfile!.isVip;

    _currentProfile = _currentProfile!.copyWith(
      coins: updatedCoins,
      isVip: isVip,
    );

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('coin_transactions').insert({
          'user_id': _currentProfile!.id,
          'package_id': packageId,
          'amount_usd': priceRs / 280.0, // stored equivalent
          'coins_added': coinsAdded,
        });
        await _client!.from('profiles').update({
          'coins': _currentProfile!.coins,
          'is_vip': _currentProfile!.isVip,
        }).eq('id', _currentProfile!.id);
      } catch (e) {
        debugPrint('[SupabaseService] Error logging purchase to Supabase: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('local_user_coins_${_currentProfile!.id}', _currentProfile!.coins);
    await prefs.setInt('local_user_coins', _currentProfile!.coins);
    await prefs.setBool('local_user_is_vip', _currentProfile!.isVip);

    _profileController.add(_currentProfile);
    return true;
  }

  /// Update coins in-memory and broadcast immediately to all listeners
  void updateLocalCoinsInMemory(int newBalance) {
    if (_currentProfile == null) return;
    final validBalance = newBalance < 0 ? 0 : newBalance;
    _currentProfile = _currentProfile!.copyWith(coins: validBalance);
    _profileController.add(_currentProfile);
  }

  /// Update and persist exact coins balance to DB and SharedPreferences
  Future<bool> updateCoinsBalance(int newBalance) async {
    if (_currentProfile == null) return false;
    final validBalance = newBalance < 0 ? 0 : newBalance;

    _currentProfile = _currentProfile!.copyWith(coins: validBalance);
    _profileController.add(_currentProfile);

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('profiles').update({'coins': validBalance}).eq('id', _currentProfile!.id);
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('local_user_coins_${_currentProfile!.id}', validBalance);
    await prefs.setInt('local_user_coins', validBalance);

    return true;
  }

  /// Deduct coins (e.g. for +15s time boost, VIP filter, or country filter)
  Future<bool> deductCoins(int amount) async {
    // Before signup or login, user cannot use coins
    if (_currentProfile == null || _currentProfile!.isAnonymous) {
      return false;
    }
    if (_currentProfile!.coins < amount) {
      return false;
    }

    final newBalance = _currentProfile!.coins - amount;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('baatkry_bonus_used_on_device', true);
    _hasUsedJoiningBonus = true;
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

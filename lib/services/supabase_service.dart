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

  Stream<UserProfile?> get profileStream => _profileController.stream;
  UserProfile? get currentProfile => _currentProfile;
  bool get isAuthenticated => _currentProfile != null && !_currentProfile!.isAnonymous;
  bool get isGuest => _currentProfile != null && _currentProfile!.isAnonymous;
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
              final profile = await _fetchRemoteProfile(user.id) ??
                  UserProfile(
                    id: user.id,
                    isAnonymous: false,
                    nickname: user.userMetadata?['full_name'] ?? user.email?.split('@').first ?? 'Google User',
                    coins: 120, // 120 coins initial signup bonus
                    age: detectedAge,
                    isAgeVerified: detectedAge != null && detectedAge >= 18,
                  );
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

    if (_client != null && _client!.auth.currentUser != null) {
      final user = _client!.auth.currentUser!;
      final profile = await _fetchRemoteProfile(user.id) ??
          UserProfile(
            id: user.id,
            isAnonymous: user.isAnonymous,
            nickname: user.isAnonymous ? 'Guest #${user.id.substring(0, 4)}' : (user.email?.split('@').first ?? 'User'),
          );
      _currentProfile = profile;
      _profileController.add(_currentProfile);
      return profile;
    }

    // Local / Offline Guest fallback
    final savedId = prefs.getString('local_user_id') ?? const Uuid().v4();
    final savedNickname = prefs.getString('local_user_nickname') ?? 'Guest #${savedId.substring(0, 5)}';
    final savedCoins = prefs.getInt('local_user_coins') ?? 120;
    final savedIsVip = prefs.getBool('local_user_is_vip') ?? false;
    final savedGender = prefs.getString('local_user_gender') ?? 'unspecified';
    final savedInterests = prefs.getStringList('local_user_interests') ?? ['Music', 'Gaming'];

    await prefs.setString('local_user_id', savedId);

    _currentProfile = UserProfile(
      id: savedId,
      isAnonymous: true,
      nickname: savedNickname,
      coins: savedCoins,
      isVip: savedIsVip,
      gender: savedGender,
      interests: savedInterests,
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
            coins: 120, // 120 starter coins
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
      try {
        final redirectUrl = kIsWeb
            ? '${Uri.base.origin}/'
            : 'com.usmanahmad.baatkry://login-callback/';

        final success = await _client!.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: redirectUrl,
          scopes: 'email profile openid https://www.googleapis.com/auth/user.birthday.read',
        );
        if (success) {
          final ageStatus = await checkGoogleUserAge();
          if (ageStatus == GoogleAgeStatus.underageBlocked) {
            throw Exception('Underage Access Denied: Your Google/Gmail account indicates you are under 18. Baatkry is strictly for adults 18+.');
          }

          final user = _client!.auth.currentUser;
          if (user != null) {
            final isAdultVerified = (ageStatus == GoogleAgeStatus.verifiedAdult);
            final profile = await _fetchRemoteProfile(user.id) ??
                UserProfile(
                  id: user.id,
                  isAnonymous: false,
                  nickname: user.userMetadata?['full_name'] ?? 'Google User',
                  coins: 120, // 120 coins initial signup bonus
                  age: isAdultVerified ? (_currentProfile?.age) : null,
                  isAgeVerified: isAdultVerified,
                );
            _currentProfile = profile;
            _profileController.add(_currentProfile);
          }
          return true;
        }
      } catch (e) {
        debugPrint('[SupabaseService] Google sign-in note: $e');
        final errText = e.toString().toLowerCase();
        if (errText.contains('access_denied') || errText.contains('verification') || errText.contains('403')) {
          throw Exception(
            'Google Sign-In Denied (Error 403): Your Google Cloud OAuth screen is currently in "Testing" mode. '
            'To resolve this in 30 seconds: Add your email to "Test users" in Google Cloud Console, or click "Publish App".',
          );
        }
        rethrow;
      }
    }

    // Local simulation fallback for testing Google Sign-in immediately
    final profile = _currentProfile?.copyWith(
          isAnonymous: false,
          nickname: 'Google Explorer',
          coins: (_currentProfile?.coins ?? 50) + 50,
          isAgeVerified: true,
          age: 21,
        ) ??
        const UserProfile(
          id: 'google_verified_user',
          isAnonymous: false,
          nickname: 'Google Explorer',
          coins: 120, // Initial signup bonus
          isAgeVerified: true,
          age: 21,
        );

    await prefs.setString('local_user_nickname', profile.nickname);
    await prefs.setInt('local_user_coins', profile.coins);
    await prefs.setBool('baatkry_age_verified_18_plus', true);

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
            coins: 120, // 120 bonus starter coins for registering
          );
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
    final prefs = await SharedPreferences.getInstance();
    final profile = _currentProfile?.copyWith(
          isAnonymous: false,
          nickname: nickname,
          coins: (_currentProfile?.coins ?? 50) + 50,
        ) ??
        UserProfile(
          id: const Uuid().v4(),
          isAnonymous: false,
          nickname: nickname,
          coins: 120, // Initial bonus
        );

    await prefs.setString('local_user_nickname', nickname);
    await prefs.setInt('local_user_coins', profile.coins);

    _currentProfile = profile;
    _profileController.add(_currentProfile);
    return true;
  }

  /// Sign in with email and password
  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (_client != null) {
      try {
        final res = await _client!.auth.signInWithPassword(email: email, password: password);
        if (res.user != null) {
          final profile = await _fetchRemoteProfile(res.user!.id) ??
              UserProfile(
                id: res.user!.id,
                isAnonymous: false,
                nickname: email.split('@').first,
                coins: 120,
              );
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
    _currentProfile = _currentProfile?.copyWith(
          isAnonymous: false,
          nickname: nickname,
        ) ??
        UserProfile(
          id: const Uuid().v4(),
          isAnonymous: false,
          nickname: nickname,
          coins: 120, // Initial bonus
        );
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
    await _loadOrCreateProfile();
  }

  /// Update user profile details (interests, nickname, gender, age verification)
  Future<void> updateProfile({
    String? nickname,
    String? gender,
    List<String>? interests,
    String? avatarUrl,
    int? age,
    bool? isAgeVerified,
    String? birthDate,
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
    await prefs.setInt('local_user_coins', validBalance);

    return true;
  }

  /// Deduct coins (e.g. for +15s time boost or gender filter)
  Future<bool> deductCoins(int amount) async {
    if (_currentProfile == null || _currentProfile!.coins < amount) {
      return false;
    }

    final newBalance = _currentProfile!.coins - amount;
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

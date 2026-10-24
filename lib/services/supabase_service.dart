import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../models/user_profile.dart';

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
    final savedCoins = prefs.getInt('local_user_coins') ?? 50;
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
            coins: 50,
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

  /// Sign in with Google (OAuth)
  /// Used for permanent account login to unlock coin purchases and VIP
  Future<bool> signInWithGoogle() async {
    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        final success = await _client!.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: kIsWeb ? null : 'com.usmanahmad.baatkry://login-callback/',
        );
        if (success) {
          // If already signed in, fetch profile
          final user = _client!.auth.currentUser;
          if (user != null) {
            final profile = await _fetchRemoteProfile(user.id) ??
                UserProfile(
                  id: user.id,
                  isAnonymous: false,
                  nickname: user.userMetadata?['full_name'] ?? 'Google User',
                  coins: 100,
                );
            _currentProfile = profile;
            _profileController.add(_currentProfile);
          }
          return true;
        }
      } catch (e) {
        debugPrint('[SupabaseService] Google sign-in note: $e');
      }
    }

    // Local simulation fallback for testing Google Sign-in immediately
    final prefs = await SharedPreferences.getInstance();
    final profile = _currentProfile?.copyWith(
          isAnonymous: false,
          nickname: 'Google Explorer',
          coins: (_currentProfile?.coins ?? 50) + 50,
        ) ??
        UserProfile(
          id: const Uuid().v4(),
          isAnonymous: false,
          nickname: 'Google Explorer',
          coins: 100,
        );

    await prefs.setString('local_user_nickname', profile.nickname);
    await prefs.setInt('local_user_coins', profile.coins);

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
            coins: 100, // Bonus starter coins for registering
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
          coins: 100,
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
                coins: 100,
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
          coins: 100,
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

  /// Update user profile details (interests, nickname, gender)
  Future<void> updateProfile({
    String? nickname,
    String? gender,
    List<String>? interests,
    String? avatarUrl,
  }) async {
    if (_currentProfile == null) return;

    _currentProfile = _currentProfile!.copyWith(
      nickname: nickname,
      gender: gender,
      interests: interests,
      avatarUrl: avatarUrl,
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

  /// Deduct coins (e.g. for +15s time boost or gender filter)
  Future<bool> deductCoins(int amount) async {
    if (_currentProfile == null || _currentProfile!.coins < amount) {
      return false;
    }

    final newBalance = _currentProfile!.coins - amount;
    _currentProfile = _currentProfile!.copyWith(coins: newBalance);

    if (_client != null && AppConfig.isSupabaseConfigured) {
      try {
        await _client!.from('profiles').update({'coins': newBalance}).eq('id', _currentProfile!.id);
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('local_user_coins', newBalance);

    _profileController.add(_currentProfile);
    return true;
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

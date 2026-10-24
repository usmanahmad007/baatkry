import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GuestSessionService {
  GuestSessionService._();
  static final GuestSessionService instance = GuestSessionService._();

  static const String _keyGuestSecondsUsed = 'baatkry_guest_seconds_used_v1';
  static const int maxGuestTotalSeconds = 180; // 3 Minutes Total for Guest Mode
  static const int maxGuestPersonSeconds = 30; // 30 Seconds max with one person

  int _cachedSecondsUsed = 0;
  bool _isLoaded = false;

  int get cachedSecondsUsed => _cachedSecondsUsed;
  int get cachedSecondsRemaining => (maxGuestTotalSeconds - _cachedSecondsUsed).clamp(0, maxGuestTotalSeconds);
  bool get isTrialExhausted => _cachedSecondsUsed >= maxGuestTotalSeconds;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedSecondsUsed = prefs.getInt(_keyGuestSecondsUsed) ?? 0;
      _isLoaded = true;
    } catch (e) {
      debugPrint('[GuestSessionService] Failed to load guest seconds: $e');
    }
  }

  Future<int> getGuestSecondsUsed() async {
    if (!_isLoaded) await init();
    return _cachedSecondsUsed;
  }

  Future<int> getGuestSecondsRemaining() async {
    final used = await getGuestSecondsUsed();
    return (maxGuestTotalSeconds - used).clamp(0, maxGuestTotalSeconds);
  }

  Future<void> recordSecondsUsed(int totalSecondsUsed) async {
    _cachedSecondsUsed = totalSecondsUsed;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyGuestSecondsUsed, totalSecondsUsed);
    } catch (e) {
      debugPrint('[GuestSessionService] Failed to persist guest seconds: $e');
    }
  }

  Future<void> resetGuestTrial() async {
    _cachedSecondsUsed = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyGuestSecondsUsed);
    } catch (_) {}
  }
}

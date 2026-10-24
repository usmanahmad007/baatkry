import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  static const String _keyPermissionRequested = 'baatkry_perm_requested_v1';
  static const String _keyPermissionGranted = 'baatkry_perm_granted_v1';

  bool _hasRequested = false;
  bool _isGranted = false;

  bool get hasRequested => _hasRequested;
  bool get isGranted => _isGranted;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hasRequested = prefs.getBool(_keyPermissionRequested) ?? false;
      _isGranted = prefs.getBool(_keyPermissionGranted) ?? false;
    } catch (e) {
      debugPrint('[PermissionService] Failed to load permissions cache: $e');
    }
  }

  Future<void> markPermissionHandled({required bool granted}) async {
    _hasRequested = true;
    _isGranted = granted;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyPermissionRequested, true);
      await prefs.setBool(_keyPermissionGranted, granted);
    } catch (e) {
      debugPrint('[PermissionService] Failed to cache permission: $e');
    }
  }
}

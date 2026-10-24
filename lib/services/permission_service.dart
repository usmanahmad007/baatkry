import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
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

  /// Request both camera and microphone in ONE combined browser getUserMedia call.
  /// Prevents the browser from prompting twice (once for camera, then once for microphone).
  Future<bool> requestCombinedPermissions() async {
    try {
      final stream = await rtc.navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': true,
      });
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      await markPermissionHandled(granted: true);
      return true;
    } catch (e) {
      debugPrint('[PermissionService] Combined permission error: $e');
      await markPermissionHandled(granted: false);
      return false;
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

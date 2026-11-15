import 'dart:async';
import 'dart:io' show InternetAddress;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../core/theme/app_theme.dart';
import 'connectivity/web_connectivity_stub.dart'
    if (dart.library.html) 'connectivity/web_connectivity_web.dart';

class NetworkService {
  static final NetworkService instance = NetworkService._internal();
  NetworkService._internal();

  bool _isLastKnownOnline = true;
  bool get isOnline => _isLastKnownOnline;

  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get statusStream => _statusController.stream;

  /// Fast endpoints designed specifically for connectivity verification (204 No Content)
  static const List<String> _checkEndpoints = [
    'https://clients3.google.com/generate_204',
    'https://www.google.com/generate_204',
    'https://connectivitycheck.gstatic.com/generate_204',
  ];

  /// Check whether the device currently has active internet connectivity
  Future<bool> hasInternetConnection({Duration timeout = const Duration(seconds: 3)}) async {
    // 1. On Web: Browser environment connectivity check
    if (kIsWeb) {
      // Authoritative first check: If browser's window.navigator.onLine reports true,
      // return immediately without triggering any cross-origin network pings.
      if (isBrowserOnline()) {
        _updateOnlineState(true);
        return true;
      }

      // If navigator.onLine returned false (can happen on localhost/VPNs),
      // perform fallback CORS-compliant ping to verify actual reachability
      try {
        final uri = Uri.parse('https://api.github.com');
        final response = await http.get(uri).timeout(timeout);
        if (response.statusCode > 0) {
          _updateOnlineState(true);
          return true;
        }
      } catch (_) {
        // Fall back to Supabase REST endpoint which carries Access-Control-Allow-Origin: *
        if (AppConfig.supabaseUrl.isNotEmpty) {
          try {
            final uri = Uri.parse('${AppConfig.supabaseUrl}/rest/v1/');
            final response = await http.get(uri, headers: {
              'apikey': AppConfig.supabaseAnonKey,
            }).timeout(timeout);
            if (response.statusCode > 0) {
              _updateOnlineState(true);
              return true;
            }
          } catch (_) {
            // Both pings failed
          }
        }
      }

      _updateOnlineState(false);
      return false;
    }

    // 2. On Native Mobile / Desktop: Fast DNS lookup check first
    try {
      final lookup = await InternetAddress.lookup('dns.google').timeout(timeout);
      if (lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty) {
        _updateOnlineState(true);
        return true;
      }
    } catch (_) {
      // Fall back to HTTP check below
    }

    // 3. Native HTTP connectivity verification (endpoints that return 204 No Content)
    for (final urlStr in _checkEndpoints) {
      try {
        final uri = Uri.parse(urlStr);
        final response = await http.get(uri).timeout(timeout);
        if (response.statusCode >= 200 && response.statusCode < 400) {
          _updateOnlineState(true);
          return true;
        }
      } catch (_) {
        continue;
      }
    }

    _updateOnlineState(false);
    return false;
  }

  void _updateOnlineState(bool isOnline) {
    if (_isLastKnownOnline != isOnline) {
      _isLastKnownOnline = isOnline;
      if (!_statusController.isClosed) {
        _statusController.add(isOnline);
      }
    }
  }

  /// Verifies connectivity and if offline, presents a modern retry/troubleshoot modal
  /// Returns `true` if online (or user successfully retried), `false` if cancelled or offline.
  Future<bool> verifyConnectionWithPrompt(BuildContext context) async {
    final online = await hasInternetConnection();
    if (online) return true;

    if (!context.mounted) return false;

    final resolved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => const _NoInternetConnectionDialog(),
    );

    return resolved ?? false;
  }

  void dispose() {
    _statusController.close();
  }
}

class _NoInternetConnectionDialog extends StatefulWidget {
  const _NoInternetConnectionDialog();

  @override
  State<_NoInternetConnectionDialog> createState() => _NoInternetConnectionDialogState();
}

class _NoInternetConnectionDialogState extends State<_NoInternetConnectionDialog> {
  bool _isChecking = false;
  String? _errorMessage;

  Future<void> _checkAgain() async {
    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });

    final isConnected = await NetworkService.instance.hasInternetConnection(
      timeout: const Duration(seconds: 4),
    );

    if (!mounted) return;

    if (isConnected) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isChecking = false;
        _errorMessage = 'Still offline. Please check your Wi-Fi or mobile data.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppColors.danger.withOpacity(0.4), width: 1.5),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.wifi_off_rounded, color: AppColors.danger, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'No Internet Connection',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live video chat requires a stable internet connection. Please verify your Wi-Fi or mobile data network before starting.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.danger.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: AppColors.border(context)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isChecking ? null : _checkAgain,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandIndigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isChecking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.refresh_rounded, size: 18),
                              SizedBox(width: 6),
                              Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Continue anyway',
                style: TextStyle(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

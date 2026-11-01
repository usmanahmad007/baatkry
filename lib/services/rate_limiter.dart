import 'dart:collection';

/// High-performance sliding-window rate limiter for anti-fraud and anti-spam protection
class RateLimiter {
  static final RateLimiter _instance = RateLimiter._internal();
  factory RateLimiter() => _instance;
  static RateLimiter get instance => _instance;

  RateLimiter._internal();

  final Map<String, Queue<DateTime>> _actionTimestamps = {};

  /// Checks if an action is permitted within the given rate limit window.
  /// If permitted, records the timestamp and returns `true`.
  /// If rate limit is exceeded, returns `false`.
  bool checkAndRecord(
    String key, {
    required int maxAllowed,
    required Duration window,
  }) {
    final now = DateTime.now();
    final queue = _actionTimestamps.putIfAbsent(key, () => Queue<DateTime>());

    // Evict timestamps outside the window
    final cutoff = now.subtract(window);
    while (queue.isNotEmpty && queue.first.isBefore(cutoff)) {
      queue.removeFirst();
    }

    if (queue.length >= maxAllowed) {
      return false; // Rate limit exceeded
    }

    queue.addLast(now);
    return true;
  }

  /// Specialized check for virtual gift spam
  /// Allows up to [maxBurst] gifts per [window]
  bool canSendGift(String userId, {int maxBurst = 8, Duration window = const Duration(seconds: 3)}) {
    return checkAndRecord('gift_$userId', maxAllowed: maxBurst, window: window);
  }

  /// Specialized check for creator withdrawal requests
  /// Allows up to [maxRequests] per [window]
  bool canRequestWithdrawal(String userId, {int maxRequests = 2, Duration window = const Duration(minutes: 1)}) {
    return checkAndRecord('withdraw_$userId', maxAllowed: maxRequests, window: window);
  }

  /// Specialized check for user abuse reporting
  bool canSubmitReport(String userId, {int maxReports = 5, Duration window = const Duration(minutes: 2)}) {
    return checkAndRecord('report_$userId', maxAllowed: maxReports, window: window);
  }

  /// Reset records for testing or logout
  void clear([String? key]) {
    if (key != null) {
      _actionTimestamps.remove(key);
    } else {
      _actionTimestamps.clear();
    }
  }
}

// lib/utils/startup_timer.dart
import 'package:flutter/foundation.dart';

/// Measures elapsed time since app startup for performance monitoring.
///
/// A global singleton that records timestamps for key phases during app initialization
/// (Firebase initialization, config loading, first frame, API calls, etc).
/// Call [mark] after each important phase completes to track startup performance.
class StartupTimer {
  static StartupTimer? _instance;
  late final Stopwatch _stopwatch;
  final Map<String, int> _phases = {};

  StartupTimer._() {
    _stopwatch = Stopwatch()..start();
  }

  static StartupTimer get instance {
    _instance ??= StartupTimer._();
    return _instance!;
  }

  @visibleForTesting
  static void reset() {
    _instance = null;
  }

  /// Records the elapsed time since app start for the given phase.
  ///
  /// The [phase] parameter is a descriptive name for the startup phase
  /// (e.g., 'firebase', 'config', 'first_frame'). Each call updates the
  /// timestamp for that phase with the current elapsed milliseconds.
  void mark(String phase) {
    _phases[phase] = _stopwatch.elapsedMilliseconds;
    if (kDebugMode) {
      print('[STARTUP] $phase: ${_phases[phase]}ms');
    }
  }

  Map<String, int> getPhases() => Map.unmodifiable(_phases);

  /// Returns the elapsed time to the last recorded phase in milliseconds.
  ///
  /// This represents the total startup duration from app start to the latest
  /// marked phase. Returns 0 if no phases have been marked yet.
  int get totalMs {
    if (_phases.isEmpty) return 0;
    return _phases.values.reduce((a, b) => a > b ? a : b);
  }

  /// Formats the timing data for backend submission.
  ///
  /// Returns a map containing the [applicationId], [memberId], all recorded
  /// [phases], and the [totalMs] total startup duration. The returned map
  /// is suitable for JSON serialization and API submission.
  Map<String, dynamic> toPayload({
    required String applicationId,
    required String memberId,
  }) {
    return {
      'applicationId': applicationId,
      'memberId': memberId,
      'phases': Map.from(_phases),
      'totalMs': totalMs,
    };
  }
}

// lib/utils/startup_timer.dart
import 'package:flutter/foundation.dart';

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

  void mark(String phase) {
    _phases[phase] = _stopwatch.elapsedMilliseconds;
    if (kDebugMode) {
      print('⏱️  [$phase] ${_phases[phase]}ms');
    }
  }

  Map<String, int> getPhases() => Map.unmodifiable(_phases);

  int get totalMs {
    if (_phases.isEmpty) return 0;
    return _phases.values.reduce((a, b) => a > b ? a : b);
  }

  Map<String, dynamic> toPayload({
    required String applicationId,
    required String memberId,
  }) {
    return {
      'applicationId': applicationId,
      'memberId': memberId,
      'phases': Map.from(_phases),
      'total_ms': totalMs,
    };
  }
}

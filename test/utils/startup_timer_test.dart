// test/utils/startup_timer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/utils/startup_timer.dart';

void main() {
  group('StartupTimer', () {
    tearDown(StartupTimer.reset);

    test('singleton returns same instance', () {
      final timer1 = StartupTimer.instance;
      final timer2 = StartupTimer.instance;
      expect(identical(timer1, timer2), true);
    });

    test('mark records phase duration', () {
      final timer = StartupTimer.instance;
      timer.mark('firebase');
      final phases = timer.getPhases();
      expect(phases.containsKey('firebase'), true);
      expect(phases['firebase']! >= 0, true);
    });

    test('toPayload includes required fields', () {
      final timer = StartupTimer.instance;
      timer.mark('firebase');
      timer.mark('config');
      final payload = timer.toPayload(
        applicationId: 'test-app',
        memberId: 'test-member',
      );
      expect(payload['applicationId'], 'test-app');
      expect(payload['memberId'], 'test-member');
      expect(payload.containsKey('phases'), true);
      expect(payload.containsKey('total_ms'), true);
    });
  });
}

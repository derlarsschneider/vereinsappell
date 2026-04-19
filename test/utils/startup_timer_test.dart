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
      expect(payload.containsKey('totalMs'), true);
    });

    test('totalMs returns maximum elapsed time', () async {
      final timer = StartupTimer.instance;
      timer.mark('phase1');
      final phase1Time = timer.getPhases()['phase1']!;

      // Small delay to ensure phase2 has a larger timestamp
      await Future.delayed(Duration(milliseconds: 10));
      timer.mark('phase2');
      final phase2Time = timer.getPhases()['phase2']!;

      expect(timer.totalMs >= phase1Time, true);
      expect(timer.totalMs == phase2Time, true);
    });

    test('getPhases returns immutable map', () {
      final timer = StartupTimer.instance;
      timer.mark('firebase');
      final phases1 = timer.getPhases();

      // Verify map is immutable by checking that modification throws
      expect(
        () => phases1['new_phase'] = 9999,
        throwsUnsupportedError,
      );

      // Verify original internal state is still correct
      final phases2 = timer.getPhases();
      expect(phases2.containsKey('new_phase'), false);
      expect(phases2.containsKey('firebase'), true);
    });

    test('toPayload works with empty phases', () {
      final timer = StartupTimer.instance;
      final payload = timer.toPayload(
        applicationId: 'test-app',
        memberId: 'test-member',
      );
      expect(payload['applicationId'], 'test-app');
      expect(payload['memberId'], 'test-member');
      expect(payload['phases'], isEmpty);
      expect(payload['totalMs'], 0);
    });

    test('payload uses camelCase key naming', () {
      final timer = StartupTimer.instance;
      timer.mark('firebase');
      final payload = timer.toPayload(
        applicationId: 'test-app',
        memberId: 'test-member',
      );

      // Verify camelCase keys are used
      expect(payload.containsKey('totalMs'), true);
      expect(payload.containsKey('total_ms'), false);
      expect(payload.containsKey('applicationId'), true);
      expect(payload.containsKey('memberId'), true);
    });
  });
}

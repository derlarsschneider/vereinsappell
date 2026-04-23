import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/api/getraenke_api.dart';
import 'package:vereinsappell/config_loader.dart';

void main() {
  group('TallyEntry.fromMap', () {
    test('parses strich entry', () {
      final entry = TallyEntry.fromMap('alt', {
        'memberId': 'mem-1',
        'type': 'strich',
        'timestamp': 1000,
      });
      expect(entry.drinkId, 'alt');
      expect(entry.memberId, 'mem-1');
      expect(entry.type, 'strich');
    });

    test('parses flasche entry', () {
      final entry = TallyEntry.fromMap('cola', {
        'memberId': 'mem-2',
        'type': 'flasche',
        'timestamp': 2000,
      });
      expect(entry.type, 'flasche');
    });
  });

  group('parseTallies', () {
    test('returns empty list when data is null', () {
      expect(parseTallies(null), isEmpty);
    });

    test('parses nested Firebase snapshot into flat list', () {
      final data = {
        'alt': {
          'entry1': {'memberId': 'mem-1', 'type': 'strich', 'timestamp': 1},
          'entry2': {'memberId': 'mem-2', 'type': 'strich', 'timestamp': 2},
        },
        'cola': {
          'entry3': {'memberId': 'mem-1', 'type': 'flasche', 'timestamp': 3},
        },
      };
      final entries = parseTallies(data);
      expect(entries.length, 3);
      expect(entries.where((e) => e.drinkId == 'alt').length, 2);
      expect(entries.where((e) => e.drinkId == 'cola').length, 1);
    });

    test('returns empty list when top-level value is empty map', () {
      expect(parseTallies({}), isEmpty);
    });

    test('returns empty list when data is not a Map', () {
      expect(parseTallies('unexpected'), isEmpty);
    });
  });

  group('GetraenkeApi', () {
    test('deleteMark method exists and is callable', () {
      final mockConfig = AppConfig(
        apiBaseUrl: 'http://localhost:8080',
        applicationId: 'test-app',
        memberId: 'test-member',
      );
      final api = GetraenkeApi(mockConfig);

      // Verify the method exists on the GetraenkeApi instance
      expect(api.deleteMark, isNotNull);
      expect(api.deleteMark, isA<Function>());
    });
  });
}

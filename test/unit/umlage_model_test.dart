import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/models/umlage.dart';

void main() {
  group('UmlageSession', () {
    test('fromSnapshot parses all fields', () {
      final session = UmlageSession.fromSnapshot('collector-1', {
        'amount': 20,
        'name': 'Vereinsfest',
        'startedAt': 1748000000000,
        'participants': {
          'member-1': 'paid',
          'member-2': 'pending',
          'member-3': 'excluded',
        },
      });

      expect(session.collectorId, 'collector-1');
      expect(session.amount, 20);
      expect(session.name, 'Vereinsfest');
      expect(session.startedAt, 1748000000000);
      expect(session.participants['member-1'], 'paid');
      expect(session.participants['member-2'], 'pending');
      expect(session.participants['member-3'], 'excluded');
    });

    test('fromSnapshot defaults name to empty string', () {
      final session = UmlageSession.fromSnapshot('c1', {
        'amount': 10,
        'startedAt': 0,
      });
      expect(session.name, isEmpty);
    });

    test('displayName returns name when set', () {
      final session = UmlageSession.fromSnapshot('c1', {
        'amount': 10,
        'name': 'Mein Fest',
        'startedAt': 1748000000000,
      });
      expect(session.displayName, 'Mein Fest');
    });

    test('displayName returns auto-name when name is empty', () {
      final session = UmlageSession.fromSnapshot('c1', {
        'amount': 10,
        'name': '',
        'startedAt': 1748000000000,
      });
      expect(session.displayName, startsWith('Umlage '));
    });

    test('paidCount counts only paid participants', () {
      final session = UmlageSession.fromSnapshot('c1', {
        'amount': 10,
        'startedAt': 0,
        'participants': {
          'm1': 'paid',
          'm2': 'paid',
          'm3': 'pending',
          'm4': 'excluded',
        },
      });
      expect(session.paidCount, 2);
    });

    test('activeCount excludes excluded participants', () {
      final session = UmlageSession.fromSnapshot('c1', {
        'amount': 10,
        'startedAt': 0,
        'participants': {
          'm1': 'paid',
          'm2': 'pending',
          'm3': 'excluded',
        },
      });
      expect(session.activeCount, 2);
    });

    test('totalCollected = paidCount * amount', () {
      final session = UmlageSession.fromSnapshot('c1', {
        'amount': 20,
        'startedAt': 0,
        'participants': {'m1': 'paid', 'm2': 'paid', 'm3': 'pending'},
      });
      expect(session.totalCollected, 40);
    });
  });

  group('HistoryEntry', () {
    test('fromSnapshot parses all fields', () {
      final entry = HistoryEntry.fromSnapshot('hist-1', {
        'collectorId': 'collector-1',
        'amount': 20,
        'name': 'Jahresfeier',
        'startedAt': 1748000000000,
        'closedAt': 1748003600000,
        'totalPaid': 220,
        'participants': {'m1': 'paid', 'm2': 'excluded'},
      });

      expect(entry.id, 'hist-1');
      expect(entry.collectorId, 'collector-1');
      expect(entry.amount, 20);
      expect(entry.name, 'Jahresfeier');
      expect(entry.totalPaid, 220);
      expect(entry.participants['m1'], 'paid');
    });

    test('memberPaid returns true when participant is paid', () {
      final entry = HistoryEntry.fromSnapshot('h1', {
        'collectorId': 'c1',
        'amount': 10,
        'startedAt': 0,
        'closedAt': 0,
        'totalPaid': 10,
        'participants': {'m1': 'paid'},
      });
      expect(entry.memberPaid('m1'), isTrue);
      expect(entry.memberPaid('m2'), isFalse);
    });
  });
}

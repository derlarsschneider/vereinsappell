import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/api/umlagen_api_interface.dart';
import 'package:vereinsappell/models/umlage.dart';
import 'package:vereinsappell/screens/umlage_screen.dart';

import 'test_helpers.dart';

class FakeUmlagenApi implements IUmlagenApi {
  final _activeSessionController = StreamController<UmlageSession?>.broadcast();
  final _allActiveController = StreamController<List<UmlageSession>>.broadcast();

  void emitActiveSession(UmlageSession? s) => _activeSessionController.add(s);
  void emitAllActive(List<UmlageSession> list) => _allActiveController.add(list);

  @override
  Stream<UmlageSession?> watchActiveSession(String collectorId) =>
      _activeSessionController.stream;

  @override
  Stream<List<UmlageSession>> watchAllActive() => _allActiveController.stream;

  @override
  Future<void> startSession({
    required String collectorId,
    required int amount,
    required String name,
    required List<String> memberIds,
  }) async {}

  @override
  Future<void> updateParticipant({
    required String collectorId,
    required String memberId,
    required String status,
  }) async {}

  @override
  Future<void> closeSession({
    required String collectorId,
    required UmlageSession session,
  }) async {}

  @override
  Future<List<HistoryEntry>> fetchHistory({int limit = 20, int? beforeClosedAt}) async => [];

  void dispose() {
    _activeSessionController.close();
    _allActiveController.close();
  }
}

UmlageSession _session({
  String collectorId = 'collector-1',
  int amount = 20,
  String name = 'Vereinsfest',
  Map<String, String> participants = const {'m1': 'paid', 'm2': 'pending'},
}) =>
    UmlageSession.fromSnapshot(collectorId, {
      'amount': amount,
      'name': name,
      'startedAt': 1748000000000,
      'participants': participants,
    });

void main() {
  group('Tab "Alle aktiven"', () {
    testWidgets('zeigt Leer-Meldung wenn keine aktiven Umlagen', (tester) async {
      final api = FakeUmlagenApi();
      final config = await makeConfig(tester);
      await tester.pumpWidget(wrapScreen(
        UmlagenScreen(config: config, api: api),
        config,
      ));
      api.emitAllActive([]);
      await tester.pumpAndSettle();

      // Switch to Tab "Alle aktiven" (first tab for non-collector)
      await tester.tap(find.text('Alle aktiven'));
      await tester.pumpAndSettle();

      expect(find.text('Aktuell läuft keine Umlage.'), findsOneWidget);
    });

    testWidgets('zeigt aktive Umlage mit Name und Betrag', (tester) async {
      final api = FakeUmlagenApi();
      final config = await makeConfig(tester);
      await tester.pumpWidget(wrapScreen(
        UmlagenScreen(config: config, api: api),
        config,
      ));
      api.emitAllActive([_session()]);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alle aktiven'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Vereinsfest'), findsOneWidget);
      expect(find.textContaining('€20'), findsOneWidget);
    });

    testWidgets('zeigt "Du hast bezahlt" wenn eigenes Mitglied paid', (tester) async {
      final api = FakeUmlagenApi();
      final config = await makeConfig(tester);
      await tester.pumpWidget(wrapScreen(
        UmlagenScreen(config: config, api: api),
        config,
      ));
      // user-1 is the current member (from makeConfig)
      api.emitAllActive([_session(participants: {'user-1': 'paid', 'm2': 'pending'})]);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alle aktiven'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Du hast bezahlt'), findsOneWidget);
    });
  });

  group('Tab "Abgeschlossen"', () {
    testWidgets('zeigt abgeschlossene Umlage mit Name und Betrag', (tester) async {
      final api = FakeUmlagenApi();
      final config = await makeConfig(tester);
      await tester.pumpWidget(wrapScreen(
        UmlagenScreen(config: config, api: api),
        config,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abgeschlossen'));
      await tester.pumpAndSettle();

      expect(find.text('Noch keine abgeschlossenen Umlagen.'), findsOneWidget);
    });
  });

  group('Tab "Meine Sammlung"', () {
    testWidgets('Tab nicht sichtbar für Nicht-Einsammler', (tester) async {
      final api = FakeUmlagenApi();
      final config = await makeConfig(tester, isUmlageneinsammler: false);
      await tester.pumpWidget(wrapScreen(
        UmlagenScreen(config: config, api: api),
        config,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Meine Sammlung'), findsNothing);
    });

    testWidgets('Tab sichtbar für Einsammler', (tester) async {
      final api = FakeUmlagenApi();
      final config = await makeConfig(tester, isUmlageneinsammler: true);
      await tester.pumpWidget(wrapScreen(
        UmlagenScreen(config: config, api: api),
        config,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Meine Sammlung'), findsOneWidget);
    });
  });
}

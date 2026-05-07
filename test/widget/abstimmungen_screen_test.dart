import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/api/polls_api_interface.dart';
import 'package:vereinsappell/screens/abstimmungen_screen.dart';

import 'test_helpers.dart';

class FakePollsApi implements IPollsApi {
  final StreamController<List<Poll>> _controller = StreamController.broadcast();

  @override
  Stream<List<Poll>> watchPolls() => _controller.stream;

  void emit(List<Poll> polls) => _controller.add(polls);

  @override
  Future<void> vote(String pollId, String memberId, List<String> ids) async {}

  @override
  Future<void> createPoll({
    required String title,
    required String description,
    required List<String> optionTexts,
    required bool allowMultiple,
    required bool isActive,
    required bool isVisible,
    required bool isSecretBallot,
    required String authorId,
  }) async {}

  @override
  Future<void> updatePoll(
    String pollId, {
    required String title,
    required String description,
    required List<PollOption> options,
    required bool allowMultiple,
    required bool isActive,
    required bool isVisible,
    required bool isSecretBallot,
  }) async {}

  @override
  Future<void> deletePoll(String pollId) async {}
}

Poll _poll({String id = 'p1', bool isVisible = true, bool isActive = true}) =>
    Poll(
      id: id,
      title: 'Abstimmung $id',
      description: '',
      options: [
        PollOption(id: 'o1', text: 'Ja'),
        PollOption(id: 'o2', text: 'Nein'),
      ],
      allowMultiple: false,
      isActive: isActive,
      isVisible: isVisible,
      isSecretBallot: false,
      authorId: 'a',
      createdAt: 0,
      votes: {},
    );

void main() {
  testWidgets('zeigt Ladeindikator vor Stream-Event', (tester) async {
    final api = FakePollsApi();
    final config = await makeConfig(tester);
    await tester.pumpWidget(wrapScreen(
      AbstimmungenScreen(config: config, pollsApi: api),
      config,
    ));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('zeigt Leer-Meldung wenn keine Abstimmungen', (tester) async {
    final api = FakePollsApi();
    final config = await makeConfig(tester);
    await tester.pumpWidget(wrapScreen(
      AbstimmungenScreen(config: config, pollsApi: api),
      config,
    ));
    api.emit([]);
    await tester.pumpAndSettle();
    expect(find.text('Keine Abstimmungen vorhanden'), findsOneWidget);
  });

  testWidgets('zeigt Abstimmungskarten', (tester) async {
    final api = FakePollsApi();
    final config = await makeConfig(tester);
    await tester.pumpWidget(wrapScreen(
      AbstimmungenScreen(config: config, pollsApi: api),
      config,
    ));
    api.emit([_poll(id: 'p1'), _poll(id: 'p2')]);
    await tester.pumpAndSettle();
    expect(find.text('Abstimmung p1'), findsOneWidget);
    expect(find.text('Abstimmung p2'), findsOneWidget);
  });

  testWidgets('member sieht nur isVisible=true Abstimmungen', (tester) async {
    final api = FakePollsApi();
    final config = await makeConfig(tester);
    await tester.pumpWidget(wrapScreen(
      AbstimmungenScreen(config: config, pollsApi: api),
      config,
    ));
    api.emit([_poll(id: 'visible'), _poll(id: 'hidden', isVisible: false)]);
    await tester.pumpAndSettle();
    expect(find.text('Abstimmung visible'), findsOneWidget);
    expect(find.text('Abstimmung hidden'), findsNothing);
  });

  testWidgets('admin sieht + Icon in AppBar', (tester) async {
    final api = FakePollsApi();
    final config = await makeConfig(tester, isAdmin: true);
    await tester.pumpWidget(wrapScreen(
      AbstimmungenScreen(config: config, pollsApi: api),
      config,
    ));
    api.emit([]);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('member sieht kein + Icon', (tester) async {
    final api = FakePollsApi();
    final config = await makeConfig(tester, isAdmin: false);
    await tester.pumpWidget(wrapScreen(
      AbstimmungenScreen(config: config, pollsApi: api),
      config,
    ));
    api.emit([]);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('super admin sieht Löschen-Button im Edit-Dialog', (tester) async {
    final api = FakePollsApi();
    final config = await makeConfig(tester, isAdmin: true, isSuperAdmin: true);
    final poll = _poll(id: 'p1');
    await tester.pumpWidget(wrapScreen(
      AbstimmungenScreen(config: config, pollsApi: api),
      config,
    ));
    api.emit([poll]);
    await tester.pumpAndSettle();

    // Tap edit icon to open dialog
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Abstimmung löschen'), findsOneWidget);
  });

  testWidgets('admin (kein super admin) sieht keinen Löschen-Button', (tester) async {
    final api = FakePollsApi();
    final config = await makeConfig(tester, isAdmin: true, isSuperAdmin: false);
    final poll = _poll(id: 'p1');
    await tester.pumpWidget(wrapScreen(
      AbstimmungenScreen(config: config, pollsApi: api),
      config,
    ));
    api.emit([poll]);
    await tester.pumpAndSettle();

    // Tap edit icon to open dialog
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Abstimmung löschen'), findsNothing);
  });
}

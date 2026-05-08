import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/models/poll.dart';
import 'package:vereinsappell/widgets/poll_card.dart';

Poll _makePoll({
  bool isActive = true,
  bool isVisible = true,
  bool isSecretBallot = false,
  Map<String, PollVote> votes = const {},
}) {
  return Poll(
    id: 'p1',
    title: 'Test Abstimmung',
    description: 'Beschreibung hier',
    options: [
      PollOption(id: 'o1', text: 'Option A'),
      PollOption(id: 'o2', text: 'Option B'),
    ],
    allowMultiple: false,
    isActive: isActive,
    isVisible: isVisible,
    isSecretBallot: isSecretBallot,
    authorId: 'a',
    createdAt: 0,
    votes: votes,
  );
}

void main() {
  testWidgets('zeigt Titel und Beschreibung', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PollCard(
          poll: _makePoll(),
          currentMemberId: 'm1',
          isAdmin: false,
          isSuperAdmin: false,
          onVote: (_, __) async {},
        ),
      ),
    ));
    expect(find.text('Test Abstimmung'), findsOneWidget);
    expect(find.text('Beschreibung hier'), findsOneWidget);
  });

  testWidgets('zeigt Optionen wenn aktiv', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PollCard(
          poll: _makePoll(isActive: true),
          currentMemberId: 'm1',
          isAdmin: false,
          isSuperAdmin: false,
          onVote: (_, __) async {},
        ),
      ),
    ));
    expect(find.text('Option A'), findsAtLeastNWidgets(1));
    expect(find.text('Option B'), findsAtLeastNWidgets(1));
    expect(find.text('Stimme abgeben'), findsNothing);
  });

  testWidgets('zeigt Auswahl wenn bereits abgestimmt', (tester) async {
    final votes = {
      'm1': PollVote(memberId: 'm1', selectedOptionIds: ['o1'], updatedAt: 0),
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PollCard(
          poll: _makePoll(votes: votes),
          currentMemberId: 'm1',
          isAdmin: false,
          isSuperAdmin: false,
          onVote: (_, __) async {},
        ),
      ),
    ));
    expect(find.text('Stimme ändern'), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('zeigt keine Optionen wenn inaktiv', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PollCard(
          poll: _makePoll(isActive: false),
          currentMemberId: 'm1',
          isAdmin: false,
          isSuperAdmin: false,
          onVote: (_, __) async {},
        ),
      ),
    ));
    expect(find.text('Stimme abgeben'), findsNothing);
    expect(find.text('Stimme ändern'), findsNothing);
  });

  testWidgets('geheime Wahl versteckt Ergebnisse während aktiv', (tester) async {
    final votes = {
      'm2': PollVote(memberId: 'm2', selectedOptionIds: ['o1'], updatedAt: 0),
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PollCard(
          poll: _makePoll(isActive: true, isSecretBallot: true, votes: votes),
          currentMemberId: 'm1',
          isAdmin: false,
          isSuperAdmin: false,
          onVote: (_, __) async {},
        ),
      ),
    ));
    expect(find.textContaining('von'), findsNothing);
  });

  testWidgets('edit-Icon nur für Admins sichtbar', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PollCard(
          poll: _makePoll(),
          currentMemberId: 'm1',
          isAdmin: true,
          isSuperAdmin: false,
          onVote: (_, __) async {},
          onEdit: () {},
        ),
      ),
    ));
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });
}

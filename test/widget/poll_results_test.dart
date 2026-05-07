import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/models/poll.dart';
import 'package:vereinsappell/widgets/poll_results.dart';

void main() {
  testWidgets('zeigt Anzahl und Label für jede Option', (tester) async {
    final poll = Poll(
      id: 'p1',
      title: 'T',
      description: '',
      options: [
        PollOption(id: 'o1', text: 'Ja'),
        PollOption(id: 'o2', text: 'Nein'),
      ],
      allowMultiple: false,
      isActive: true,
      isVisible: true,
      isSecretBallot: false,
      authorId: 'a',
      createdAt: 0,
      votes: {
        'm1': PollVote(memberId: 'm1', selectedOptionIds: ['o1'], updatedAt: 0),
        'm2': PollVote(memberId: 'm2', selectedOptionIds: ['o1'], updatedAt: 0),
        'm3': PollVote(memberId: 'm3', selectedOptionIds: ['o2'], updatedAt: 0),
      },
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: PollResults(poll: poll))),
    );

    expect(find.text('Ja'), findsOneWidget);
    expect(find.text('Nein'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.textContaining('3 von 3'), findsOneWidget);
  });

  testWidgets('zeigt 0 Stimmen wenn niemand abgestimmt hat', (tester) async {
    final poll = Poll(
      id: 'p2',
      title: 'T',
      description: '',
      options: [PollOption(id: 'o1', text: 'Option')],
      allowMultiple: false,
      isActive: true,
      isVisible: true,
      isSecretBallot: false,
      authorId: 'a',
      createdAt: 0,
      votes: {},
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: PollResults(poll: poll, totalMembers: 5))),
    );

    expect(find.text('0'), findsOneWidget);
    expect(find.textContaining('0 von 5'), findsOneWidget);
  });
}

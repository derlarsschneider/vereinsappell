import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/models/poll.dart';
import 'package:vereinsappell/widgets/poll_form_dialog.dart';

void main() {
  Widget wrap(Widget w) => MaterialApp(home: Scaffold(body: w));

  testWidgets('zeigt leeres Formular im Create-Modus', (tester) async {
    await tester.pumpWidget(wrap(
      Builder(builder: (ctx) => ElevatedButton(
        onPressed: () => showPollFormDialog(ctx, onSave: (_) {}),
        child: const Text('open'),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Neue Abstimmung'), findsOneWidget);
    expect(find.byType(TextFormField), findsWidgets);
  });

  testWidgets('Erstellen-Button deaktiviert ohne Titel', (tester) async {
    await tester.pumpWidget(wrap(
      Builder(builder: (ctx) => ElevatedButton(
        onPressed: () => showPollFormDialog(ctx, onSave: (_) {}),
        child: const Text('open'),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final saveButton = find.text('Erstellen');
    expect(saveButton, findsOneWidget);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();
    // Form validation fired — error message appears
    expect(find.text('Titel erforderlich'), findsOneWidget);
    expect(find.text('Neue Abstimmung'), findsOneWidget);
  });

  testWidgets('zeigt bestehende Daten im Edit-Modus', (tester) async {
    final poll = Poll(
      id: 'p1',
      title: 'Meine Wahl',
      description: 'Details',
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
      votes: {},
    );
    await tester.pumpWidget(wrap(
      Builder(builder: (ctx) => ElevatedButton(
        onPressed: () => showPollFormDialog(ctx, poll: poll, onSave: (_) {}),
        child: const Text('open'),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Abstimmung bearbeiten'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Meine Wahl'), findsOneWidget);
    expect(find.text('Ja'), findsOneWidget);
    expect(find.text('Nein'), findsOneWidget);
  });
}

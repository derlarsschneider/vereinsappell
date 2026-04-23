import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/api/getraenke_api.dart';
import 'package:vereinsappell/screens/getraenke_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

TallyEntry _strich(String drinkId, String memberId) =>
    TallyEntry(drinkId: drinkId, memberId: memberId, type: 'strich');

TallyEntry _flasche(String drinkId, String memberId) =>
    TallyEntry(drinkId: drinkId, memberId: memberId, type: 'flasche');

void main() {
  group('BierdeckelCard', () {
    testWidgets('shows no bottle button for Alt', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'alt'),
        entries: [],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: null,
      )));
      expect(find.text('🍾'), findsNothing);
    });

    testWidgets('shows bottle button for Cola', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'cola'),
        entries: [],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: () {},
      )));
      expect(find.text('🍾'), findsOneWidget);
    });

    testWidgets('own strich marks are rendered red', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'alt'),
        entries: [_strich('alt', 'mem-1')],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: null,
      )));
      final redContainers = tester.widgetList<Container>(find.byType(Container)).where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) return decoration.color == const Color(0xFFE53935);
        return false;
      });
      expect(redContainers, isNotEmpty);
    });

    testWidgets('tally area is empty with no entries', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'pils'),
        entries: [],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: null,
      )));
      final stickContainers = tester.widgetList<Container>(find.byType(Container)).where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          return decoration.color == const Color(0xFFE53935) ||
              decoration.color == const Color(0xFF2C2C2C);
        }
        return false;
      });
      expect(stickContainers, isEmpty);
    });

    testWidgets('flasche entry shown as emoji in tally row', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'cola'),
        entries: [_flasche('cola', 'mem-1')],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: () {},
      )));
      expect(find.text('🍾'), findsWidgets);
    });
  });
}

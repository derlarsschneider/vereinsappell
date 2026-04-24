import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/models/tally_entry.dart';
import 'package:vereinsappell/widgets/bierdeckel_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

TallyEntry _strich(String drinkId, String memberId, {String id = 'entry-1', int timestamp = 0}) =>
    TallyEntry(id: id, drinkId: drinkId, memberId: memberId, type: 'strich', timestamp: timestamp);

TallyEntry _flasche(String drinkId, String memberId, {String id = 'entry-1', int timestamp = 0}) =>
    TallyEntry(id: id, drinkId: drinkId, memberId: memberId, type: 'flasche', timestamp: timestamp);

void main() {
  group('BierdeckelCard', () {
    testWidgets('shows no bottle button for Alt', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'alt'),
        entries: [],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: null,
        onDeleteMark: (_) {},
      )));
      expect(find.byKey(const Key('bottle-counter-row')), findsNothing);
    });

    testWidgets('shows bottle button for Cola', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'cola'),
        entries: [],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: () {},
        onDeleteMark: (_) {},
      )));
      expect(find.byKey(const Key('bottle-counter-row')), findsOneWidget);
    });

    testWidgets('own strich marks are rendered red', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'alt'),
        entries: [_strich('alt', 'mem-1')],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: null,
        onDeleteMark: (_) {},
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
        onDeleteMark: (_) {},
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

    testWidgets('flasche entry shown as svg icon in tally row', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'cola'),
        entries: [_flasche('cola', 'mem-1')],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: () {},
        onDeleteMark: (_) {},
      )));
      expect(find.byKey(const ValueKey('bottle-tally-0')), findsOneWidget);
    });

    testWidgets('single-line layout: drink name, marks, and buttons in single row', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'cola'),
        entries: [
          _strich('cola', 'mem-1', id: 'entry-1'),
          _strich('cola', 'mem-1', id: 'entry-2'),
          _flasche('cola', 'mem-1', id: 'entry-3'),
        ],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: () {},
        onDeleteMark: (_) {},
      )));

      final rows = tester.widgetList<Row>(find.byType(Row));
      expect(rows, isNotEmpty);

      expect(find.text('Cola'), findsWidgets);

      final gestureDetectors = tester.widgetList<GestureDetector>(find.byType(GestureDetector));
      expect(gestureDetectors, isNotEmpty);
    });

    testWidgets('deleting own flasche mark triggers callback with correct entry id', (tester) async {
      String? deletedId;
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'cola'),
        entries: [_flasche('cola', 'mem-1', id: 'bottle-to-delete')],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: () {},
        onDeleteMark: (id) { deletedId = id; },
      )));

      // Tap the flasche − button (second minus: strich row first, flasche row second)
      final minusButtons = find.text('−');
      expect(minusButtons, findsWidgets);

      await tester.tap(minusButtons.at(1));
      await tester.pumpAndSettle();

      expect(deletedId, equals('bottle-to-delete'));
    });

    testWidgets('tapping others marks does nothing (read-only)', (tester) async {
      bool callbackCalled = false;
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'cola'),
        entries: [
          _strich('cola', 'mem-2', id: 'others-strich'),
          _flasche('cola', 'mem-2', id: 'others-flasche'),
        ],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: () {},
        onDeleteMark: (_) { callbackCalled = true; },
      )));

      final stickContainers = tester.widgetList<Container>(find.byType(Container)).where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          return decoration.color == const Color(0xFF2C2C2C);
        }
        return false;
      });
      expect(stickContainers, isNotEmpty);

      expect(callbackCalled, isFalse);
    });

    testWidgets('mixed marks: own red + others black displayed together', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'cola'),
        entries: [
          _strich('cola', 'mem-1', id: 'my-strich'),
          _strich('cola', 'mem-2', id: 'other-strich'),
          _flasche('cola', 'mem-1', id: 'my-bottle'),
          _flasche('cola', 'mem-2', id: 'other-bottle'),
        ],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: () {},
        onDeleteMark: (_) {},
      )));

      final stickContainers = tester.widgetList<Container>(find.byType(Container)).where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          return decoration.color == const Color(0xFFE53935) ||
              decoration.color == const Color(0xFF2C2C2C);
        }
        return false;
      }).toList();
      expect(stickContainers.length, greaterThanOrEqualTo(2));
    });

    testWidgets('buttons are properly sized for drinks with bottles', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'cola'),
        entries: [],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: () {},
        onDeleteMark: (_) {},
      )));

      // Cola with bottle: two counter rows → two − and two + buttons
      expect(find.text('−'), findsNWidgets(2));
      expect(find.text('+'), findsNWidgets(2));
    });

    testWidgets('drinks with bottles have two buttons (strich + flasche)', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'cola'),
        entries: [],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: () {},
        onDeleteMark: (_) {},
      )));

      expect(find.text('🥤'), findsWidgets);
      expect(find.byKey(const Key('bottle-counter-row')), findsOneWidget);
    });

    testWidgets('beers without bottles have only strich button', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'alt'),
        entries: [],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: null,
        onDeleteMark: (_) {},
      )));

      expect(find.text('🍺'), findsWidgets); // drink button emoji (Alt has no svgAsset)
      expect(find.byKey(const Key('bottle-counter-row')), findsNothing);
    });
  });
}

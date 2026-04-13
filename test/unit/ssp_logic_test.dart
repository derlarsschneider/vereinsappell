import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/logic/ssp_logic.dart';

void main() {
  group('ergebnis', () {
    test('stein schlägt schere', () => expect(ergebnis(Zug.stein, Zug.schere), 1));
    test('schere schlägt papier', () => expect(ergebnis(Zug.schere, Zug.papier), 1));
    test('papier schlägt stein', () => expect(ergebnis(Zug.papier, Zug.stein), 1));
    test('schere verliert gegen stein', () => expect(ergebnis(Zug.schere, Zug.stein), -1));
    test('papier verliert gegen schere', () => expect(ergebnis(Zug.papier, Zug.schere), -1));
    test('stein verliert gegen papier', () => expect(ergebnis(Zug.stein, Zug.papier), -1));
    test('stein vs stein = 0', () => expect(ergebnis(Zug.stein, Zug.stein), 0));
    test('schere vs schere = 0', () => expect(ergebnis(Zug.schere, Zug.schere), 0));
    test('papier vs papier = 0', () => expect(ergebnis(Zug.papier, Zug.papier), 0));
  });

  group('zugFromString', () {
    test("'stein' → Zug.stein", () => expect(zugFromString('stein'), Zug.stein));
    test("'schere' → Zug.schere", () => expect(zugFromString('schere'), Zug.schere));
    test("'papier' → Zug.papier", () => expect(zugFromString('papier'), Zug.papier));
    test("ungültiger String → null", () => expect(zugFromString('ungültig'), null));
    test("null → null", () => expect(zugFromString(null), null));
  });

  group('zugToString / zugFromString roundtrip', () {
    for (final zug in Zug.values) {
      test('roundtrip $zug', () {
        expect(zugFromString(zugToString(zug)), zug);
      });
    }
  });

  group('Spielstand', () {
    test('fromJson setzt korrekte Felder', () {
      final s = Spielstand.fromJson({'s': 3, 'n': 1, 'u': 2});
      expect(s.siege, 3);
      expect(s.niederlagen, 1);
      expect(s.unentschieden, 2);
    });

    test('default-Konstruktor setzt alles auf 0', () {
      final s = Spielstand();
      expect(s.toJson(), {'s': 0, 'n': 0, 'u': 0});
    });

    test('fromJson(toJson()) roundtrip', () {
      final original = Spielstand(siege: 5, niederlagen: 2, unentschieden: 1);
      final copy = Spielstand.fromJson(original.toJson());
      expect(copy.siege, original.siege);
      expect(copy.niederlagen, original.niederlagen);
      expect(copy.unentschieden, original.unentschieden);
    });
  });
}

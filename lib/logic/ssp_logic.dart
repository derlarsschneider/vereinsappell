// lib/logic/ssp_logic.dart
// Pure game logic for Schere-Stein-Papier – no Flutter/Firebase dependencies.

enum Zug { schere, stein, papier }

const zugEmoji = {
  Zug.schere: '✂️',
  Zug.stein: '🪨',
  Zug.papier: '✋',
};

Zug? zugFromString(String? s) => switch (s) {
      'schere' => Zug.schere,
      'stein' => Zug.stein,
      'papier' => Zug.papier,
      _ => null,
    };

String zugToString(Zug z) => switch (z) {
      Zug.schere => 'schere',
      Zug.stein => 'stein',
      Zug.papier => 'papier',
    };

/// Returns +1 if a wins, -1 if b wins, 0 for draw.
int ergebnis(Zug a, Zug b) {
  if (a == b) return 0;
  if ((a == Zug.stein && b == Zug.schere) ||
      (a == Zug.schere && b == Zug.papier) ||
      (a == Zug.papier && b == Zug.stein)) {
    return 1;
  }
  return -1;
}

class Spielstand {
  int siege;
  int niederlagen;
  int unentschieden;

  Spielstand({this.siege = 0, this.niederlagen = 0, this.unentschieden = 0});

  factory Spielstand.fromJson(Map<dynamic, dynamic> map) => Spielstand(
        siege: (map['s'] as int?) ?? 0,
        niederlagen: (map['n'] as int?) ?? 0,
        unentschieden: (map['u'] as int?) ?? 0,
      );

  Map<String, int> toJson() => {'s': siege, 'n': niederlagen, 'u': unentschieden};
}

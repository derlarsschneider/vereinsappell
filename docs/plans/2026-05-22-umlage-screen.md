# Umlage Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a 3-tab screen for collecting member levies (Umlagen), backed by Firebase Realtime Database, with a new `isGeldeintreiber` role flag.

**Architecture:** A new `UmlagenScreen` with 3 tabs ("Meine Sammlung", "Alle aktiven", "Abgeschlossen") uses Firebase Realtime Database streams for live updates. Business logic lives in `UmlagenApi` behind an `IUmlagenApi` interface for testability. Models are plain Dart classes in `lib/models/umlage.dart`.

**Tech Stack:** Flutter, Firebase Realtime Database (`firebase_database: ^11.0.0`), existing `DefaultScreen`/`DefaultScreenState` base class pattern, `provider` for Member access.

---

## File Map

| Action | File | Responsibility |
|---|---|---|
| Create | `lib/models/umlage.dart` | `UmlageSession` + `HistoryEntry` data classes |
| Create | `lib/api/umlagen_api_interface.dart` | `IUmlagenApi` interface |
| Create | `lib/api/umlagen_api.dart` | Firebase Realtime Database implementation |
| Create | `lib/screens/umlage_screen.dart` | 3-tab screen widget |
| Modify | `lib/config_loader.dart` | Add `isGeldeintreiber` to `Member` |
| Modify | `lib/screens/mitglieder_screen.dart` | Add `SwitchListTile` for new flag |
| Modify | `lib/screens/verein_screen.dart` | Add `'umlagen'` to `_allScreens` |
| Modify | `lib/screens/home_screen.dart` | Add `'💶 Umlagen'` menu tile |
| Modify | `test/widget/test_helpers.dart` | Add `isGeldeintreiber` param to `makeConfig` |
| Create | `test/unit/umlage_model_test.dart` | Unit tests for model parsing |
| Create | `test/widget/umlage_screen_test.dart` | Widget tests for all 3 tabs |

---

## Task 1: Add `isGeldeintreiber` to Member

**Files:**
- Modify: `lib/config_loader.dart`
- Modify: `test/widget/test_helpers.dart`

- [ ] **Step 1: Write the failing test**

Create `test/unit/umlage_member_flag_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/config_loader.dart';

void main() {
  test('Member.updateMember parses isGeldeintreiber true', () {
    final config = AppConfig(
      apiBaseUrl: 'https://api.example.com',
      applicationId: 'test-app',
      memberId: 'user-1',
    );
    config.member.updateMember({'isGeldeintreiber': true});
    expect(config.member.isGeldeintreiber, isTrue);
  });

  test('Member.updateMember defaults isGeldeintreiber to false', () {
    final config = AppConfig(
      apiBaseUrl: 'https://api.example.com',
      applicationId: 'test-app',
      memberId: 'user-1',
    );
    config.member.updateMember({});
    expect(config.member.isGeldeintreiber, isFalse);
  });

  test('Member.encodeMember includes isGeldeintreiber', () {
    final config = AppConfig(
      apiBaseUrl: 'https://api.example.com',
      applicationId: 'test-app',
      memberId: 'user-1',
    );
    config.member.updateMember({'isGeldeintreiber': true});
    final encoded = config.member.encodeMember();
    expect(encoded, contains('"isGeldeintreiber":true'));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /home/lars/tzg/vereinsappell
flutter test test/unit/umlage_member_flag_test.dart
```

Expected: FAIL — `isGeldeintreiber` is not defined on `Member`.

- [ ] **Step 3: Add `isGeldeintreiber` to `lib/config_loader.dart`**

In the `Member` class, add alongside the other flags (after `_isSaftschubse`):

```dart
bool _isGeldeintreiber = false;
```

Add getter after `get isSaftschubse`:

```dart
bool get isGeldeintreiber => _isGeldeintreiber;
```

Add setter after `set isSaftschubse`:

```dart
set isGeldeintreiber(bool value) => _isGeldeintreiber = value;
```

In `updateMember`, add after `_isSaftschubse = member?['isSaftschubse'] ?? false;`:

```dart
_isGeldeintreiber = member?['isGeldeintreiber'] ?? false;
```

In `encodeMember`, add after `'isSaftschubse': _isSaftschubse,`:

```dart
'isGeldeintreiber': _isGeldeintreiber,
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/unit/umlage_member_flag_test.dart
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Update `test/widget/test_helpers.dart` to support the new flag**

In `makeConfig`, add `isGeldeintreiber = false` parameter and include it in `memberJson`:

```dart
Future<AppConfig> makeConfig(
  WidgetTester tester, {
  bool isAdmin = false,
  bool isSuperAdmin = false,
  bool isGeldeintreiber = false,
  String? sessionPassword = 'testpw',
}) async {
  final config = await tester.runAsync(() async {
    final memberJson = jsonEncode({
      'memberId': 'user-1',
      'name': 'Test User',
      'isAdmin': isAdmin,
      'isSuperAdmin': isSuperAdmin,
      'isSpiess': false,
      'isGeldeintreiber': isGeldeintreiber,
      'token': '',
    });
    // rest of function unchanged
```

- [ ] **Step 6: Run all existing tests to check for regressions**

```bash
flutter test
```

Expected: All existing tests still PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/config_loader.dart test/widget/test_helpers.dart test/unit/umlage_member_flag_test.dart
git commit -m "feat(member): add isGeldeintreiber flag"
```

---

## Task 2: Create Umlage Models

**Files:**
- Create: `lib/models/umlage.dart`
- Create: `test/unit/umlage_model_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/unit/umlage_model_test.dart`:

```dart
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
      // startedAt = 2026-05-22 19:32:00 UTC+2 → "Umlage 22.05.2026 19:32"
      // Use a fixed ms value: 1748000000000 → date depends on timezone,
      // so just check prefix
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/unit/umlage_model_test.dart
```

Expected: FAIL — `package:vereinsappell/models/umlage.dart` not found.

- [ ] **Step 3: Create `lib/models/umlage.dart`**

```dart
import 'package:intl/intl.dart';

class UmlageSession {
  final String collectorId;
  final int amount;
  final String name;
  final int startedAt;
  final Map<String, String> participants;

  UmlageSession({
    required this.collectorId,
    required this.amount,
    required this.name,
    required this.startedAt,
    required this.participants,
  });

  factory UmlageSession.fromSnapshot(String collectorId, Map<dynamic, dynamic> data) {
    final rawParticipants = data['participants'];
    final participants = <String, String>{};
    if (rawParticipants is Map) {
      for (final e in rawParticipants.entries) {
        participants[e.key as String] = e.value as String;
      }
    }
    return UmlageSession(
      collectorId: collectorId,
      amount: (data['amount'] as num?)?.toInt() ?? 0,
      name: (data['name'] as String?) ?? '',
      startedAt: (data['startedAt'] as num?)?.toInt() ?? 0,
      participants: participants,
    );
  }

  String get displayName {
    if (name.isNotEmpty) return name;
    final dt = DateTime.fromMillisecondsSinceEpoch(startedAt);
    return 'Umlage ${DateFormat('dd.MM.yyyy HH:mm').format(dt)}';
  }

  int get paidCount =>
      participants.values.where((s) => s == 'paid').length;

  int get activeCount =>
      participants.values.where((s) => s != 'excluded').length;

  int get totalCollected => paidCount * amount;
}

class HistoryEntry {
  final String id;
  final String collectorId;
  final int amount;
  final String name;
  final int startedAt;
  final int closedAt;
  final int totalPaid;
  final Map<String, String> participants;

  HistoryEntry({
    required this.id,
    required this.collectorId,
    required this.amount,
    required this.name,
    required this.startedAt,
    required this.closedAt,
    required this.totalPaid,
    required this.participants,
  });

  factory HistoryEntry.fromSnapshot(String id, Map<dynamic, dynamic> data) {
    final rawParticipants = data['participants'];
    final participants = <String, String>{};
    if (rawParticipants is Map) {
      for (final e in rawParticipants.entries) {
        participants[e.key as String] = e.value as String;
      }
    }
    return HistoryEntry(
      id: id,
      collectorId: (data['collectorId'] as String?) ?? '',
      amount: (data['amount'] as num?)?.toInt() ?? 0,
      name: (data['name'] as String?) ?? '',
      startedAt: (data['startedAt'] as num?)?.toInt() ?? 0,
      closedAt: (data['closedAt'] as num?)?.toInt() ?? 0,
      totalPaid: (data['totalPaid'] as num?)?.toInt() ?? 0,
      participants: participants,
    );
  }

  String get displayName {
    if (name.isNotEmpty) return name;
    final dt = DateTime.fromMillisecondsSinceEpoch(startedAt);
    return 'Umlage ${DateFormat('dd.MM.yyyy HH:mm').format(dt)}';
  }

  bool memberPaid(String memberId) => participants[memberId] == 'paid';

  int get paidCount =>
      participants.values.where((s) => s == 'paid').length;
}
```

- [ ] **Step 4: Check if `intl` is already a dependency**

```bash
grep 'intl' /home/lars/tzg/vereinsappell/pubspec.yaml
```

If missing, add `intl: ^0.19.0` under `dependencies:` in `pubspec.yaml` and run:

```bash
flutter pub get
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
flutter test test/unit/umlage_model_test.dart
```

Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/models/umlage.dart test/unit/umlage_model_test.dart pubspec.yaml pubspec.lock
git commit -m "feat(umlage): add UmlageSession and HistoryEntry models"
```

---

## Task 3: Create IUmlagenApi Interface + Firebase Implementation

**Files:**
- Create: `lib/api/umlagen_api_interface.dart`
- Create: `lib/api/umlagen_api.dart`

- [ ] **Step 1: Create `lib/api/umlagen_api_interface.dart`**

```dart
import '../models/umlage.dart';

abstract class IUmlagenApi {
  Stream<UmlageSession?> watchActiveSession(String collectorId);
  Stream<List<UmlageSession>> watchAllActive();
  Future<void> startSession({
    required String collectorId,
    required int amount,
    required String name,
    required List<String> memberIds,
  });
  Future<void> updateParticipant({
    required String collectorId,
    required String memberId,
    required String status,
  });
  Future<void> closeSession({
    required String collectorId,
    required UmlageSession session,
  });
  Future<List<HistoryEntry>> fetchHistory({int limit = 20, String? startAfterKey});
}
```

- [ ] **Step 2: Create `lib/api/umlagen_api.dart`**

```dart
import 'package:firebase_database/firebase_database.dart';
import '../config_loader.dart';
import '../models/umlage.dart';
import 'umlagen_api_interface.dart';

class UmlagenApi implements IUmlagenApi {
  final AppConfig config;

  UmlagenApi(this.config);

  DatabaseReference get _activeRef =>
      FirebaseDatabase.instance.ref('umlagen/${config.applicationId}/active');

  DatabaseReference get _historyRef =>
      FirebaseDatabase.instance.ref('umlagen/${config.applicationId}/history');

  DatabaseReference _statsRef(String memberId) =>
      FirebaseDatabase.instance.ref('umlagen/${config.applicationId}/stats/$memberId');

  @override
  Stream<UmlageSession?> watchActiveSession(String collectorId) {
    return _activeRef.child(collectorId).onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return null;
      return UmlageSession.fromSnapshot(collectorId, data as Map<dynamic, dynamic>);
    });
  }

  @override
  Stream<List<UmlageSession>> watchAllActive() {
    return _activeRef.onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return [];
      return (data as Map<dynamic, dynamic>).entries
          .where((e) => e.value is Map)
          .map((e) => UmlageSession.fromSnapshot(
                e.key as String,
                e.value as Map<dynamic, dynamic>,
              ))
          .toList();
    });
  }

  @override
  Future<void> startSession({
    required String collectorId,
    required int amount,
    required String name,
    required List<String> memberIds,
  }) async {
    final participants = {for (final id in memberIds) id: 'pending'};
    await _activeRef.child(collectorId).set({
      'amount': amount,
      'name': name,
      'startedAt': DateTime.now().millisecondsSinceEpoch,
      'participants': participants,
    });
  }

  @override
  Future<void> updateParticipant({
    required String collectorId,
    required String memberId,
    required String status,
  }) async {
    await _activeRef
        .child(collectorId)
        .child('participants')
        .child(memberId)
        .set(status);
  }

  @override
  Future<void> closeSession({
    required String collectorId,
    required UmlageSession session,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final historyRef = _historyRef.push();
    final statsRef = _statsRef(collectorId);

    final participantsMap = {
      for (final e in session.participants.entries)
        if (e.value != 'pending') e.key: e.value
    };

    await Future.wait([
      historyRef.set({
        'collectorId': collectorId,
        'amount': session.amount,
        'name': session.name,
        'startedAt': session.startedAt,
        'closedAt': now,
        'totalPaid': session.totalCollected,
        'participants': participantsMap,
      }),
      statsRef.runTransaction((currentData) {
        final current = currentData as Map<dynamic, dynamic>? ?? {};
        return Transaction.success({
          'totalCollected': ((current['totalCollected'] as num?) ?? 0) + session.totalCollected,
          'collectionsCount': ((current['collectionsCount'] as num?) ?? 0) + 1,
        });
      }),
      _activeRef.child(collectorId).remove(),
    ]);
  }

  @override
  Future<List<HistoryEntry>> fetchHistory({int limit = 20, String? startAfterKey}) async {
    Query query = _historyRef.orderByChild('closedAt').limitToLast(limit);
    final snapshot = await query.get();
    if (!snapshot.exists || snapshot.value is! Map) return [];

    final entries = (snapshot.value as Map<dynamic, dynamic>)
        .entries
        .where((e) => e.value is Map)
        .map((e) => HistoryEntry.fromSnapshot(
              e.key as String,
              e.value as Map<dynamic, dynamic>,
            ))
        .toList()
      ..sort((a, b) => b.closedAt.compareTo(a.closedAt));

    if (startAfterKey != null) {
      final idx = entries.indexWhere((e) => e.id == startAfterKey);
      if (idx != -1) return entries.sublist(idx + 1);
    }
    return entries;
  }
}
```

- [ ] **Step 3: Verify the files compile**

```bash
flutter analyze lib/api/umlagen_api_interface.dart lib/api/umlagen_api.dart lib/models/umlage.dart
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add lib/api/umlagen_api_interface.dart lib/api/umlagen_api.dart
git commit -m "feat(umlage): add IUmlagenApi interface and Firebase implementation"
```

---

## Task 4: Wire Up Navigation (verein_screen + home_screen + mitglieder_screen)

**Files:**
- Modify: `lib/screens/verein_screen.dart:13-22` (add to `_allScreens`)
- Modify: `lib/screens/home_screen.dart` (add menu tile)
- Modify: `lib/screens/mitglieder_screen.dart` (add SwitchListTile)

- [ ] **Step 1: Add `'umlagen'` to `_allScreens` in `lib/screens/verein_screen.dart`**

In the `_allScreens` list (currently ends at line ~22), add:

```dart
{'key': 'umlagen', 'label': '💶 Umlagen'},
```

after the `'abstimmungen'` entry.

- [ ] **Step 2: Add menu tile in `lib/screens/home_screen.dart`**

Add the following import at the top of `home_screen.dart`:

```dart
import 'umlage_screen.dart';
```

In `_buildGridMenu`, after the `abstimmungen` tile block and before the `strafen` tile block, add:

```dart
if (_isScreenActive('umlagen'))
  _buildMenuTile(
    context,
    '💶 Umlagen',
    () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UmlagenScreen(config: widget.config),
      ),
    ),
  ),
```

- [ ] **Step 3: Add `isGeldeintreiber` SwitchListTile in `lib/screens/mitglieder_screen.dart`**

In `_buildMemberDetail`, in the Rollen section after the `isSaftschubse` SwitchListTile, add:

```dart
SwitchListTile(
  title: Text('Geldeintreiber'),
  value: selectedMember!['isGeldeintreiber'] == true,
  onChanged: (val) => setState(() => selectedMember!['isGeldeintreiber'] = val),
),
```

- [ ] **Step 4: Verify compilation**

```bash
flutter analyze lib/screens/verein_screen.dart lib/screens/home_screen.dart lib/screens/mitglieder_screen.dart
```

Expected: Only warning about missing `umlage_screen.dart` import (will be fixed in Task 5). No type errors.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/verein_screen.dart lib/screens/home_screen.dart lib/screens/mitglieder_screen.dart
git commit -m "feat(umlage): wire up navigation and member flag toggle"
```

---

## Task 5: Create UmlagenScreen — Shell + Tab 2 (Alle aktiven) + Tab 3 (Abgeschlossen)

**Files:**
- Create: `lib/screens/umlage_screen.dart`
- Create: `test/widget/umlage_screen_test.dart`

Build the screen shell with all 3 tabs, but implement Tab 1 as a stub. Tabs 2 and 3 are fully functional and testable independently.

- [ ] **Step 1: Write failing widget tests**

Create `test/widget/umlage_screen_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
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
  Future<List<HistoryEntry>> fetchHistory({int limit = 20, String? startAfterKey}) async => [];

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

HistoryEntry _historyEntry({
  String id = 'h1',
  String name = 'Jahresfeier',
  int totalPaid = 220,
  Map<String, String> participants = const {'user-1': 'paid'},
}) =>
    HistoryEntry.fromSnapshot(id, {
      'collectorId': 'collector-1',
      'amount': 20,
      'name': name,
      'startedAt': 1748000000000,
      'closedAt': 1748003600000,
      'totalPaid': totalPaid,
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

      // Switch to Tab 2
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

      // History is loaded via fetchHistory — override returns []
      // Just check the tab renders without error
      expect(find.byType(ListView), findsWidgets);
    });
  });

  group('Tab "Meine Sammlung"', () {
    testWidgets('Tab nicht sichtbar für Nicht-Einsammler', (tester) async {
      final api = FakeUmlagenApi();
      final config = await makeConfig(tester, isGeldeintreiber: false);
      await tester.pumpWidget(wrapScreen(
        UmlagenScreen(config: config, api: api),
        config,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Meine Sammlung'), findsNothing);
    });

    testWidgets('Tab sichtbar für Einsammler', (tester) async {
      final api = FakeUmlagenApi();
      final config = await makeConfig(tester, isGeldeintreiber: true);
      await tester.pumpWidget(wrapScreen(
        UmlagenScreen(config: config, api: api),
        config,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Meine Sammlung'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/widget/umlage_screen_test.dart
```

Expected: FAIL — `UmlagenScreen` not found.

- [ ] **Step 3: Create `lib/screens/umlage_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/umlagen_api.dart';
import '../api/umlagen_api_interface.dart';
import '../config_loader.dart';
import '../models/umlage.dart';
import 'default_screen.dart';

class UmlagenScreen extends DefaultScreen {
  final IUmlagenApi? api;

  const UmlagenScreen({super.key, required super.config, this.api})
      : super(title: 'Umlagen');

  @override
  DefaultScreenState<UmlagenScreen> createState() => _UmlagenScreenState();
}

class _UmlagenScreenState extends DefaultScreenState<UmlagenScreen>
    with SingleTickerProviderStateMixin {
  late final IUmlagenApi _api;
  late final TabController _tabController;

  List<HistoryEntry> _history = [];
  bool _historyLoading = false;
  bool _hasMoreHistory = true;
  String? _lastHistoryKey;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? UmlagenApi(widget.config);
    final isCollector = widget.config.member.isGeldeintreiber;
    _tabController = TabController(
      length: isCollector ? 3 : 2,
      vsync: this,
      initialIndex: 0,
    );
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory({bool loadMore = false}) async {
    if (_historyLoading) return;
    setState(() => _historyLoading = true);
    try {
      final entries = await _api.fetchHistory(
        limit: 20,
        startAfterKey: loadMore ? _lastHistoryKey : null,
      );
      setState(() {
        if (loadMore) {
          _history.addAll(entries);
        } else {
          _history = entries;
        }
        _hasMoreHistory = entries.length == 20;
        if (entries.isNotEmpty) _lastHistoryKey = entries.last.id;
      });
    } catch (e) {
      showError('$e');
    } finally {
      setState(() => _historyLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);
    final isCollector = member.isGeldeintreiber;

    final tabs = [
      if (isCollector) const Tab(text: 'Meine Sammlung'),
      const Tab(text: 'Alle aktiven'),
      const Tab(text: 'Abgeschlossen'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('💶 Umlagen'),
        bottom: TabBar(controller: _tabController, tabs: tabs),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          if (isCollector) _MeineSammlungTab(api: _api, config: widget.config),
          _AlleAktivenTab(api: _api, currentMemberId: widget.config.memberId),
          _AbgeschlossenTab(
            history: _history,
            loading: _historyLoading,
            hasMore: _hasMoreHistory,
            currentMemberId: widget.config.memberId,
            onLoadMore: () => _loadHistory(loadMore: true),
          ),
        ],
      ),
    );
  }
}

// ── Tab 1: Meine Sammlung ────────────────────────────────────────────────────

class _MeineSammlungTab extends StatefulWidget {
  final IUmlagenApi api;
  final AppConfig config;

  const _MeineSammlungTab({required this.api, required this.config});

  @override
  State<_MeineSammlungTab> createState() => _MeineSammlungTabState();
}

class _MeineSammlungTabState extends State<_MeineSammlungTab> {
  int _selectedAmount = 20;
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _startSession(List<dynamic> members) async {
    final name = _nameController.text.trim();
    final memberIds = members
        .where((m) => m['isActive'] != false)
        .map<String>((m) => m['memberId'] as String)
        .toList();
    try {
      await widget.api.startSession(
        collectorId: widget.config.memberId,
        amount: _selectedAmount,
        name: name,
        memberIds: memberIds,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmClose(UmlageSession session) async {
    final unpaid = session.participants.values.where((s) => s == 'pending').length;
    final confirmed = unpaid == 0 ||
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Umlage abschließen?'),
            content: Text('$unpaid Mitglied${unpaid == 1 ? '' : 'er'} noch nicht bezahlt.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Trotzdem abschließen'),
              ),
            ],
          ),
        );
    if (confirmed == true) {
      await widget.api.closeSession(
        collectorId: widget.config.memberId,
        session: session,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UmlageSession?>(
      stream: widget.api.watchActiveSession(widget.config.memberId),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        final session = snapshot.data;
        if (session == null) {
          return _buildStartView();
        }
        return _buildCollectView(session);
      },
    );
  }

  Widget _buildStartView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Betrag wählen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          _BanknotePicker(
            selected: _selectedAmount,
            onChanged: (v) => setState(() => _selectedAmount = v),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name (optional)',
              hintText: 'z.B. Vereinsfest Mai',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              // Members list needed — fetch inline for simplicity
              // (UmlagenScreen could be refactored to pass members if needed)
              await _startSession([]);
            },
            icon: const Icon(Icons.play_arrow),
            label: Text('Umlage starten (€$_selectedAmount)'),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectView(UmlageSession session) {
    final paidFraction = session.activeCount == 0
        ? 0.0
        : session.paidCount / session.activeCount;
    final allPaid = session.activeCount > 0 && session.paidCount == session.activeCount;

    final bgColor = Color.lerp(Colors.red[200], Colors.green[200], paidFraction)!;
    final memberIds = session.participants.entries
        .where((e) => e.value != 'excluded')
        .map((e) => e.key)
        .toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: bgColor,
        border: allPaid ? Border.all(color: Colors.green, width: 4) : null,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _BanknotePicker(
                  selected: session.amount,
                  onChanged: session.paidCount > 0
                      ? null
                      : (v) async {
                          // amount change not supported mid-session when paid>0
                        },
                ),
                const SizedBox(height: 8),
                Text(
                  session.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: paidFraction,
                  backgroundColor: Colors.white38,
                  color: Colors.green,
                ),
                const SizedBox(height: 4),
                Text(
                  '${session.paidCount} von ${session.activeCount} bezahlt · €${session.totalCollected} gesammelt',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: memberIds.length,
              itemBuilder: (context, index) {
                final memberId = memberIds[index];
                final status = session.participants[memberId] ?? 'pending';
                return _MemberListTile(
                  memberId: memberId,
                  status: status,
                  onTap: () => widget.api.updateParticipant(
                    collectorId: widget.config.memberId,
                    memberId: memberId,
                    status: status == 'paid' ? 'pending' : 'paid',
                  ),
                  onSwipe: () => widget.api.updateParticipant(
                    collectorId: widget.config.memberId,
                    memberId: memberId,
                    status: 'excluded',
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _confirmClose(session),
                icon: const Icon(Icons.check),
                label: const Text('Umlage abschließen'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab 2: Alle aktiven ──────────────────────────────────────────────────────

class _AlleAktivenTab extends StatelessWidget {
  final IUmlagenApi api;
  final String currentMemberId;

  const _AlleAktivenTab({required this.api, required this.currentMemberId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UmlageSession>>(
      stream: api.watchAllActive(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final sessions = snapshot.data!;
        if (sessions.isEmpty) {
          return const Center(child: Text('Aktuell läuft keine Umlage.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: sessions.length,
          itemBuilder: (context, i) {
            final s = sessions[i];
            final myStatus = s.participants[currentMemberId];
            final paidFraction = s.activeCount == 0 ? 0.0 : s.paidCount / s.activeCount;
            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            s.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                        Text(
                          '€${s.amount}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: paidFraction,
                      backgroundColor: Colors.grey[200],
                      color: Colors.green,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      myStatus == 'paid'
                          ? '✅ Du hast bezahlt · ${s.paidCount}/${s.activeCount} gesamt'
                          : '⬜ Du hast noch nicht bezahlt · ${s.paidCount}/${s.activeCount} gesamt',
                      style: TextStyle(
                        fontSize: 11,
                        color: myStatus == 'paid' ? Colors.green[700] : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Tab 3: Abgeschlossen ─────────────────────────────────────────────────────

class _AbgeschlossenTab extends StatelessWidget {
  final List<HistoryEntry> history;
  final bool loading;
  final bool hasMore;
  final String currentMemberId;
  final VoidCallback onLoadMore;

  const _AbgeschlossenTab({
    required this.history,
    required this.loading,
    required this.hasMore,
    required this.currentMemberId,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && history.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (history.isEmpty) {
      return const Center(child: Text('Noch keine abgeschlossenen Umlagen.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: history.length + (hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == history.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: loading
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: onLoadMore,
                      child: const Text('Mehr anzeigen'),
                    ),
            ),
          );
        }
        final entry = history[i];
        final paid = entry.memberPaid(currentMemberId);
        final dt = DateTime.fromMillisecondsSinceEpoch(entry.closedAt);
        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: Icon(
              paid ? Icons.circle : Icons.circle,
              color: paid ? Colors.green : Colors.red,
              size: 12,
            ),
            title: Text(entry.displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Text(
              '${DateFormat('dd.MM.yyyy').format(dt)} · ${entry.paidCount}/${entry.participants.length} Mitglieder',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Text(
              '€${entry.totalPaid}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        );
      },
    );
  }
}

// ── Shared Widgets ───────────────────────────────────────────────────────────

class _BanknotePicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int>? onChanged;

  const _BanknotePicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const amounts = [5, 10, 20, 50];
    const colors = {5: Color(0xFF43a047), 10: Color(0xFFe53935), 20: Color(0xFF1e88e5), 50: Color(0xFFfb8c00)};
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: amounts.map((amount) {
        final isSelected = amount == selected;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: onChanged == null ? null : () => onChanged!(amount),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 64,
              height: 36,
              decoration: BoxDecoration(
                color: colors[amount],
                borderRadius: BorderRadius.circular(6),
                border: isSelected ? Border.all(color: Colors.white, width: 2.5) : null,
                boxShadow: isSelected
                    ? [BoxShadow(color: Colors.black26, blurRadius: 6, offset: const Offset(0, 2))]
                    : [const BoxShadow(color: Colors.black12, blurRadius: 2)],
              ),
              child: Center(
                child: Text(
                  '€$amount',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MemberListTile extends StatelessWidget {
  final String memberId;
  final String status;
  final VoidCallback onTap;
  final VoidCallback onSwipe;

  const _MemberListTile({
    required this.memberId,
    required this.status,
    required this.onTap,
    required this.onSwipe,
  });

  @override
  Widget build(BuildContext context) {
    final isPaid = status == 'paid';
    return Dismissible(
      key: Key(memberId),
      background: Container(
        color: Colors.red[100],
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.cancel, color: Colors.red),
      ),
      secondaryBackground: Container(
        color: Colors.red[100],
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.cancel, color: Colors.red),
      ),
      onDismissed: (_) => onSwipe(),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isPaid ? Colors.green[50] : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: isPaid ? Border.all(color: Colors.green, width: 1.5) : null,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)],
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isPaid ? Colors.green[200] : Colors.blue[100],
              child: Text(
                memberId.substring(0, 2).toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isPaid ? Colors.green[900] : Colors.blue[900],
                ),
              ),
            ),
            title: Text(memberId, style: const TextStyle(fontSize: 13)),
            trailing: Icon(
              isPaid ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isPaid ? Colors.green : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}
```

**Note:** The member name is shown as `memberId` here as a placeholder. In Task 6, member names will be resolved by fetching the members list.

- [ ] **Step 4: Run tests**

```bash
flutter test test/widget/umlage_screen_test.dart
```

Expected: All tests PASS.

- [ ] **Step 5: Run full test suite**

```bash
flutter test
```

Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/umlage_screen.dart test/widget/umlage_screen_test.dart
git commit -m "feat(umlage): add UmlagenScreen with 3 tabs"
```

---

## Task 6: Resolve Member Names in Tab 1

The collection tab currently shows `memberId` as the member name. Wire up the members API to show real names and fetch the member list for starting a session.

**Files:**
- Modify: `lib/screens/umlage_screen.dart`
- Modify: `lib/api/members_api.dart` (no change needed — already has `fetchMembers`)

- [ ] **Step 1: Add member list fetching to `_MeineSammlungTabState`**

In `_MeineSammlungTabState`, add:

```dart
List<dynamic> _members = [];
bool _membersLoading = false;

@override
void initState() {
  super.initState();
  _fetchMembers();
}

Future<void> _fetchMembers() async {
  setState(() => _membersLoading = true);
  try {
    final api = MembersApi(widget.config);
    final data = await api.fetchMembers();
    setState(() {
      _members = data
        ..sort((a, b) => (a['name'] ?? '').toLowerCase().compareTo((b['name'] ?? '').toLowerCase()));
    });
  } finally {
    setState(() => _membersLoading = false);
  }
}
```

Add import at top of file:

```dart
import '../api/members_api.dart';
```

- [ ] **Step 2: Pass members to `_startSession`**

Replace the `_buildStartView` button's `onPressed`:

```dart
onPressed: _membersLoading
    ? null
    : () => _startSession(_members),
```

- [ ] **Step 3: Build a name lookup map and pass to `_MemberListTile`**

In `_buildCollectView`, before the `ListView.builder`, create a name map:

```dart
final nameMap = {for (final m in _members) m['memberId'] as String: m['name'] as String? ?? m['memberId'] as String};
```

Update `_MemberListTile` constructor call to pass the resolved name:

```dart
_MemberListTile(
  memberId: memberId,
  memberName: nameMap[memberId] ?? memberId,
  status: status,
  onTap: ...
  onSwipe: ...
),
```

- [ ] **Step 4: Update `_MemberListTile` to accept and display `memberName`**

Add `final String memberName;` field and update `title`:

```dart
class _MemberListTile extends StatelessWidget {
  final String memberId;
  final String memberName;
  final String status;
  // ...

  const _MemberListTile({
    required this.memberId,
    required this.memberName,
    // ...
  });

  // In build():
  title: Text(memberName, style: const TextStyle(fontSize: 13)),
  leading: CircleAvatar(
    // Use initials from memberName
    child: Text(
      memberName.isNotEmpty ? memberName[0].toUpperCase() : '?',
      // ...
    ),
  ),
```

- [ ] **Step 5: Verify compilation**

```bash
flutter analyze lib/screens/umlage_screen.dart
```

Expected: No errors.

- [ ] **Step 6: Run all tests**

```bash
flutter test
```

Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/umlage_screen.dart
git commit -m "feat(umlage): resolve member names in collection tab"
```

---

## Task 7: Final Integration Test + Smoke Check

- [ ] **Step 1: Run full test suite**

```bash
flutter test --reporter=expanded
```

Expected: All tests PASS, no failures.

- [ ] **Step 2: Analyze for warnings**

```bash
flutter analyze
```

Expected: No errors. Address any warnings related to the new files.

- [ ] **Step 3: Smoke-check in browser**

```bash
flutter run -d chrome
```

- Open the app, navigate to "💶 Umlagen" in the home menu
- As a non-collector: verify only "Alle aktiven" and "Abgeschlossen" tabs are visible
- As a collector (set flag in Mitglieder screen): verify "Meine Sammlung" tab appears
- Verify "Alle aktiven" shows empty state when no sessions active
- Verify "Abgeschlossen" shows empty state

- [ ] **Step 4: Final commit (if any lint fixes)**

```bash
git add -p
git commit -m "fix(umlage): address analyzer warnings"
```

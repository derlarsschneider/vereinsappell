# Getränke Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a live tally-mark drinks screen where all members can mark drinks and Saftschubse members can reset all marks.

**Architecture:** Flutter writes directly to Firebase Realtime Database (already in pubspec); all clients listen via `.onValue` stream for live updates. Member permission flag `isSaftschubse` is added to DynamoDB/Lambda and surfaced in the admin UI.

**Tech Stack:** Flutter/Dart, Firebase Realtime Database (`firebase_database ^11.0.0` — already in pubspec), Python/boto3 (Lambda backend), AWS DynamoDB.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `aws_backend/lambda/api_members.py` | Read/write `isSaftschubse` |
| Modify | `lib/config_loader.dart` | `Member._isSaftschubse` field |
| Modify | `lib/screens/mitglieder_screen.dart` | Admin toggle for `isSaftschubse` |
| Create | `lib/api/getraenke_api.dart` | Firebase I/O + `TallyEntry` model |
| Create | `lib/screens/getraenke_screen.dart` | Screen + `BierdeckelCard` widget |
| Modify | `lib/screens/home_screen.dart` | Add "🍺 Getränke" tile |
| Modify | `test/unit/config_loader_test.dart` | Tests for `isSaftschubse` |
| Create | `test/unit/getraenke_api_test.dart` | Tests for `TallyEntry` + grouping |
| Create | `test/widget/getraenke_screen_test.dart` | Widget tests for `BierdeckelCard` |

---

### Task 1: Backend — add `isSaftschubse` to api_members.py

**Files:**
- Modify: `aws_backend/lambda/api_members.py`

- [ ] **Step 1: Add `isSaftschubse` to `get_member` response**

In `get_member()`, add the field to the non-all-details dict (around line 86):

```python
result = item if all_details else {
    'memberId': item['memberId'],
    'name': item['name'],
    'isAdmin': item.get('isAdmin', False),
    'isSpiess': item.get('isSpiess', False),
    'isSaftschubse': item.get('isSaftschubse', False),
    'isSuperAdmin': item.get('isSuperAdmin', False),
    'isActive': item.get('isActive', True),
    'token': item.get('token', ''),
}
```

- [ ] **Step 2: Add `isSaftschubse` to `add_member` write + response**

In `add_member()`, extend the `UpdateExpression` and `ExpressionAttributeValues`:

```python
UpdateExpression=(
    'SET #name = :name, isAdmin = :isAdmin, isSpiess = :isSpiess, '
    'isSaftschubse = :isSaftschubse, '
    'isActive = :isActive, #token = :token, street = :street, '
    'houseNumber = :houseNumber, postalCode = :postalCode, '
    'city = :city, phone1 = :phone1, phone2 = :phone2'
),
ExpressionAttributeNames={'#name': 'name', '#token': 'token'},
ExpressionAttributeValues={
    ':name': data['name'],
    ':isAdmin': data.get('isAdmin', False),
    ':isSpiess': data.get('isSpiess', False),
    ':isSaftschubse': data.get('isSaftschubse', False),
    ':isActive': data.get('isActive', True),
    ':token': data.get('token', ''),
    ':street': data.get('street', ''),
    ':houseNumber': data.get('houseNumber', ''),
    ':postalCode': data.get('postalCode', ''),
    ':city': data.get('city', ''),
    ':phone1': data.get('phone1', ''),
    ':phone2': data.get('phone2', ''),
},
```

Also add `'isSaftschubse': data.get('isSaftschubse', False)` to the `return` dict at the bottom of `add_member`.

- [ ] **Step 3: Deploy lambda**

```bash
cd aws_backend/lambda && ./update.sh
```

Expected: `"FunctionName": "vereins-app-beta-lambda_backend"` in output, no errors.

- [ ] **Step 4: Commit**

```bash
git add aws_backend/lambda/api_members.py
git commit -m "feat: add isSaftschubse field to member API"
```

---

### Task 2: Flutter Member model — add `isSaftschubse`

**Files:**
- Modify: `lib/config_loader.dart`
- Modify: `test/unit/config_loader_test.dart`

- [ ] **Step 1: Write failing tests**

Add to the `Member` group in `test/unit/config_loader_test.dart`:

```dart
test('isSaftschubse defaults to false when absent', () async {
  await withStubHttp(() async {
    final config = _makeConfig();
    config.member.updateMember({'name': 'Max'});
    expect(config.member.isSaftschubse, isFalse);
  });
});

test('isSaftschubse is set from JSON', () async {
  await withStubHttp(() async {
    final config = _makeConfig();
    config.member.updateMember({'name': 'Max', 'isSaftschubse': true});
    expect(config.member.isSaftschubse, isTrue);
  });
});

test('encodeMember includes isSaftschubse', () async {
  await withStubHttp(() async {
    final config = _makeConfig();
    config.member.updateMember({'name': 'Max', 'isSaftschubse': true});
    final decoded = jsonDecode(config.member.encodeMember()) as Map<String, dynamic>;
    expect(decoded['isSaftschubse'], isTrue);
  });
});
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
flutter test test/unit/config_loader_test.dart
```

Expected: 3 new tests FAIL with `NoSuchMethodError` or similar.

- [ ] **Step 3: Implement in `config_loader.dart`**

Add field declaration alongside the other booleans (around line 230):

```dart
bool _isSaftschubse = false;
```

Add getter and setter alongside the others:

```dart
bool get isSaftschubse => _isSaftschubse;
set isSaftschubse(bool value) => _isSaftschubse = value;
```

In `updateMember()`, add:

```dart
_isSaftschubse = member?['isSaftschubse'] ?? false;
```

In `encodeMember()`, add `'isSaftschubse': _isSaftschubse,` to the map.

- [ ] **Step 4: Run tests**

```bash
flutter test test/unit/config_loader_test.dart
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/config_loader.dart test/unit/config_loader_test.dart
git commit -m "feat: add isSaftschubse to Member model"
```

---

### Task 3: Mitglieder admin UI — isSaftschubse toggle

**Files:**
- Modify: `lib/screens/mitglieder_screen.dart`

- [ ] **Step 1: Add SwitchListTile after the Spieß toggle**

In `_buildMemberDetail()`, after the `isSpiess` SwitchListTile (around line 258):

```dart
SwitchListTile(
  title: Text('Saftschubse'),
  value: selectedMember!['isSaftschubse'] == true,
  onChanged: (val) => setState(() => selectedMember!['isSaftschubse'] = val),
),
```

- [ ] **Step 2: Verify app compiles**

```bash
flutter analyze
```

Expected: no new errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/mitglieder_screen.dart
git commit -m "feat: add isSaftschubse toggle to member admin UI"
```

---

### Task 4: TallyEntry model + GetraenkeApi

**Files:**
- Create: `lib/api/getraenke_api.dart`
- Create: `test/unit/getraenke_api_test.dart`

- [ ] **Step 1: Write failing unit tests**

Create `test/unit/getraenke_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/api/getraenke_api.dart';

void main() {
  group('TallyEntry.fromMap', () {
    test('parses strich entry', () {
      final entry = TallyEntry.fromMap('alt', {
        'memberId': 'mem-1',
        'type': 'strich',
        'timestamp': 1000,
      });
      expect(entry.drinkId, 'alt');
      expect(entry.memberId, 'mem-1');
      expect(entry.type, 'strich');
    });

    test('parses flasche entry', () {
      final entry = TallyEntry.fromMap('cola', {
        'memberId': 'mem-2',
        'type': 'flasche',
        'timestamp': 2000,
      });
      expect(entry.type, 'flasche');
    });
  });

  group('parseTallies', () {
    test('returns empty list when data is null', () {
      expect(parseTallies(null), isEmpty);
    });

    test('parses nested Firebase snapshot into flat list', () {
      final data = {
        'alt': {
          'entry1': {'memberId': 'mem-1', 'type': 'strich', 'timestamp': 1},
          'entry2': {'memberId': 'mem-2', 'type': 'strich', 'timestamp': 2},
        },
        'cola': {
          'entry3': {'memberId': 'mem-1', 'type': 'flasche', 'timestamp': 3},
        },
      };
      final entries = parseTallies(data);
      expect(entries.length, 3);
      expect(entries.where((e) => e.drinkId == 'alt').length, 2);
      expect(entries.where((e) => e.drinkId == 'cola').length, 1);
    });

    test('returns empty list when top-level value is empty map', () {
      expect(parseTallies({}), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
flutter test test/unit/getraenke_api_test.dart
```

Expected: compilation error — `GetraenkeApi` not found.

- [ ] **Step 3: Implement `lib/api/getraenke_api.dart`**

```dart
import 'package:firebase_database/firebase_database.dart';
import '../config_loader.dart';

class TallyEntry {
  final String drinkId;
  final String memberId;
  final String type; // 'strich' | 'flasche'

  TallyEntry({
    required this.drinkId,
    required this.memberId,
    required this.type,
  });

  factory TallyEntry.fromMap(String drinkId, Map<dynamic, dynamic> map) {
    return TallyEntry(
      drinkId: drinkId,
      memberId: map['memberId'] as String,
      type: map['type'] as String,
    );
  }
}

List<TallyEntry> parseTallies(Object? data) {
  if (data == null) return [];
  final drinksMap = Map<dynamic, dynamic>.from(data as Map);
  final entries = <TallyEntry>[];
  for (final drinkEntry in drinksMap.entries) {
    final drinkId = drinkEntry.key as String;
    final marksMap = Map<dynamic, dynamic>.from(drinkEntry.value as Map);
    for (final mark in marksMap.values) {
      entries.add(TallyEntry.fromMap(drinkId, Map<dynamic, dynamic>.from(mark as Map)));
    }
  }
  return entries;
}

class GetraenkeApi {
  final AppConfig config;

  GetraenkeApi(this.config);

  DatabaseReference get _ref =>
      FirebaseDatabase.instance.ref('tallies/${config.applicationId}');

  Stream<List<TallyEntry>> watchTallies() {
    return _ref.onValue.map((event) => parseTallies(event.snapshot.value));
  }

  Future<void> addMark(String drinkId, String type) async {
    await _ref.child(drinkId).push().set({
      'memberId': config.memberId,
      'type': type,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> clearAll() async {
    await _ref.remove();
  }
}
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/unit/getraenke_api_test.dart
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/api/getraenke_api.dart test/unit/getraenke_api_test.dart
git commit -m "feat: add GetraenkeApi and TallyEntry model"
```

---

### Task 5: BierdeckelCard widget + widget tests

**Files:**
- Create: `lib/screens/getraenke_screen.dart` (BierdeckelCard only for now)
- Create: `test/widget/getraenke_screen_test.dart`

- [ ] **Step 1: Write failing widget tests**

Create `test/widget/getraenke_screen_test.dart`:

```dart
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
      // No sticks rendered
      final redContainers = tester.widgetList<Container>(find.byType(Container)).where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          return decoration.color == const Color(0xFFE53935) ||
              decoration.color == const Color(0xFF2C2C2C);
        }
        return false;
      });
      expect(redContainers, isEmpty);
    });

    testWidgets('flasche entry shown as emoji in tally row', (tester) async {
      await tester.pumpWidget(_wrap(BierdeckelCard(
        drink: kDrinks.firstWhere((d) => d.id == 'cola'),
        entries: [_flasche('cola', 'mem-1')],
        myMemberId: 'mem-1',
        onStrich: () {},
        onFlasche: () {},
      )));
      // The tally row contains a 🍾 text widget for the flasche entry
      // (distinct from the button 🍾 which is in a different widget subtree)
      expect(find.text('🍾'), findsWidgets);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
flutter test test/widget/getraenke_screen_test.dart
```

Expected: compilation error — `BierdeckelCard`, `kDrinks` not found.

- [ ] **Step 3: Implement `BierdeckelCard` and drink definitions in `getraenke_screen.dart`**

Create `lib/screens/getraenke_screen.dart` with BierdeckelCard and drink data:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/getraenke_api.dart';
import '../config_loader.dart';
import 'default_screen.dart';

class DrinkDef {
  final String id;
  final String name;
  final String headerEmoji;
  final String buttonEmoji;
  final bool hasBottle;

  const DrinkDef({
    required this.id,
    required this.name,
    required this.headerEmoji,
    required this.buttonEmoji,
    required this.hasBottle,
  });
}

const kDrinks = [
  DrinkDef(id: 'alt',       name: 'Alt',       headerEmoji: '🍺', buttonEmoji: '🍺', hasBottle: false),
  DrinkDef(id: 'pils',      name: 'Pils',      headerEmoji: '🍻', buttonEmoji: '🍺', hasBottle: false),
  DrinkDef(id: 'cola',      name: 'Cola',      headerEmoji: '🥤', buttonEmoji: '🥤', hasBottle: true),
  DrinkDef(id: 'fanta',     name: 'Fanta',     headerEmoji: '🥤', buttonEmoji: '🥤', hasBottle: true),
  DrinkDef(id: 'sprite',    name: 'Sprite',    headerEmoji: '🥤', buttonEmoji: '🥤', hasBottle: true),
  DrinkDef(id: 'cola_zero', name: 'Cola Zero', headerEmoji: '🥤', buttonEmoji: '🥤', hasBottle: true),
  DrinkDef(id: 'wasser',    name: 'Wasser',    headerEmoji: '💧', buttonEmoji: '🫗', hasBottle: true),
];

// ── BierdeckelCard ────────────────────────────────────────────────────────────

class BierdeckelCard extends StatelessWidget {
  final DrinkDef drink;
  final List<TallyEntry> entries;
  final String myMemberId;
  final VoidCallback onStrich;
  final VoidCallback? onFlasche;

  const BierdeckelCard({
    super.key,
    required this.drink,
    required this.entries,
    required this.myMemberId,
    required this.onStrich,
    required this.onFlasche,
  });

  @override
  Widget build(BuildContext context) {
    final myStriche    = entries.where((e) => e.memberId == myMemberId && e.type == 'strich').length;
    final othersStriche = entries.where((e) => e.memberId != myMemberId && e.type == 'strich').length;
    final myFlaschen   = entries.where((e) => e.memberId == myMemberId && e.type == 'flasche').length;
    final othersFlaschen = entries.where((e) => e.memberId != myMemberId && e.type == 'flasche').length;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFDF8EE), Color(0xFFF0E8D0)],
        ),
        border: Border.all(color: const Color(0xFFC8A96E), width: 2),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(2, 3))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: emoji + name + tally marks inline
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(drink.headerEmoji, style: const TextStyle(fontSize: 20)),
              Text(
                drink.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF4A2C00)),
              ),
              _TallyRow(
                myStriche: myStriche,
                othersStriche: othersStriche,
                myFlaschen: myFlaschen,
                othersFlaschen: othersFlaschen,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Buttons
          Row(
            children: [
              Expanded(child: _TallyButton(emoji: drink.buttonEmoji, filled: true, onTap: onStrich)),
              if (drink.hasBottle && onFlasche != null) ...[
                const SizedBox(width: 8),
                Expanded(child: _TallyButton(emoji: '🍾', filled: false, onTap: onFlasche!)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TallyRow extends StatelessWidget {
  final int myStriche;
  final int othersStriche;
  final int myFlaschen;
  final int othersFlaschen;

  const _TallyRow({
    required this.myStriche,
    required this.othersStriche,
    required this.myFlaschen,
    required this.othersFlaschen,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ..._strichWidgets(myStriche, const Color(0xFFE53935)),
        ..._flascheWidgets(myFlaschen, const Color(0xFFE53935)),
        ..._strichWidgets(othersStriche, const Color(0xFF2C2C2C)),
        ..._flascheWidgets(othersFlaschen, const Color(0xFF2C2C2C)),
      ],
    );
  }

  List<Widget> _strichWidgets(int count, Color color) {
    final widgets = <Widget>[];
    final groups = count ~/ 5;
    final remainder = count % 5;
    for (int i = 0; i < groups; i++) {
      widgets.add(_TallyGroup(color: color));
      widgets.add(const SizedBox(width: 6));
    }
    for (int i = 0; i < remainder; i++) {
      widgets.add(_Stick(color: color));
    }
    return widgets;
  }

  List<Widget> _flascheWidgets(int count, Color color) {
    return List.generate(
      count,
      (_) => Text('🍾', style: const TextStyle(fontSize: 14)),
    );
  }
}

class _TallyGroup extends StatelessWidget {
  final Color color;
  const _TallyGroup({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(4, (_) => Padding(
              padding: const EdgeInsets.only(right: 2),
              child: _Stick(color: color),
            )),
          ),
          Positioned(
            top: 3,
            left: -4,
            child: Transform.rotate(
              angle: -0.31,
              child: Container(
                width: 38,
                height: 5,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stick extends StatelessWidget {
  final Color color;
  const _Stick({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _TallyButton extends StatelessWidget {
  final String emoji;
  final bool filled;
  final VoidCallback onTap;

  const _TallyButton({required this.emoji, required this.filled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: filled ? const Color(0xFF7A4F00) : Colors.white,
          border: Border.all(color: const Color(0xFF7A4F00), width: 2),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(1, 2))],
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/widget/getraenke_screen_test.dart
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/getraenke_screen.dart test/widget/getraenke_screen_test.dart
git commit -m "feat: add BierdeckelCard widget and drink definitions"
```

---

### Task 6: GetraenkeScreen — full screen wiring

**Files:**
- Modify: `lib/screens/getraenke_screen.dart` (append screen class)

- [ ] **Step 1: Append `GetraenkeScreen` class to `getraenke_screen.dart`**

Add at the bottom of the file:

```dart
// ── GetraenkeScreen ───────────────────────────────────────────────────────────

class GetraenkeScreen extends DefaultScreen {
  const GetraenkeScreen({super.key, required super.config})
      : super(title: 'Getränke');

  @override
  DefaultScreenState createState() => _GetraenkeScreenState();
}

class _GetraenkeScreenState extends DefaultScreenState<GetraenkeScreen> {
  late final GetraenkeApi _api;
  List<TallyEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _api = GetraenkeApi(widget.config);
    _api.watchTallies().listen(
      (entries) { if (mounted) setState(() => _entries = entries); },
      onError: (e) { if (mounted) showError('Firebase-Fehler: $e'); },
    );
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alle Striche löschen?'),
        content: const Text('Alle Striche und Flaschen für alle Getränke werden gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _api.clearAll();
      } catch (e) {
        if (mounted) showError('Fehler beim Löschen: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('🍺 Getränke')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (member.isSaftschubse) ...[
            ElevatedButton.icon(
              onPressed: _confirmReset,
              icon: const Icon(Icons.delete_sweep, color: Colors.white),
              label: const Text('Alle Striche löschen', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
            const SizedBox(height: 12),
          ],
          ...kDrinks.map((drink) {
            final drinkEntries = _entries.where((e) => e.drinkId == drink.id).toList();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: BierdeckelCard(
                drink: drink,
                entries: drinkEntries,
                myMemberId: widget.config.memberId,
                onStrich: () => _api.addMark(drink.id, 'strich').catchError(
                  (e) { if (mounted) showError('Fehler: $e'); },
                ),
                onFlasche: drink.hasBottle
                    ? () => _api.addMark(drink.id, 'flasche').catchError(
                          (e) { if (mounted) showError('Fehler: $e'); },
                        )
                    : null,
              ),
            );
          }),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify app compiles**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/getraenke_screen.dart
git commit -m "feat: add GetraenkeScreen with live Firebase tally updates"
```

---

### Task 7: Home screen tile + Firebase setup

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: Add import at top of `home_screen.dart`**

```dart
import 'getraenke_screen.dart';
```

- [ ] **Step 2: Add tile in `_buildGridMenu` after the Schere-Stein-Papier tile (around line 460)**

```dart
if (_isScreenActive('getraenke'))
  _buildMenuTile(
    context,
    '🍺 Getränke',
    () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GetraenkeScreen(config: widget.config),
      ),
    ),
  ),
```

- [ ] **Step 3: Enable Firebase Realtime Database in the Firebase Console**

> Manual step — must be done once per Firebase project:
> 1. Open [Firebase Console](https://console.firebase.google.com/) → select the project
> 2. Left sidebar → **Realtime Database** → **Create database**
> 3. Choose region: **europe-west1** (Frankfurt)
> 4. Start in **test mode** (open rules), then apply rules from Step 4

- [ ] **Step 4: Set Firebase Security Rules**

In the Firebase Console → Realtime Database → Rules tab, set:

```json
{
  "rules": {
    "tallies": {
      "$applicationId": {
        ".read": true,
        ".write": true
      }
    }
  }
}
```

> This allows any client to read/write their applicationId's tallies. The Lambda authorizer already protects the REST API; these rules are intentionally open for this internal tool.

- [ ] **Step 5: Enable Realtime Database in `firebase_options.dart`**

Check that the `databaseURL` is set in `FirebaseOptions` for web. Open `lib/firebase_options.dart` and verify the `web` options block includes:

```dart
databaseURL: 'https://<your-project-id>-default-rtdb.europe-west1.firebasedatabase.app',
```

If the `databaseURL` field is missing, add it. The URL is shown in the Firebase Console → Realtime Database overview.

- [ ] **Step 6: Add getraenke to active_screens in the Firebase/DynamoDB customer config**

In the Verein admin screen (or directly in DynamoDB), add `"getraenke"` to the `active_screens` array for the club. Alternatively, test with `_activeScreens == null` (backwards-compatible: shows all screens when the field is absent).

- [ ] **Step 7: Verify app compiles and run all tests**

```bash
flutter analyze && flutter test
```

Expected: no errors, all tests PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: add Getraenke tile to home screen"
```

---

## Self-Review

**Spec coverage check:**
- ✅ All 7 drinks with correct emojis and bottle availability
- ✅ Live updates via Firebase `.onValue` stream
- ✅ Own marks in red, others in black
- ✅ Bierdeckel card design with 5-groups + diagonal
- ✅ Bottle marks as 🍾 inline in tally row
- ✅ isSaftschubse reset button with confirmation dialog
- ✅ isSaftschubse new field (backend + model + admin UI)
- ✅ Home screen tile controlled via `active_screens`
- ✅ Empty tally area is blank (no placeholder text)
- ✅ Firebase Security Rules documented

**Type consistency:**
- `TallyEntry` defined in Task 4, used in Task 5 and 6 — consistent
- `GetraenkeApi.addMark(drinkId, type)` defined in Task 4, called in Task 6 — consistent
- `GetraenkeApi.clearAll()` defined in Task 4, called in Task 6 — consistent
- `kDrinks` defined in Task 5, used in Task 6 — consistent
- `BierdeckelCard` takes `DrinkDef drink` — defined and used consistently
- `parseTallies` is a top-level function (not a method), called in tests and used inside `watchTallies` — consistent

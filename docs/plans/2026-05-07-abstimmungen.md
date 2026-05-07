# Abstimmungen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a scrollable voting screen where members see all active/visible polls as cards, can cast/change their vote, and see live results — with admin create/edit and super-admin delete.

**Architecture:** Firebase Realtime Database stores polls and votes under `polls/{applicationId}/{pollId}`. A `StreamBuilder` listens to the poll collection for real-time updates. Each poll card handles its own vote subcollection listener.

**Tech Stack:** Flutter, Firebase Realtime Database (`firebase_database`), `provider` for Member access, custom bar-chart widget (no additional library).

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/models/poll.dart` | Create | `Poll`, `PollOption`, `PollVote` data classes + Firebase parsing |
| `lib/api/polls_api.dart` | Create | Firebase CRUD + stream for polls and votes |
| `lib/widgets/poll_card.dart` | Create | Single poll card: voting UI + results bar chart |
| `lib/widgets/poll_form_dialog.dart` | Create | Create / edit poll bottom sheet (admin only) |
| `lib/screens/abstimmungen_screen.dart` | Create | Main screen: `ListView` of `PollCard`s |
| `lib/screens/home_screen.dart` | Modify | Add `📊 Abstimmungen` menu tile |
| `test/unit/poll_model_test.dart` | Create | Unit tests for model parsing from Firebase snapshots |
| `test/widget/abstimmungen_screen_test.dart` | Create | Widget tests for the screen |

---

## Firebase Data Shape

```
polls/{applicationId}/{pollId}:
  title:          String
  description:    String        (empty string if none)
  allowMultiple:  bool
  isActive:       bool
  isVisible:      bool
  isSecretBallot: bool
  authorId:       String        (memberId of creator)
  createdAt:      int           (milliseconds since epoch)
  options:
    {optionId}:
      text:       String
  votes:
    {memberId}:
      selections:
        {optionId}: true        (presence = selected)
      updatedAt:  int
```

---

## Task 1: Poll Data Model

**Files:**
- Create: `lib/models/poll.dart`
- Create: `test/unit/poll_model_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// test/unit/poll_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/models/poll.dart';

void main() {
  group('PollOption.fromMap', () {
    test('parses text', () {
      final opt = PollOption.fromMap('opt1', {'text': 'Option A'});
      expect(opt.id, 'opt1');
      expect(opt.text, 'Option A');
    });
  });

  group('PollVote.fromMap', () {
    test('parses selections map', () {
      final vote = PollVote.fromMap('member-1', {
        'selections': {'opt1': true, 'opt2': true},
        'updatedAt': 1000,
      });
      expect(vote.memberId, 'member-1');
      expect(vote.selectedOptionIds, containsAll(['opt1', 'opt2']));
      expect(vote.updatedAt, 1000);
    });

    test('handles missing selections', () {
      final vote = PollVote.fromMap('member-1', {'updatedAt': 0});
      expect(vote.selectedOptionIds, isEmpty);
    });
  });

  group('Poll.fromSnapshot', () {
    test('parses full poll', () {
      final poll = Poll.fromSnapshot('poll-1', {
        'title': 'Test Abstimmung',
        'description': 'Beschreibung',
        'allowMultiple': true,
        'isActive': true,
        'isVisible': true,
        'isSecretBallot': false,
        'authorId': 'author-1',
        'createdAt': 2000,
        'options': {
          'opt1': {'text': 'Ja'},
          'opt2': {'text': 'Nein'},
        },
        'votes': {
          'member-1': {
            'selections': {'opt1': true},
            'updatedAt': 3000,
          },
        },
      });
      expect(poll.id, 'poll-1');
      expect(poll.title, 'Test Abstimmung');
      expect(poll.allowMultiple, true);
      expect(poll.options.length, 2);
      expect(poll.votes.length, 1);
      expect(poll.votes['member-1']!.selectedOptionIds, contains('opt1'));
    });

    test('parses poll with no options or votes', () {
      final poll = Poll.fromSnapshot('p', {
        'title': 'Minimal',
        'description': '',
        'allowMultiple': false,
        'isActive': false,
        'isVisible': true,
        'isSecretBallot': false,
        'authorId': 'a',
        'createdAt': 0,
      });
      expect(poll.options, isEmpty);
      expect(poll.votes, isEmpty);
    });
  });

  group('Poll helpers', () {
    Poll buildPoll({bool isSecretBallot = false, bool isActive = true}) {
      return Poll(
        id: 'p1',
        title: 'T',
        description: '',
        options: [
          PollOption(id: 'o1', text: 'A'),
          PollOption(id: 'o2', text: 'B'),
        ],
        allowMultiple: false,
        isActive: isActive,
        isVisible: true,
        isSecretBallot: isSecretBallot,
        authorId: 'auth',
        createdAt: 0,
        votes: {
          'm1': PollVote(memberId: 'm1', selectedOptionIds: ['o1'], updatedAt: 0),
          'm2': PollVote(memberId: 'm2', selectedOptionIds: ['o2'], updatedAt: 0),
        },
      );
    }

    test('countForOption returns correct count', () {
      final poll = buildPoll();
      expect(poll.countForOption('o1'), 1);
      expect(poll.countForOption('o2'), 1);
      expect(poll.countForOption('o3'), 0);
    });

    test('showResults: non-secret always shows', () {
      expect(buildPoll(isSecretBallot: false, isActive: true).showResults, true);
    });

    test('showResults: secret ballot hides while active', () {
      expect(buildPoll(isSecretBallot: true, isActive: true).showResults, false);
    });

    test('showResults: secret ballot shows when inactive', () {
      expect(buildPoll(isSecretBallot: true, isActive: false).showResults, true);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/unit/poll_model_test.dart
```

Expected: FAIL with "Target of URI doesn't exist: 'package:vereinsappell/models/poll.dart'"

- [ ] **Step 3: Implement the model**

```dart
// lib/models/poll.dart
class PollOption {
  final String id;
  final String text;

  PollOption({required this.id, required this.text});

  factory PollOption.fromMap(String id, Map<dynamic, dynamic> map) {
    return PollOption(id: id, text: map['text'] as String? ?? '');
  }

  Map<String, dynamic> toMap() => {'text': text};
}

class PollVote {
  final String memberId;
  final List<String> selectedOptionIds;
  final int updatedAt;

  PollVote({
    required this.memberId,
    required this.selectedOptionIds,
    required this.updatedAt,
  });

  factory PollVote.fromMap(String memberId, Map<dynamic, dynamic> map) {
    final sel = map['selections'];
    final ids = sel is Map
        ? (sel as Map<dynamic, dynamic>).keys.map((k) => k as String).toList()
        : <String>[];
    return PollVote(
      memberId: memberId,
      selectedOptionIds: ids,
      updatedAt: map['updatedAt'] as int? ?? 0,
    );
  }
}

class Poll {
  final String id;
  final String title;
  final String description;
  final List<PollOption> options;
  final bool allowMultiple;
  final bool isActive;
  final bool isVisible;
  final bool isSecretBallot;
  final String authorId;
  final int createdAt;
  final Map<String, PollVote> votes;

  Poll({
    required this.id,
    required this.title,
    required this.description,
    required this.options,
    required this.allowMultiple,
    required this.isActive,
    required this.isVisible,
    required this.isSecretBallot,
    required this.authorId,
    required this.createdAt,
    required this.votes,
  });

  factory Poll.fromSnapshot(String id, Map<dynamic, dynamic> map) {
    final rawOptions = map['options'];
    final options = rawOptions is Map
        ? (rawOptions as Map<dynamic, dynamic>)
            .entries
            .map((e) => PollOption.fromMap(e.key as String,
                Map<dynamic, dynamic>.from(e.value as Map)))
            .toList()
        : <PollOption>[];

    final rawVotes = map['votes'];
    final votes = rawVotes is Map
        ? {
            for (final e in (rawVotes as Map<dynamic, dynamic>).entries)
              e.key as String: PollVote.fromMap(
                e.key as String,
                Map<dynamic, dynamic>.from(e.value as Map),
              )
          }
        : <String, PollVote>{};

    return Poll(
      id: id,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      allowMultiple: map['allowMultiple'] as bool? ?? false,
      isActive: map['isActive'] as bool? ?? false,
      isVisible: map['isVisible'] as bool? ?? true,
      isSecretBallot: map['isSecretBallot'] as bool? ?? false,
      authorId: map['authorId'] as String? ?? '',
      createdAt: map['createdAt'] as int? ?? 0,
      options: options,
      votes: votes,
    );
  }

  int countForOption(String optionId) =>
      votes.values.where((v) => v.selectedOptionIds.contains(optionId)).length;

  bool get showResults => !isSecretBallot || !isActive;
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/unit/poll_model_test.dart
```

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/poll.dart test/unit/poll_model_test.dart
git commit -m "feat: add Poll data model with Firebase parsing"
```

---

## Task 2: Firebase Polls API

**Files:**
- Create: `lib/api/polls_api.dart`

Note: The Firebase Realtime Database API is not easily unit-tested without a live connection. The API is kept thin — all business logic lives in the model — and widget tests will mock this class via dependency injection.

- [ ] **Step 1: Create the API class**

```dart
// lib/api/polls_api.dart
import 'package:firebase_database/firebase_database.dart';
import '../config_loader.dart';
import '../models/poll.dart';

export '../models/poll.dart';

class PollsApi {
  final AppConfig config;

  PollsApi(this.config);

  DatabaseReference get _ref =>
      FirebaseDatabase.instance.ref('polls/${config.applicationId}');

  Stream<List<Poll>> watchPolls() {
    return _ref.onValue.map((event) => _parsePolls(event.snapshot.value));
  }

  List<Poll> _parsePolls(Object? data) {
    if (data == null || data is! Map) return [];
    return (data as Map<dynamic, dynamic>)
        .entries
        .where((e) => e.value is Map)
        .map((e) => Poll.fromSnapshot(
              e.key as String,
              Map<dynamic, dynamic>.from(e.value as Map),
            ))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> createPoll({
    required String title,
    required String description,
    required List<String> optionTexts,
    required bool allowMultiple,
    required bool isActive,
    required bool isVisible,
    required bool isSecretBallot,
    required String authorId,
  }) async {
    final pollRef = _ref.push();
    final optionEntries = {
      for (var i = 0; i < optionTexts.length; i++)
        'opt$i': {'text': optionTexts[i]}
    };
    await pollRef.set({
      'title': title,
      'description': description,
      'allowMultiple': allowMultiple,
      'isActive': isActive,
      'isVisible': isVisible,
      'isSecretBallot': isSecretBallot,
      'authorId': authorId,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'options': optionEntries,
    });
  }

  Future<void> updatePoll(
    String pollId, {
    required String title,
    required String description,
    required List<PollOption> options,
    required bool allowMultiple,
    required bool isActive,
    required bool isVisible,
    required bool isSecretBallot,
  }) async {
    final optionEntries = {
      for (final opt in options) opt.id: opt.toMap()
    };
    await _ref.child(pollId).update({
      'title': title,
      'description': description,
      'allowMultiple': allowMultiple,
      'isActive': isActive,
      'isVisible': isVisible,
      'isSecretBallot': isSecretBallot,
      'options': optionEntries,
    });
  }

  Future<void> vote(
    String pollId,
    String memberId,
    List<String> selectedOptionIds,
  ) async {
    final selections = {for (final id in selectedOptionIds) id: true};
    await _ref.child(pollId).child('votes').child(memberId).set({
      'selections': selections,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deletePoll(String pollId) async {
    await _ref.child(pollId).remove();
  }
}
```

- [ ] **Step 2: Verify the app still compiles**

```bash
flutter analyze lib/api/polls_api.dart
```

Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/api/polls_api.dart
git commit -m "feat: add PollsApi for Firebase Realtime Database"
```

---

## Task 3: Poll Results Bar Chart Widget

**Files:**
- Create: `lib/widgets/poll_results.dart`

This widget renders a horizontal bar per option with label, colored bar, and absolute vote count. It is a pure display widget — no Firebase dependency.

- [ ] **Step 1: Write failing widget test**

```dart
// test/widget/poll_results_test.dart
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
```

- [ ] **Step 2: Run to verify fail**

```bash
flutter test test/widget/poll_results_test.dart
```

Expected: FAIL — "Target of URI doesn't exist"

- [ ] **Step 3: Implement the widget**

```dart
// lib/widgets/poll_results.dart
import 'package:flutter/material.dart';
import '../models/poll.dart';

class PollResults extends StatelessWidget {
  final Poll poll;
  final int? totalMembers;

  const PollResults({super.key, required this.poll, this.totalMembers});

  @override
  Widget build(BuildContext context) {
    final voterCount = poll.votes.length;
    final total = totalMembers ?? voterCount;
    final maxVotes = poll.options
        .map((o) => poll.countForOption(o.id))
        .fold(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '$voterCount von $total haben abgestimmt',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        for (final option in poll.options) ...[
          Text(option.text, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 3),
          _Bar(
            count: poll.countForOption(option.id),
            maxVotes: maxVotes,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final int count;
  final int maxVotes;

  const _Bar({required this.count, required this.maxVotes});

  @override
  Widget build(BuildContext context) {
    final fraction = maxVotes == 0 ? 0.0 : count / maxVotes;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 12,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation(Colors.green[400]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 24,
          child: Text(
            '$count',
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/widget/poll_results_test.dart
```

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/poll_results.dart test/widget/poll_results_test.dart
git commit -m "feat: add PollResults bar chart widget"
```

---

## Task 4: Poll Form Dialog

**Files:**
- Create: `lib/widgets/poll_form_dialog.dart`

Admin-only bottom sheet for creating and editing polls. No Firebase calls here — the caller provides callbacks.

- [ ] **Step 1: Write failing widget test**

```dart
// test/widget/poll_form_dialog_test.dart
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
    await tester.tap(saveButton);
    await tester.pump();
    // Form validation prevents save — no callback called
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
```

- [ ] **Step 2: Run to verify fail**

```bash
flutter test test/widget/poll_form_dialog_test.dart
```

Expected: FAIL — "Target of URI doesn't exist"

- [ ] **Step 3: Implement the dialog**

```dart
// lib/widgets/poll_form_dialog.dart
import 'package:flutter/material.dart';
import '../models/poll.dart';

class PollFormData {
  final String title;
  final String description;
  final List<String> optionTexts;
  final bool allowMultiple;
  final bool isActive;
  final bool isVisible;
  final bool isSecretBallot;

  PollFormData({
    required this.title,
    required this.description,
    required this.optionTexts,
    required this.allowMultiple,
    required this.isActive,
    required this.isVisible,
    required this.isSecretBallot,
  });
}

Future<void> showPollFormDialog(
  BuildContext context, {
  Poll? poll,
  required void Function(PollFormData) onSave,
  VoidCallback? onDelete,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _PollFormSheet(poll: poll, onSave: onSave, onDelete: onDelete),
  );
}

class _PollFormSheet extends StatefulWidget {
  final Poll? poll;
  final void Function(PollFormData) onSave;
  final VoidCallback? onDelete;

  const _PollFormSheet({this.poll, required this.onSave, this.onDelete});

  @override
  State<_PollFormSheet> createState() => _PollFormSheetState();
}

class _PollFormSheetState extends State<_PollFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late List<TextEditingController> _optionCtrls;
  late bool _allowMultiple;
  late bool _isActive;
  late bool _isVisible;
  late bool _isSecretBallot;

  @override
  void initState() {
    super.initState();
    final p = widget.poll;
    _titleCtrl = TextEditingController(text: p?.title ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _optionCtrls = p != null && p.options.isNotEmpty
        ? p.options.map((o) => TextEditingController(text: o.text)).toList()
        : [TextEditingController(), TextEditingController()];
    _allowMultiple = p?.allowMultiple ?? false;
    _isActive = p?.isActive ?? true;
    _isVisible = p?.isVisible ?? true;
    _isSecretBallot = p?.isSecretBallot ?? false;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_optionCtrls.length <= 2) return;
    setState(() {
      _optionCtrls[i].dispose();
      _optionCtrls.removeAt(i);
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final texts = _optionCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (texts.length < 2) return;
    widget.onSave(PollFormData(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      optionTexts: texts,
      allowMultiple: _allowMultiple,
      isActive: _isActive,
      isVisible: _isVisible,
      isSecretBallot: _isSecretBallot,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.poll != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? 'Abstimmung bearbeiten' : 'Neue Abstimmung',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Titel *', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Titel erforderlich' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Beschreibung (optional)', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              const Text('Antwortmöglichkeiten', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (var i = 0; i < _optionCtrls.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _optionCtrls[i],
                          decoration: InputDecoration(
                            labelText: 'Option ${i + 1}',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Erforderlich' : null,
                        ),
                      ),
                      if (_optionCtrls.length > 2)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _removeOption(i),
                        ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add),
                label: const Text('Option hinzufügen'),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('Mehrfachauswahl erlauben'),
                value: _allowMultiple,
                onChanged: (v) => setState(() => _allowMultiple = v),
              ),
              SwitchListTile(
                title: const Text('Geheime Wahl'),
                value: _isSecretBallot,
                onChanged: (v) => setState(() => _isSecretBallot = v),
              ),
              SwitchListTile(
                title: const Text('Aktiv'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              SwitchListTile(
                title: const Text('Sichtbar'),
                value: _isVisible,
                onChanged: (v) => setState(() => _isVisible = v),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _submit,
                child: Text(isEdit ? 'Speichern' : 'Erstellen'),
              ),
              if (widget.onDelete != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: widget.onDelete,
                  child: const Text('Abstimmung löschen', style: TextStyle(color: Colors.red)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/widget/poll_form_dialog_test.dart
```

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/poll_form_dialog.dart test/widget/poll_form_dialog_test.dart
git commit -m "feat: add PollFormDialog for creating and editing polls"
```

---

## Task 5: Poll Card Widget

**Files:**
- Create: `lib/widgets/poll_card.dart`

Renders a single poll with header, voting options, and results. Depends on `PollResults` and `PollFormDialog`.

- [ ] **Step 1: Write failing widget tests**

```dart
// test/widget/poll_card_test.dart
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
    expect(find.text('Option A'), findsOneWidget);
    expect(find.text('Option B'), findsOneWidget);
    expect(find.text('Stimme abgeben'), findsOneWidget);
  });

  testWidgets('zeigt "Stimme ändern" wenn bereits abgestimmt', (tester) async {
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
    expect(find.text('Stimme ändern'), findsOneWidget);
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
```

- [ ] **Step 2: Run to verify fail**

```bash
flutter test test/widget/poll_card_test.dart
```

Expected: FAIL — "Target of URI doesn't exist"

- [ ] **Step 3: Implement PollCard**

```dart
// lib/widgets/poll_card.dart
import 'package:flutter/material.dart';
import '../models/poll.dart';
import 'poll_results.dart';

class PollCard extends StatefulWidget {
  final Poll poll;
  final String currentMemberId;
  final bool isAdmin;
  final bool isSuperAdmin;
  final Future<void> Function(String pollId, List<String> selectedIds) onVote;
  final VoidCallback? onEdit;
  final int? totalMembers;

  const PollCard({
    super.key,
    required this.poll,
    required this.currentMemberId,
    required this.isAdmin,
    required this.isSuperAdmin,
    required this.onVote,
    this.onEdit,
    this.totalMembers,
  });

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  late Set<String> _pendingSelection;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _pendingSelection = Set.from(
      widget.poll.votes[widget.currentMemberId]?.selectedOptionIds ?? [],
    );
  }

  @override
  void didUpdateWidget(PollCard old) {
    super.didUpdateWidget(old);
    if (old.poll.id != widget.poll.id) {
      _pendingSelection = Set.from(
        widget.poll.votes[widget.currentMemberId]?.selectedOptionIds ?? [],
      );
    }
  }

  void _toggleOption(String optionId) {
    if (!widget.poll.isActive) return;
    setState(() {
      if (widget.poll.allowMultiple) {
        if (_pendingSelection.contains(optionId)) {
          _pendingSelection.remove(optionId);
        } else {
          _pendingSelection.add(optionId);
        }
      } else {
        _pendingSelection = {optionId};
      }
    });
  }

  Future<void> _submit() async {
    if (_pendingSelection.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onVote(widget.poll.id, _pendingSelection.toList());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool get _hasVoted =>
      widget.poll.votes.containsKey(widget.currentMemberId);

  Color get _borderColor {
    if (!widget.poll.isActive) return Colors.grey[300]!;
    if (widget.poll.isSecretBallot) return Colors.blue[300]!;
    return Colors.green[400]!;
  }

  @override
  Widget build(BuildContext context) {
    final poll = widget.poll;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: _borderColor, width: poll.isActive ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            if (poll.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(poll.description,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            if (poll.isActive) ...[
              const SizedBox(height: 12),
              _buildOptions(),
              const SizedBox(height: 8),
              _buildSubmitButton(),
            ],
            if (poll.showResults) ...[
              const Divider(height: 20),
              PollResults(poll: poll, totalMembers: widget.totalMembers),
            ],
            if (poll.isSecretBallot && poll.isActive) ...[
              const SizedBox(height: 8),
              const Text('🔒 Ergebnisse erst nach Ende sichtbar',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            widget.poll.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),
        if (widget.isAdmin && widget.onEdit != null)
          GestureDetector(
            onTap: widget.onEdit,
            child: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
          ),
        const SizedBox(width: 4),
        Text(
          widget.poll.isActive ? '● Aktiv' : '⏹ Beendet',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: widget.poll.isActive ? Colors.green : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildOptions() {
    return Column(
      children: [
        for (final option in widget.poll.options)
          _OptionTile(
            option: option,
            selected: _pendingSelection.contains(option.id),
            onTap: () => _toggleOption(option.id),
            accentColor: widget.poll.isSecretBallot ? Colors.blue : Colors.green,
          ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    final canSubmit = _pendingSelection.isNotEmpty && !_submitting;
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton(
        onPressed: canSubmit ? _submit : null,
        child: _submitting
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(_hasVoted ? 'Stimme ändern' : 'Stimme abgeben'),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final PollOption option;
  final bool selected;
  final VoidCallback onTap;
  final Color accentColor;

  const _OptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? accentColor : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
          color: selected ? accentColor.withAlpha(25) : null,
        ),
        child: Row(
          children: [
            if (selected)
              Icon(Icons.check, size: 16, color: accentColor),
            if (selected) const SizedBox(width: 6),
            Text(option.text, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/widget/poll_card_test.dart
```

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/poll_card.dart test/widget/poll_card_test.dart
git commit -m "feat: add PollCard widget with voting UI and results"
```

---

## Task 6: Abstimmungen Screen

**Files:**
- Create: `lib/screens/abstimmungen_screen.dart`
- Create: `test/widget/abstimmungen_screen_test.dart`

Main screen — `StreamBuilder` over `PollsApi.watchPolls()`, renders `PollCard` per poll, admin `+` icon in AppBar.

- [ ] **Step 1: Write failing widget tests**

```dart
// test/widget/abstimmungen_screen_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/models/poll.dart';
import 'package:vereinsappell/screens/abstimmungen_screen.dart';

import 'test_helpers.dart';

class FakePollsApi {
  final StreamController<List<Poll>> _controller = StreamController.broadcast();

  Stream<List<Poll>> watchPolls() => _controller.stream;

  void emit(List<Poll> polls) => _controller.add(polls);

  Future<void> vote(String pollId, String memberId, List<String> ids) async {}
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
  Future<void> updatePoll(String pollId, {
    required String title,
    required String description,
    required List<PollOption> options,
    required bool allowMultiple,
    required bool isActive,
    required bool isVisible,
    required bool isSecretBallot,
  }) async {}
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
}
```

- [ ] **Step 2: Run to verify fail**

```bash
flutter test test/widget/abstimmungen_screen_test.dart
```

Expected: FAIL — "Target of URI doesn't exist"

- [ ] **Step 3: Implement AbstimmungenScreen**

```dart
// lib/screens/abstimmungen_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/polls_api.dart';
import '../config_loader.dart';
import '../models/poll.dart';
import '../widgets/poll_card.dart';
import '../widgets/poll_form_dialog.dart';
import 'default_screen.dart';

class AbstimmungenScreen extends DefaultScreen {
  final PollsApi? pollsApi;

  const AbstimmungenScreen({super.key, required super.config, this.pollsApi})
      : super(title: 'Abstimmungen');

  @override
  DefaultScreenState createState() => _AbstimmungenScreenState();
}

class _AbstimmungenScreenState extends DefaultScreenState<AbstimmungenScreen> {
  late final PollsApi _api;
  late final StreamSubscription<List<Poll>> _sub;
  List<Poll>? _polls;

  @override
  void initState() {
    super.initState();
    _api = widget.pollsApi ?? PollsApi(widget.config);
    _sub = _api.watchPolls().listen(
      (polls) { if (mounted) setState(() => _polls = polls); },
      onError: (e) { if (mounted) showError('Firebase-Fehler: $e'); },
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _onVote(String pollId, List<String> selectedIds) async {
    try {
      await _api.vote(pollId, widget.config.memberId, selectedIds);
    } catch (e) {
      if (mounted) showError('Fehler beim Abstimmen: $e');
    }
  }

  void _openCreate(BuildContext context) {
    showPollFormDialog(
      context,
      onSave: (data) async {
        try {
          await _api.createPoll(
            title: data.title,
            description: data.description,
            optionTexts: data.optionTexts,
            allowMultiple: data.allowMultiple,
            isActive: data.isActive,
            isVisible: data.isVisible,
            isSecretBallot: data.isSecretBallot,
            authorId: widget.config.memberId,
          );
        } catch (e) {
          if (mounted) showError('Fehler beim Erstellen: $e');
        }
      },
    );
  }

  void _openEdit(BuildContext context, Poll poll, bool isSuperAdmin) {
    showPollFormDialog(
      context,
      poll: poll,
      onSave: (data) async {
        final updatedOptions = data.optionTexts.asMap().entries.map((e) {
          final existingId = e.key < poll.options.length
              ? poll.options[e.key].id
              : 'opt${poll.options.length + e.key}';
          return PollOption(id: existingId, text: e.value);
        }).toList();
        try {
          await _api.updatePoll(
            poll.id,
            title: data.title,
            description: data.description,
            options: updatedOptions,
            allowMultiple: data.allowMultiple,
            isActive: data.isActive,
            isVisible: data.isVisible,
            isSecretBallot: data.isSecretBallot,
          );
        } catch (e) {
          if (mounted) showError('Fehler beim Speichern: $e');
        }
      },
      onDelete: isSuperAdmin
          ? () async {
              Navigator.pop(context);
              try {
                await _api.deletePoll(poll.id);
              } catch (e) {
                if (mounted) showError('Fehler beim Löschen: $e');
              }
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);
    final polls = _polls;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Abstimmungen'),
        actions: [
          if (member.isAdmin || member.isSuperAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _openCreate(context),
            ),
        ],
      ),
      body: polls == null
          ? const Center(child: CircularProgressIndicator())
          : _buildList(context, polls, member),
    );
  }

  Widget _buildList(BuildContext context, List<Poll> polls, Member member) {
    final visible = (member.isAdmin || member.isSuperAdmin)
        ? polls
        : polls.where((p) => p.isVisible).toList();

    if (visible.isEmpty) {
      return const Center(child: Text('Keine Abstimmungen vorhanden'));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: visible.length,
      itemBuilder: (_, i) {
        final poll = visible[i];
        return PollCard(
          poll: poll,
          currentMemberId: widget.config.memberId,
          isAdmin: member.isAdmin || member.isSuperAdmin,
          isSuperAdmin: member.isSuperAdmin,
          onVote: _onVote,
          onEdit: (member.isAdmin || member.isSuperAdmin)
              ? () => _openEdit(context, poll, member.isSuperAdmin)
              : null,
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/widget/abstimmungen_screen_test.dart
```

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/screens/abstimmungen_screen.dart test/widget/abstimmungen_screen_test.dart
git commit -m "feat: add AbstimmungenScreen with real-time Firebase stream"
```

---

## Task 7: Home Screen Integration

**Files:**
- Modify: `lib/screens/home_screen.dart`

Add the `📊 Abstimmungen` tile to the grid menu, following the existing `_isScreenActive` pattern.

- [ ] **Step 1: Add import and menu tile to home_screen.dart**

In `lib/screens/home_screen.dart`, add the import near the other screen imports:

```dart
import 'abstimmungen_screen.dart';
```

Then in `_buildGridMenu`, add this tile after the Marschbefehl tile (or wherever appropriate in the list):

```dart
if (_isScreenActive('abstimmungen'))
  _buildMenuTile(
    context,
    '📊 Abstimmungen',
    () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AbstimmungenScreen(config: widget.config),
      ),
    ),
  ),
```

- [ ] **Step 2: Verify the app compiles**

```bash
flutter analyze lib/screens/home_screen.dart
```

Expected: No errors

- [ ] **Step 3: Run all tests**

```bash
flutter test
```

Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: add Abstimmungen tile to home screen"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] Title, description, options, flags (allowMultiple, isActive, isVisible, isSecretBallot, authorId, createdAt) → Task 1
- [x] Firebase Realtime Database storage + live stream → Task 2
- [x] Bar chart with absolute counts → Task 3
- [x] Create/edit form with all flags → Task 4
- [x] Voting UI (single/multi-select, submit/change button) → Task 5
- [x] Scrollable screen, newest at bottom, visible-only filter → Task 6
- [x] Admin `+` icon top right → Task 6
- [x] Admin edit, Super Admin delete → Task 4 + Task 6
- [x] Secret ballot hides results while active → Task 5 + Task 3
- [x] Home screen tile with `_isScreenActive` guard → Task 7

**Placeholder scan:** No TBDs, no "similar to Task N" references.

**Type consistency:** `PollsApi`, `PollFormData`, `PollOption`, `PollVote`, `Poll` used consistently across all tasks.

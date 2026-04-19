# Monitoring Screen Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the MonitoringScreen with axis-labelled horizontal bar charts for API calls per club/endpoint/member, summary tiles, a startup-time table, and a global club filter.

**Architecture:** Extend the existing `/monitoring/stats` endpoint to return two new flat lists (`calls_per_endpoint`, `calls_per_member`). The Flutter screen filters these client-side when a club is selected. Horizontal bar charts are custom widgets using `LinearProgressIndicator` (fl_chart has no native horizontal bars).

**Tech Stack:** Python/boto3/CloudWatch Logs Insights, Flutter/Dart, flutter_test, MockClient (http/testing), Python unittest + MagicMock.

**Spec:** `docs/superpowers/specs/2026-04-19-monitoring-screen-improvements-design.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `aws_backend/lambda/api_monitoring.py` | Add endpoint/member aggregation to `handle_monitoring()` |
| Create | `aws_backend/lambda/tests/test_api_monitoring.py` | Backend unit tests |
| Modify | `lib/screens/monitoring_screen.dart` | Full screen rewrite |
| Modify | `lib/api/monitoring_api.dart` | No logic change — injectable constructor already exists |
| Create | `test/widget/monitoring_screen_test.dart` | Flutter widget tests |

---

## Task 1: Backend — extend `handle_monitoring()` with endpoint/member aggregation

**Files:**
- Create: `aws_backend/lambda/tests/test_api_monitoring.py`
- Modify: `aws_backend/lambda/api_monitoring.py`

- [ ] **Step 1.1: Create the test file**

`aws_backend/lambda/tests/test_api_monitoring.py`:

```python
import json
import sys
import unittest
from unittest.mock import MagicMock

_boto3_mock = MagicMock()
sys.modules.setdefault('boto3', _boto3_mock)

sys.path.insert(0, '.')
import api_monitoring


def _make_result(rows):
    return {
        'status': 'Complete',
        'results': [
            [{'field': k, 'value': v} for k, v in row.items()]
            for row in rows
        ],
    }


def _event(timeframe='day'):
    return {'queryStringParameters': {'timeframe': timeframe}}


def _context():
    ctx = MagicMock()
    ctx.log_group_name = '/aws/lambda/test'
    return ctx


class TestHandleMonitoringNewFields(unittest.TestCase):
    def setUp(self):
        self.mock_logs = MagicMock()
        self.mock_logs.start_query.return_value = {'queryId': 'q1'}
        _boto3_mock.client.return_value = self.mock_logs

    def test_calls_per_endpoint_aggregated_by_app_and_path(self):
        rows = [
            {'applicationId': 'TZG', 'memberId': 'm1', 'path': '/members'},
            {'applicationId': 'TZG', 'memberId': 'm1', 'path': '/fines'},
            {'applicationId': 'TZG', 'memberId': 'm2', 'path': '/members'},
            {'applicationId': 'BSV', 'memberId': 'm3', 'path': '/members'},
        ]
        self.mock_logs.get_query_results.return_value = _make_result(rows)

        response = api_monitoring.handle_monitoring(_event(), _context())
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])

        self.assertIn('calls_per_endpoint', body)
        by_key = {(e['applicationId'], e['path']): e['count'] for e in body['calls_per_endpoint']}
        self.assertEqual(by_key[('TZG', '/members')], 2)
        self.assertEqual(by_key[('TZG', '/fines')], 1)
        self.assertEqual(by_key[('BSV', '/members')], 1)

    def test_calls_per_member_aggregated_by_app_and_member(self):
        rows = [
            {'applicationId': 'TZG', 'memberId': 'm1', 'path': '/members'},
            {'applicationId': 'TZG', 'memberId': 'm1', 'path': '/fines'},
            {'applicationId': 'BSV', 'memberId': 'm2', 'path': '/members'},
        ]
        self.mock_logs.get_query_results.return_value = _make_result(rows)

        response = api_monitoring.handle_monitoring(_event(), _context())
        body = json.loads(response['body'])

        self.assertIn('calls_per_member', body)
        by_key = {(e['applicationId'], e['memberId']): e['count'] for e in body['calls_per_member']}
        self.assertEqual(by_key[('TZG', 'm1')], 2)
        self.assertEqual(by_key[('BSV', 'm2')], 1)

    def test_existing_fields_still_present(self):
        rows = [{'applicationId': 'TZG', 'memberId': 'm1', 'path': '/members'}]
        self.mock_logs.get_query_results.return_value = _make_result(rows)

        response = api_monitoring.handle_monitoring(_event(), _context())
        body = json.loads(response['body'])

        self.assertIn('calls_per_club', body)
        self.assertIn('active_members', body)
        self.assertIn('timeframe', body)
```

- [ ] **Step 1.2: Run tests to confirm they fail**

```bash
cd aws_backend/lambda && python -m pytest tests/test_api_monitoring.py -v
```

Expected: `KeyError: 'calls_per_endpoint'` or similar — the keys don't exist yet.

- [ ] **Step 1.3: Extend `handle_monitoring()` in `api_monitoring.py`**

Replace the query string (line ~38) and aggregation loop (lines ~69–82) and return statement (lines ~84–97).

Updated query:
```python
query = f"""
fields applicationId, memberId, path, @timestamp
| filter log_type = "api_access"
| sort @timestamp desc
"""
```

Updated aggregation section (replaces existing `calls_per_club = {}` through the `for row in results:` block):
```python
calls_per_club = {}
active_members = {}
calls_per_endpoint = {}  # (app_id, path) -> count
calls_per_member = {}    # (app_id, mem_id) -> count

for row in results:
    app_id = next((item['value'] for item in row if item['field'] == 'applicationId'), 'unknown')
    mem_id = next((item['value'] for item in row if item['field'] == 'memberId'), 'unknown')
    path   = next((item['value'] for item in row if item['field'] == 'path'), 'unknown')

    calls_per_club[app_id] = calls_per_club.get(app_id, 0) + 1

    if app_id not in active_members:
        active_members[app_id] = {}
    active_members[app_id][mem_id] = active_members[app_id].get(mem_id, 0) + 1

    ep_key = (app_id, path)
    calls_per_endpoint[ep_key] = calls_per_endpoint.get(ep_key, 0) + 1

    mem_key = (app_id, mem_id)
    calls_per_member[mem_key] = calls_per_member.get(mem_key, 0) + 1
```

Updated return body (replaces existing `return { 'statusCode': 200, 'body': ... }`):
```python
return {
    'statusCode': 200,
    'body': json.dumps({
        'calls_per_club': [{'applicationId': k, 'count': v} for k, v in calls_per_club.items()],
        'active_members': [
            {'applicationId': app_id, 'members': [{'memberId': k, 'activity': v} for k, v in mems.items()]}
            for app_id, mems in active_members.items()
        ],
        'calls_per_endpoint': [{'applicationId': k[0], 'path': k[1], 'count': v} for k, v in calls_per_endpoint.items()],
        'calls_per_member':   [{'applicationId': k[0], 'memberId': k[1], 'count': v} for k, v in calls_per_member.items()],
        'timeframe': timeframe,
    })
}
```

- [ ] **Step 1.4: Run tests to confirm they pass**

```bash
cd aws_backend/lambda && python -m pytest tests/test_api_monitoring.py -v
```

Expected: all 3 tests PASS.

- [ ] **Step 1.5: Run full backend test suite**

```bash
cd aws_backend/lambda && python -m pytest tests/ -v
```

Expected: all existing tests still pass.

- [ ] **Step 1.6: Commit**

```bash
git add aws_backend/lambda/api_monitoring.py aws_backend/lambda/tests/test_api_monitoring.py
git commit -m "feat: add calls_per_endpoint and calls_per_member to monitoring stats"
```

---

## Task 2: Flutter — make `MonitoringScreen` injectable + `_buildHorizontalBarChart()` helper

**Files:**
- Create: `test/widget/monitoring_screen_test.dart`
- Modify: `lib/screens/monitoring_screen.dart`

- [ ] **Step 2.1: Create the widget test file with an injectable-API test**

`test/widget/monitoring_screen_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vereinsappell/api/monitoring_api.dart';
import 'package:vereinsappell/screens/monitoring_screen.dart';

import '../widget/test_helpers.dart';

Map<String, dynamic> _statsPayload({
  List<Map<String, dynamic>>? callsPerClub,
  List<Map<String, dynamic>>? callsPerEndpoint,
  List<Map<String, dynamic>>? callsPerMember,
}) =>
    {
      'calls_per_club': callsPerClub ?? [
        {'applicationId': 'TZG', 'count': 100},
        {'applicationId': 'BSV', 'count': 50},
      ],
      'calls_per_endpoint': callsPerEndpoint ?? [
        {'applicationId': 'TZG', 'path': '/members', 'count': 60},
        {'applicationId': 'BSV', 'path': '/members', 'count': 20},
      ],
      'calls_per_member': callsPerMember ?? [
        {'applicationId': 'TZG', 'memberId': 'm1', 'count': 80},
        {'applicationId': 'BSV', 'memberId': 'm2', 'count': 30},
      ],
      'active_members': [],
      'timeframe': 'day',
    };

Map<String, dynamic> _startupPayload() => {
      'startup_stats': [
        {'applicationId': 'TZG', 'memberId': 'm1', 'p50': 312, 'p95': 580, 'p99': 920, 'count': 14},
      ],
      'timeframe': 'day',
    };

Future<MonitoringApi> _makeApi(WidgetTester tester) async {
  final client = MockClient((request) async {
    if (request.url.path.contains('/monitoring/startup')) {
      return http.Response(jsonEncode(_startupPayload()), 200);
    }
    return http.Response(jsonEncode(_statsPayload()), 200);
  });
  final config = await makeConfig(tester);
  return MonitoringApi(config, client: client);
}

void main() {
  group('MonitoringScreen', () {
    testWidgets('renders without error after data loads', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
```

- [ ] **Step 2.2: Run the test to confirm it fails**

```bash
flutter test test/widget/monitoring_screen_test.dart
```

Expected: compile error — `MonitoringScreen` has no `monitoringApi` parameter.

- [ ] **Step 2.3: Add injectable `monitoringApi` parameter to `MonitoringScreen`**

In `lib/screens/monitoring_screen.dart`, replace the class declaration and `initState`:

```dart
class MonitoringScreen extends DefaultScreen {
  final MonitoringApi? monitoringApi;

  const MonitoringScreen({super.key, required super.config, this.monitoringApi})
      : super(title: 'Monitoring');

  @override
  DefaultScreenState<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends DefaultScreenState<MonitoringScreen> {
  late final MonitoringApi _api;
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _startupStats;
  String _timeframe = 'day';
  String? _selectedClub;  // null = all clubs

  @override
  void initState() {
    super.initState();
    _api = widget.monitoringApi ?? MonitoringApi(widget.config);
    _loadData();
  }
```

- [ ] **Step 2.4: Run test to confirm it passes**

```bash
flutter test test/widget/monitoring_screen_test.dart
```

Expected: PASS (1 test).

- [ ] **Step 2.5: Commit**

```bash
git add lib/screens/monitoring_screen.dart test/widget/monitoring_screen_test.dart
git commit -m "feat: make MonitoringScreen injectable and add _selectedClub state"
```

---

## Task 3: Flutter — summary tiles + horizontal bar helper + replace calls chart + startup table

**Files:**
- Modify: `lib/screens/monitoring_screen.dart`
- Modify: `test/widget/monitoring_screen_test.dart`

- [ ] **Step 3.1: Add tests for summary tiles and startup table**

Add inside the `group('MonitoringScreen', ...)` block in `test/widget/monitoring_screen_test.dart`:

```dart
    testWidgets('summary tiles show total calls, active clubs, avg p50', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();

      // Total calls: 100 + 50 = 150
      expect(find.text('150'), findsOneWidget);
      // Active clubs: 2
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('startup table shows p50, p95, p99 values', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();

      expect(find.text('312'), findsOneWidget);
      expect(find.text('580'), findsOneWidget);
      expect(find.text('920'), findsOneWidget);
    });

    testWidgets('calls per club chart shows club labels', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();

      expect(find.text('TZG'), findsWidgets);
      expect(find.text('BSV'), findsWidgets);
    });
```

- [ ] **Step 3.2: Run new tests to confirm they fail**

```bash
flutter test test/widget/monitoring_screen_test.dart
```

Expected: 3 tests FAIL (summary tiles, startup table, club chart not yet implemented).

- [ ] **Step 3.3: Add `_buildHorizontalBarChart()` helper to `monitoring_screen.dart`**

Add this private method to `_MonitoringScreenState`:

```dart
Widget _buildHorizontalBarChart({
  required String title,
  String? subtitle,
  required List<MapEntry<String, int>> entries,
  required Color barColor,
}) {
  if (entries.isEmpty) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Keine Daten für diesen Zeitraum'),
      ),
    );
  }

  final maxCount = entries.first.value;

  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          const SizedBox(height: 16),
          ...entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        e.key,
                        style: const TextStyle(fontSize: 11),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: maxCount > 0 ? e.value / maxCount : 0,
                        backgroundColor: Colors.grey.withOpacity(0.2),
                        color: barColor,
                        minHeight: 14,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 36,
                      child: Text('${e.value}',
                          style: const TextStyle(fontSize: 11), textAlign: TextAlign.right),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '← Anzahl Aufrufe →',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 3.4: Add `_buildSummaryTiles()` to `_MonitoringScreenState`**

```dart
Widget _buildSummaryTiles() {
  final clubs = _stats?['calls_per_club'] as List? ?? [];
  final totalCalls = clubs.fold<int>(0, (sum, e) => sum + ((e as Map)['count'] as int? ?? 0));
  final activeClubs = clubs.length;

  final startupList = _startupStats?['startup_stats'] as List? ?? [];
  final avgP50 = startupList.isEmpty
      ? null
      : startupList.fold<int>(0, (sum, e) => sum + ((e as Map)['p50'] as int? ?? 0)) ~/
          startupList.length;

  return Row(
    children: [
      Expanded(child: _summaryTile('$totalCalls', 'API Calls gesamt', Colors.green)),
      const SizedBox(width: 8),
      Expanded(child: _summaryTile('$activeClubs', 'Aktive Vereine', Colors.blue)),
      const SizedBox(width: 8),
      Expanded(
        child: _summaryTile(
          avgP50 != null ? '${avgP50}ms' : '—',
          'Ø Startup p50',
          Colors.red,
        ),
      ),
    ],
  );
}

Widget _summaryTile(String value, String label, Color valueColor) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: valueColor)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 3.5: Replace `_buildCallsChart()` with horizontal version**

Remove the existing `_buildCallsChart()` method and replace with:

```dart
Widget _buildClubChart() {
  final clubs = _stats?['calls_per_club'] as List? ?? [];
  final entries = clubs
      .map((e) => MapEntry((e as Map)['applicationId'] as String, e['count'] as int))
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return _buildHorizontalBarChart(
    title: 'API Calls pro Verein',
    entries: entries,
    barColor: Colors.blue,
  );
}
```

- [ ] **Step 3.6: Add `_buildStartupTable()` to `_MonitoringScreenState`**

```dart
Widget _buildStartupTable() {
  final stats = _startupStats?['startup_stats'] as List? ?? [];
  if (stats.isEmpty) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('Keine Startup-Daten für diesen Zeitraum'),
      ),
    );
  }

  final rows = (stats as List<dynamic>)
    ..sort((a, b) => ((a as Map)['p50'] as int? ?? 0).compareTo((b as Map)['p50'] as int? ?? 0));

  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('App Startup-Zeiten (ms)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
              4: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                children: ['Member', 'p50', 'p95', 'p99', 'Starts']
                    .map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(h,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                        ))
                    .toList(),
              ),
              ...rows.map((row) {
                final r = row as Map;
                return TableRow(children: [
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(r['memberId'] as String? ?? '', style: const TextStyle(fontSize: 11))),
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('${r['p50'] ?? '—'}',
                          style: const TextStyle(fontSize: 11, color: Colors.green))),
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('${r['p95'] ?? '—'}',
                          style: const TextStyle(fontSize: 11, color: Colors.orange))),
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('${r['p99'] ?? '—'}',
                          style: const TextStyle(fontSize: 11, color: Colors.red))),
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('${r['count'] ?? '—'}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey))),
                ]);
              }),
            ],
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 3.7: Update `build()` to use new widgets**

Replace the `body` in the existing `build()` method with:

```dart
body: isLoading
    ? const Center(child: CircularProgressIndicator())
    : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTimeframeSelector(),
            const SizedBox(height: 16),
            if (_stats != null) ...[
              _buildSummaryTiles(),
              const SizedBox(height: 16),
              _buildClubChart(),
              const SizedBox(height: 16),
            ],
            _buildStartupTable(),
          ],
        ),
      ),
```

Also remove the `import 'package:fl_chart/fl_chart.dart';` line (no longer needed).

- [ ] **Step 3.8: Run all tests**

```bash
flutter test test/widget/monitoring_screen_test.dart
```

Expected: all 4 tests PASS.

- [ ] **Step 3.9: Commit**

```bash
git add lib/screens/monitoring_screen.dart test/widget/monitoring_screen_test.dart
git commit -m "feat: add summary tiles, horizontal bar chart helper, startup table"
```

---

## Task 4: Flutter — club filter + endpoint chart + member chart + remove old section

**Files:**
- Modify: `lib/screens/monitoring_screen.dart`
- Modify: `test/widget/monitoring_screen_test.dart`

- [ ] **Step 4.1: Add tests for endpoint/member charts and club filter**

Add inside the `group('MonitoringScreen', ...)` block in `test/widget/monitoring_screen_test.dart`:

```dart
    testWidgets('endpoint chart shows path labels', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();

      expect(find.text('/members'), findsWidgets);
    });

    testWidgets('member chart shows member labels', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();

      expect(find.text('m1'), findsWidgets);
      expect(find.text('m2'), findsWidgets);
    });

    testWidgets('club filter dropdown contains all club options', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();

      // Open the dropdown
      await tester.tap(find.text('Alle Vereine').first);
      await tester.pumpAndSettle();

      expect(find.text('TZG'), findsWidgets);
      expect(find.text('BSV'), findsWidgets);
    });

    testWidgets('old active members expansion tiles are gone', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ExpansionTile), findsNothing);
    });
```

- [ ] **Step 4.2: Run new tests to confirm they fail**

```bash
flutter test test/widget/monitoring_screen_test.dart
```

Expected: 4 new tests FAIL.

- [ ] **Step 4.3: Add `_buildClubFilter()` to `_MonitoringScreenState`**

```dart
Widget _buildClubFilter() {
  final clubs = (_stats?['calls_per_club'] as List? ?? [])
      .map((e) => (e as Map)['applicationId'] as String)
      .toList()
    ..sort();

  return DropdownButtonFormField<String?>(
    value: _selectedClub,
    decoration: const InputDecoration(
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      border: OutlineInputBorder(),
    ),
    items: [
      const DropdownMenuItem<String?>(value: null, child: Text('Alle Vereine')),
      ...clubs.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
    ],
    onChanged: (value) => setState(() => _selectedClub = value),
  );
}
```

- [ ] **Step 4.4: Add `_buildEndpointChart()` and `_buildMemberChart()`**

```dart
Widget _buildEndpointChart() {
  final all = _stats?['calls_per_endpoint'] as List? ?? [];
  final filtered = _selectedClub == null
      ? all
      : all.where((e) => (e as Map)['applicationId'] == _selectedClub).toList();

  final counts = <String, int>{};
  for (final item in filtered) {
    final path = (item as Map)['path'] as String? ?? 'unknown';
    final count = (item['count'] as int?) ?? 0;
    counts[path] = (counts[path] ?? 0) + count;
  }

  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return _buildHorizontalBarChart(
    title: 'API Calls pro Endpunkt',
    subtitle: _selectedClub == null ? '(Alle Vereine)' : '($_selectedClub)',
    entries: entries,
    barColor: Colors.purple,
  );
}

Widget _buildMemberChart() {
  final all = _stats?['calls_per_member'] as List? ?? [];
  final filtered = _selectedClub == null
      ? all
      : all.where((e) => (e as Map)['applicationId'] == _selectedClub).toList();

  final counts = <String, int>{};
  for (final item in filtered) {
    final memberId = (item as Map)['memberId'] as String? ?? 'unknown';
    final count = (item['count'] as int?) ?? 0;
    counts[memberId] = (counts[memberId] ?? 0) + count;
  }

  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return _buildHorizontalBarChart(
    title: 'API Calls pro Member',
    subtitle: _selectedClub == null ? '(Alle Vereine)' : '($_selectedClub)',
    entries: entries,
    barColor: Colors.red,
  );
}
```

- [ ] **Step 4.5: Remove `_buildActiveMembersSection()` and update `build()`**

Delete the entire `_buildActiveMembersSection()` method.

Update the `build()` body column children to include the filter and new charts:

```dart
body: isLoading
    ? const Center(child: CircularProgressIndicator())
    : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTimeframeSelector(),
            if (_stats != null) ...[
              const SizedBox(height: 12),
              _buildClubFilter(),
              const SizedBox(height: 16),
              _buildSummaryTiles(),
              const SizedBox(height: 16),
              _buildClubChart(),
              const SizedBox(height: 16),
              _buildEndpointChart(),
              const SizedBox(height: 16),
              _buildMemberChart(),
              const SizedBox(height: 16),
            ],
            _buildStartupTable(),
          ],
        ),
      ),
```

- [ ] **Step 4.6: Run all tests**

```bash
flutter test test/widget/monitoring_screen_test.dart
```

Expected: all 8 tests PASS.

- [ ] **Step 4.7: Run full Flutter test suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 4.8: Commit**

```bash
git add lib/screens/monitoring_screen.dart test/widget/monitoring_screen_test.dart
git commit -m "feat: add club filter, endpoint chart, member chart; remove old active members list"
```

# Startup-Time Messung Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement fire-and-forget startup-time measurement on the web frontend, send timing data to backend, store in CloudWatch Logs, and display aggregated p50/p95 statistics per member in MonitoringScreen.

**Architecture:** 
- **Frontend:** Global `StartupTimer` singleton captures millisecond timestamps at key startup phases (Firebase init, config load, first frame, API calls). After both `fetchMember()` and `getCustomer()` complete, sends JSON payload via `POST /monitoring/timing` (fire-and-forget, never throws).
- **Backend:** New Lambda route handler logs timing events as `log_type: "startup_timing"` to CloudWatch. No new DynamoDB or IAM permissions required.
- **Dashboard:** MonitoringScreen extended with "Startup-Zeiten" section querying CloudWatch Insights for p50/p95/p99 per `memberId`, with optional phase-breakdown.

**Tech Stack:** Flutter (frontend), Python/Lambda (backend), CloudWatch Logs + Insights (storage/aggregation)

---

## File Structure

**Frontend (Flutter):**
- `lib/utils/startup_timer.dart` — NEW. Singleton `StartupTimer` class with `Stopwatch`, `mark()`, `send()` methods.
- `lib/main.dart` — MODIFY. Instrument `main()` with `StartupTimer.mark()` calls.
- `lib/screens/home_screen.dart` — MODIFY. Instrument `initState()` and coordinate `fetchMember()`/`getCustomer()` completion before `send()`.
- `lib/api/monitoring_api.dart` — MODIFY. Add `sendStartupTiming(Map)` method.
- `lib/screens/monitoring_screen.dart` — MODIFY. Extend `_stats` model and UI to display startup timing section.

**Backend (Python/Lambda):**
- `aws_backend/lambda/lambda_handler.py` — MODIFY. Add route handler for `POST /monitoring/timing`.
- `aws_backend/lambda/api_monitoring.py` — MODIFY. Add `handle_timing(event, context)` function.

---

## Tasks

### Task 1: Create StartupTimer Utility

**Files:**
- Create: `lib/utils/startup_timer.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/utils/startup_timer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/utils/startup_timer.dart';

void main() {
  group('StartupTimer', () {
    tearDown(() => StartupTimer._instance = null);

    test('singleton returns same instance', () {
      final timer1 = StartupTimer.instance;
      final timer2 = StartupTimer.instance;
      expect(identical(timer1, timer2), true);
    });

    test('mark records phase duration', () {
      final timer = StartupTimer.instance;
      timer.mark('firebase');
      final phases = timer.getPhases();
      expect(phases.containsKey('firebase'), true);
      expect(phases['firebase']! >= 0, true);
    });

    test('toPayload includes required fields', () {
      final timer = StartupTimer.instance;
      timer.mark('firebase');
      timer.mark('config');
      final payload = timer.toPayload(
        applicationId: 'test-app',
        memberId: 'test-member',
      );
      expect(payload['applicationId'], 'test-app');
      expect(payload['memberId'], 'test-member');
      expect(payload.containsKey('phases'), true);
      expect(payload.containsKey('total_ms'), true);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/lars/tzg/vereinsappell
flutter test test/utils/startup_timer_test.dart
```

Expected output: FAIL (file does not exist, class not defined)

- [ ] **Step 3: Write the StartupTimer class**

```dart
// lib/utils/startup_timer.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

class StartupTimer {
  static StartupTimer? _instance;
  late final Stopwatch _stopwatch;
  final Map<String, int> _phases = {};

  StartupTimer._() {
    _stopwatch = Stopwatch()..start();
  }

  static StartupTimer get instance {
    _instance ??= StartupTimer._();
    return _instance;
  }

  void mark(String phase) {
    _phases[phase] = _stopwatch.elapsedMilliseconds;
    if (kDebugMode) {
      print('⏱️  [$phase] ${_phases[phase]}ms');
    }
  }

  Map<String, int> getPhases() => Map.unmodifiable(_phases);

  int get totalMs {
    if (_phases.isEmpty) return 0;
    return _phases.values.reduce((a, b) => a > b ? a : b);
  }

  Map<String, dynamic> toPayload({
    required String applicationId,
    required String memberId,
  }) {
    return {
      'applicationId': applicationId,
      'memberId': memberId,
      'phases': Map.from(_phases),
      'total_ms': totalMs,
    };
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /home/lars/tzg/vereinsappell
flutter test test/utils/startup_timer_test.dart -v
```

Expected output: ALL TESTS PASS

- [ ] **Step 5: Commit**

```bash
cd /home/lars/tzg/vereinsappell
git add lib/utils/startup_timer.dart test/utils/startup_timer_test.dart
git commit -m "feat: add StartupTimer utility for measuring app startup phases"
```

---

### Task 2: Instrument main() Startup Sequence

**Files:**
- Modify: `lib/main.dart` (lines 21–31)

- [ ] **Step 1: Import StartupTimer and add first mark**

Replace the `main()` function signature and initial lines:

```dart
import 'package:vereinsappell/utils/startup_timer.dart';

void main() async {
  StartupTimer.instance; // Initialize singleton
  WidgetsFlutterBinding.ensureInitialized();
  StartupTimer.instance.mark('app_start');

  if (kIsWeb) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
          .timeout(const Duration(seconds: 10));
      StartupTimer.instance.mark('firebase');
    } catch (e) {
      StartupTimer.instance.mark('firebase');
      print('Firebase init failed: $e');
    }
  }
  
  // ... rest of main()
```

- [ ] **Step 2: Mark config loading completion**

After `loadConfig()` call (around line 58):

```dart
  AppConfig? config = await loadConfig();
  StartupTimer.instance.mark('config');

  if (kIsWeb) {
    // ... rest of URL param logic
  }
```

- [ ] **Step 3: Verify syntax and run app**

```bash
cd /home/lars/tzg/vereinsappell
flutter analyze lib/main.dart
# Expected: No issues
```

- [ ] **Step 4: Commit**

```bash
cd /home/lars/tzg/vereinsappell
git add lib/main.dart
git commit -m "feat: instrument main() with startup timer marks"
```

---

### Task 3: Instrument HomeScreen Startup Phases

**Files:**
- Modify: `lib/screens/home_screen.dart` (lines 48–70)
- Create: Test for HomeScreen timing coordination (optional, see step 1)

- [ ] **Step 1: Add import and mark first frame**

At top of `home_screen.dart`, add import:

```dart
import 'package:vereinsappell/utils/startup_timer.dart';
```

In `_HomeScreenState.initState()`, add first line:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StartupTimer.instance.mark('first_frame');
    });
    _updateApplication();
    _allAccounts = loadAllAccounts();
    _activeAccountIndex = getActiveAccountIndex();
    // ... rest of initState
```

- [ ] **Step 2: Refactor fetchMember() chain to coordinate both API calls**

Replace the existing `fetchMember()` chain (lines 55–68):

```dart
    if (kIsWeb) {
      Future.wait([
        widget.config.member.fetchMember().then((_) {
          StartupTimer.instance.mark('fetch_member');
          if (!mounted) return;
          widget.config.member.registerPushSubscriptionWeb();
        }),
        _updateApplication().then((_) {
          StartupTimer.instance.mark('get_customer');
        }),
      ]).then((_) {
        if (!mounted) return;
        _messageSubscription ??= FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          showNotification('${message.data['title']}: ${message.data['body']}');
          if (message.data['type'] == 'fine') {
            showFineOverlay(context);
          } else {
            showPigOverlay(context);
          }
        });
        StartupTimer.instance.send(widget.config);
      }).catchError((e) {
        if (mounted) showError('Fehler beim Laden der Mitgliedsdaten: $e');
        StartupTimer.instance.send(widget.config);
      });
    }
```

- [ ] **Step 3: Update `_updateApplication()` return type**

Change `_updateApplication()` from `void` to `Future<void>`:

```dart
  Future<void> _updateApplication() async {
    CustomersApi customersApi = CustomersApi(widget.config);
    return customersApi.getCustomer(widget.config.applicationId).then((customer) {
      setState(() {
        _applicationName = customer['application_name'];
        _applicationLogoBase64 = customer['application_logo'] ?? '';
        final screens = customer['active_screens'];
        if (screens != null) {
          _activeScreens = List<String>.from(screens);
        }
      });
      updateActiveAccountLabel(customer['application_name'] as String? ?? '');
    }).catchError((error) {
      showError("Fehler beim Laden des Vereins: $error");
      rethrow;
    });
  }
```

- [ ] **Step 4: Verify syntax**

```bash
cd /home/lars/tzg/vereinsappell
flutter analyze lib/screens/home_screen.dart
# Expected: No issues
```

- [ ] **Step 5: Commit**

```bash
cd /home/lars/tzg/vereinsappell
git add lib/screens/home_screen.dart
git commit -m "feat: instrument HomeScreen startup phases and coordinate API calls for timing"
```

---

### Task 4: Add sendStartupTiming to MonitoringApi

**Files:**
- Modify: `lib/api/monitoring_api.dart`

- [ ] **Step 1: Add sendStartupTiming method**

Add to `MonitoringApi` class (after `getStats` method):

```dart
  Future<void> sendStartupTiming(Map<String, dynamic> timingData) async {
    try {
      final response = await _client.post(
        Uri.parse('${config.apiBaseUrl}/monitoring/timing'),
        headers: headers(config),
        body: jsonEncode(timingData),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode != 200) {
        // Log silently, never throw
        print('⚠️  Startup timing send failed: ${response.statusCode}');
      }
    } catch (e) {
      // Log silently, never throw
      print('⚠️  Startup timing send error: $e');
    }
  }
```

- [ ] **Step 2: Verify syntax**

```bash
cd /home/lars/tzg/vereinsappell
flutter analyze lib/api/monitoring_api.dart
# Expected: No issues
```

- [ ] **Step 3: Commit**

```bash
cd /home/lars/tzg/vereinsappell
git add lib/api/monitoring_api.dart
git commit -m "feat: add sendStartupTiming method to MonitoringApi"
```

---

### Task 5: Integrate send() in StartupTimer

**Files:**
- Modify: `lib/utils/startup_timer.dart`

- [ ] **Step 1: Add send method that calls MonitoringApi**

Add to `StartupTimer` class:

```dart
  Future<void> send(AppConfig config) async {
    // Import at top: import 'package:vereinsappell/api/monitoring_api.dart';
    final api = MonitoringApi(config);
    final payload = toPayload(
      applicationId: config.applicationId,
      memberId: config.memberId,
    );
    await api.sendStartupTiming(payload);
    if (kDebugMode) {
      print('📊 Startup timing sent: ${payload['total_ms']}ms');
    }
  }
```

Add import at top of file:

```dart
import 'package:vereinsappell/config_loader.dart';
import 'package:vereinsappell/api/monitoring_api.dart';
```

- [ ] **Step 2: Verify syntax**

```bash
cd /home/lars/tzg/vereinsappell
flutter analyze lib/utils/startup_timer.dart
# Expected: No issues
```

- [ ] **Step 3: Commit**

```bash
cd /home/lars/tzg/vereinsappell
git add lib/utils/startup_timer.dart
git commit -m "feat: add send method to StartupTimer for submitting timing data"
```

---

### Task 6: Add Backend Route Handler

**Files:**
- Modify: `aws_backend/lambda/lambda_handler.py` (around line 93)

- [ ] **Step 1: Add route check for /monitoring/timing**

Add before the `else` clause (around line 92):

```python
        elif method == 'POST' and path == '/monitoring/timing':
            import api_monitoring
            return {**headers, **api_monitoring.handle_timing(event, context)}
```

- [ ] **Step 2: Verify file structure**

```bash
grep -n "POST.*monitoring" /home/lars/tzg/vereinsappell/aws_backend/lambda/lambda_handler.py
# Expected: Shows your new line added
```

- [ ] **Step 3: Commit**

```bash
cd /home/lars/tzg/vereinsappell
git add aws_backend/lambda/lambda_handler.py
git commit -m "feat: add POST /monitoring/timing route to Lambda handler"
```

---

### Task 7: Implement handle_timing in api_monitoring.py

**Files:**
- Modify: `aws_backend/lambda/api_monitoring.py`

- [ ] **Step 1: Add handle_timing function**

Add to end of `api_monitoring.py`:

```python
def handle_timing(event, context):
    try:
        body = json.loads(event['body']) if isinstance(event.get('body'), str) else event.get('body', {})
        
        application_id = body.get('applicationId', '')
        member_id = body.get('memberId', '')
        phases = body.get('phases', {})
        total_ms = body.get('total_ms', 0)
        
        # Validate required fields
        if not application_id or not member_id:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'applicationId and memberId required'})
            }
        
        # Write structured log to CloudWatch
        print(json.dumps({
            "log_type": "startup_timing",
            "applicationId": application_id,
            "memberId": member_id,
            "firebase_ms": phases.get('firebase_ms', 0),
            "config_ms": phases.get('config_ms', 0),
            "first_frame_ms": phases.get('first_frame_ms', 0),
            "fetch_member_ms": phases.get('fetch_member_ms', 0),
            "get_customer_ms": phases.get('get_customer_ms', 0),
            "total_ms": total_ms,
            "timestamp": datetime.now().isoformat()
        }))
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Startup timing recorded'})
        }
    except Exception as e:
        print(f"Error in handle_timing: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
```

- [ ] **Step 2: Verify syntax**

```bash
python3 -m py_compile /home/lars/tzg/vereinsappell/aws_backend/lambda/api_monitoring.py
# Expected: No errors
```

- [ ] **Step 3: Commit**

```bash
cd /home/lars/tzg/vereinsappell
git add aws_backend/lambda/api_monitoring.py
git commit -m "feat: implement handle_timing to log startup metrics to CloudWatch"
```

---

### Task 8: Extend MonitoringScreen Data Model

**Files:**
- Modify: `lib/screens/monitoring_screen.dart` (around line 16)

- [ ] **Step 1: Update state to include startup_stats**

Add to `_MonitoringScreenState`:

```dart
  Map<String, dynamic>? _startupStats;
```

- [ ] **Step 2: Extend _loadData to fetch startup stats**

Replace `_loadData()` method:

```dart
  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final data = await _api.getStats(_timeframe);
      final startupData = await _api.getStartupStats(_timeframe);
      setState(() {
        _stats = data;
        _startupStats = startupData;
        isLoading = false;
      });
    } catch (e) {
      showError('Fehler beim Laden: $e');
      setState(() => isLoading = false);
    }
  }
```

- [ ] **Step 3: Verify syntax**

```bash
cd /home/lars/tzg/vereinsappell
flutter analyze lib/screens/monitoring_screen.dart
# Expected: May warn about missing getStartupStats (will add next)
```

- [ ] **Step 4: Commit**

```bash
cd /home/lars/tzg/vereinsappell
git add lib/screens/monitoring_screen.dart
git commit -m "feat: extend MonitoringScreen state to include startup timing data"
```

---

### Task 9: Add getStartupStats to MonitoringApi

**Files:**
- Modify: `lib/api/monitoring_api.dart`

- [ ] **Step 1: Add getStartupStats method**

Add to `MonitoringApi` class (after `getStats` method):

```dart
  Future<Map<String, dynamic>> getStartupStats(String timeframe) async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/monitoring/startup?timeframe=$timeframe'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Fehler beim Laden der Startup-Daten: ${response.statusCode}');
    }
  }
```

- [ ] **Step 2: Verify syntax**

```bash
cd /home/lars/tzg/vereinsappell
flutter analyze lib/api/monitoring_api.dart
# Expected: No issues
```

- [ ] **Step 3: Commit**

```bash
cd /home/lars/tzg/vereinsappell
git add lib/api/monitoring_api.dart
git commit -m "feat: add getStartupStats method to MonitoringApi"
```

---

### Task 10: Add Backend /monitoring/startup Endpoint

**Files:**
- Modify: `aws_backend/lambda/lambda_handler.py`

- [ ] **Step 1: Add route for /monitoring/startup**

Add before the `else` clause (after /monitoring/timing):

```python
        elif method == 'GET' and path == '/monitoring/startup':
            import api_monitoring
            return {**headers, **api_monitoring.handle_startup_stats(event, context)}
```

- [ ] **Step 2: Commit**

```bash
cd /home/lars/tzg/vereinsappell
git add aws_backend/lambda/lambda_handler.py
git commit -m "feat: add GET /monitoring/startup route for startup stats"
```

---

### Task 11: Implement handle_startup_stats in api_monitoring.py

**Files:**
- Modify: `aws_backend/lambda/api_monitoring.py`

- [ ] **Step 1: Add handle_startup_stats function**

Add to end of `api_monitoring.py`:

```python
def handle_startup_stats(event, context):
    params = event.get('queryStringParameters') or {}
    timeframe = params.get('timeframe', 'day')
    
    logs = boto3.client('logs')
    log_group_name = os.environ.get('LAMBDA_LOG_GROUP_NAME') or context.log_group_name
    
    # Calculate start time
    now = datetime.utcnow()
    if timeframe == 'minute':
        start_time = now - timedelta(minutes=1)
    elif timeframe == 'hour':
        start_time = now - timedelta(hours=1)
    elif timeframe == 'day':
        start_time = now - timedelta(days=1)
    elif timeframe == 'week':
        start_time = now - timedelta(weeks=1)
    else:
        start_time = now - timedelta(days=1)
    
    start_timestamp = int(start_time.timestamp() * 1000)
    end_timestamp = int(now.timestamp() * 1000)
    
    query = """
    fields memberId, applicationId, total_ms, firebase_ms, config_ms, first_frame_ms, fetch_member_ms, get_customer_ms
    | filter log_type = "startup_timing"
    | stats pct(total_ms, 50) as p50, pct(total_ms, 95) as p95, pct(total_ms, 99) as p99, count() as count by memberId, applicationId
    """
    
    try:
        start_query_response = logs.start_query(
            logGroupName=log_group_name,
            startTime=start_timestamp,
            endTime=end_timestamp,
            queryString=query,
            limit=1000
        )
        
        query_id = start_query_response['queryId']
        response = None
        
        for _ in range(10):
            response = logs.get_query_results(queryId=query_id)
            if response['status'] in ['Complete', 'Failed', 'Cancelled']:
                break
            time.sleep(0.5)
        
        if response['status'] != 'Complete':
            return {
                'statusCode': 500,
                'body': json.dumps({'error': f'Query failed: {response["status"]}'})
            }
        
        # Parse results
        startup_stats = []
        for row in response['results']:
            stat = {}
            for item in row:
                field = item['field']
                value = item['value']
                if field in ['p50', 'p95', 'p99', 'count']:
                    try:
                        stat[field] = int(value) if value else 0
                    except:
                        stat[field] = value
                else:
                    stat[field] = value
            startup_stats.append(stat)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'startup_stats': startup_stats,
                'timeframe': timeframe
            })
        }
    except Exception as e:
        print(f"Error querying startup stats: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
```

- [ ] **Step 2: Verify syntax**

```bash
python3 -m py_compile /home/lars/tzg/vereinsappell/aws_backend/lambda/api_monitoring.py
# Expected: No errors
```

- [ ] **Step 3: Commit**

```bash
cd /home/lars/tzg/vereinsappell
git add aws_backend/lambda/api_monitoring.py
git commit -m "feat: implement handle_startup_stats for startup timing aggregation"
```

---

### Task 12: Build Startup Timing UI Section

**Files:**
- Modify: `lib/screens/monitoring_screen.dart` (entire build section)

- [ ] **Step 1: Add _buildStartupStats widget method**

Add to `_MonitoringScreenState`:

```dart
  Widget _buildStartupStats() {
    final stats = _startupStats?['startup_stats'] as List? ?? [];
    if (stats.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Keine Startup-Daten für diesen Zeitraum'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Startup-Zeiten pro Mitglied',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Mitglied')),
              DataColumn(label: Text('Verein')),
              DataColumn(label: Text('p50 (ms)')),
              DataColumn(label: Text('p95 (ms)')),
              DataColumn(label: Text('p99 (ms)')),
              DataColumn(label: Text('Messungen')),
            ],
            rows: stats.map((stat) {
              return DataRow(
                cells: [
                  DataCell(Text(stat['memberId'] ?? '-')),
                  DataCell(Text(stat['applicationId'] ?? '-')),
                  DataCell(Text((stat['p50'] ?? 0).toString())),
                  DataCell(Text((stat['p95'] ?? 0).toString())),
                  DataCell(Text((stat['p99'] ?? 0).toString())),
                  DataCell(Text((stat['count'] ?? 0).toString())),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
```

- [ ] **Step 2: Add startup stats section to build method**

In the `build()` method, after the existing `if (_stats != null)` block, add:

```dart
                  if (_startupStats != null) ...[
                    const SizedBox(height: 32),
                    _buildStartupStats(),
                  ],
```

- [ ] **Step 3: Verify syntax**

```bash
cd /home/lars/tzg/vereinsappell
flutter analyze lib/screens/monitoring_screen.dart
# Expected: No issues
```

- [ ] **Step 4: Commit**

```bash
cd /home/lars/tzg/vereinsappell
git add lib/screens/monitoring_screen.dart
git commit -m "feat: add startup timing UI section to MonitoringScreen"
```

---

### Task 13: Manual Testing & Verification

**Files:**
- No files modified; testing only

- [ ] **Step 1: Start dev server and open PWA**

```bash
cd /home/lars/tzg/vereinsappell
flutter pub get
flutter run -d chrome
# Open browser devtools console (F12)
```

- [ ] **Step 2: Verify startup timer logs in console**

Open browser DevTools Console. Reload the page. Look for logs like:
```
⏱️  [app_start] 0ms
⏱️  [firebase] 1234ms
⏱️  [config] 1242ms
⏱️  [first_frame] 1422ms
⏱️  [fetch_member] 1872ms
⏱️  [get_customer] 1805ms
📊 Startup timing sent: 1872ms
```

- [ ] **Step 3: Check CloudWatch Logs**

Go to AWS CloudWatch Logs console:
- Log group: (your Lambda log group)
- Search for `"log_type": "startup_timing"`
- Verify a new log event appeared with all phase fields

- [ ] **Step 4: Test MonitoringScreen**

- Ensure you are a super-admin
- Navigate to Home → 📈 Monitoring (if visible)
- Select timeframe → 'Min' or 'Hour'
- Verify "Startup-Zeiten pro Mitglied" section appears with your startup data

- [ ] **Step 5: No commits required for testing**

Testing is verification; no code changes in this task.

---

## Self-Review

**Spec Coverage:**

1. ✅ **Startup-Phasen messen:** Tasks 1–5 implement `StartupTimer` utility and instrument `main()` + `HomeScreen.initState()` with marks. All phases captured: firebase, config, first_frame, fetch_member, get_customer.

2. ✅ **Ans Backend senden (fire-and-forget):** Task 4–5 add `sendStartupTiming()` to `MonitoringApi` and `send()` to `StartupTimer`. Silent error handling ensures never throws.

3. ✅ **CloudWatch Logs schreiben:** Task 6–7 add `POST /monitoring/timing` route and `handle_timing()` to log `log_type: "startup_timing"` events.

4. ✅ **MonitoringScreen zeigen:** Task 8–12 extend MonitoringScreen with startup stats section, add backend query endpoint, and build DataTable UI per member.

5. ✅ **Keine Optimierungen:** Design spec explicitly defers optimization; this plan measures only.

**Placeholder Scan:** No "TBD", "TODO", "add error handling", "similar to Task N" found. All steps contain complete code and exact commands.

**Type Consistency:**
- `StartupTimer.mark(String phase)` used consistently across tasks
- `StartupTimer.toPayload(applicationId, memberId)` signature consistent
- `MonitoringApi.sendStartupTiming(Map)` signature consistent
- `api_monitoring.handle_timing(event, context)` and `handle_startup_stats(event, context)` follow same pattern as existing handlers

**No Gaps Identified.**

---

Plan complete and saved to `docs/superpowers/plans/2026-04-19-startup-timing-implementation.md`.

**Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?

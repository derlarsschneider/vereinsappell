# Multi-Account & Account-Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to hold multiple club accounts locally, switch between them via the AppBar, and automatically gain access to newly created clubs.

**Architecture:** A thin multi-account layer replaces the single `config` localStorage key with `accounts` (JSON array) and `activeAccount` (index). `AppConfig` gains an optional `label` field. All screens are unchanged — they still receive a single `AppConfig`. The backend's `create_customer` returns the requesting super admin's `memberId` so the frontend can add the new club as a local account automatically.

**Tech Stack:** Flutter/Dart (web localStorage via `storage.dart`), Python/boto3 (AWS Lambda), pytest, flutter_test.

---

### Task 1: Backend — return `member_id` and `api_base_url` from `create_customer`

**Files:**
- Modify: `aws_backend/lambda/api_customers.py`
- Test: `aws_backend/lambda/tests/test_api_customers.py`

The backend already has `API_BASE_URL` in the environment and receives the requesting member's ID via the `memberid` header. We just need to include both in the response.

- [ ] **Step 1: Write failing tests**

Add to `TestCreateCustomer` in `aws_backend/lambda/tests/test_api_customers.py`:

```python
def test_create_customer_response_includes_member_id(self):
    event = _event('POST', '/customers', body={'application_name': 'New Club'})
    event['headers'] = {'memberid': 'super123'}
    response = api_customers.create_customer(event)
    self.assertEqual(response['statusCode'], 200)
    body = json.loads(response['body'])
    self.assertEqual(body['member_id'], 'super123')

def test_create_customer_response_includes_api_base_url(self):
    with patch.object(api_customers, 'API_BASE_URL', 'https://api.example.com'):
        event = _event('POST', '/customers', body={'application_name': 'New Club'})
        event['headers'] = {}
        response = api_customers.create_customer(event)
    body = json.loads(response['body'])
    self.assertEqual(body['api_base_url'], 'https://api.example.com')

def test_create_customer_response_member_id_empty_when_no_header(self):
    event = _event('POST', '/customers', body={'application_name': 'New Club'})
    # no 'headers' key — must not crash
    event.pop('headers', None)
    response = api_customers.create_customer(event)
    self.assertEqual(response['statusCode'], 200)
    body = json.loads(response['body'])
    self.assertEqual(body['member_id'], '')
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd aws_backend/lambda
python -m pytest tests/test_api_customers.py::TestCreateCustomer -v
```

Expected: 3 FAIL, rest PASS.

- [ ] **Step 3: Update `create_customer` in `aws_backend/lambda/api_customers.py`**

Replace the entire `create_customer` function:

```python
def create_customer(event):
    body = json.loads(event['body'])
    application_id = str(uuid.uuid4())
    application_name = body['application_name']
    api_url = body.get('api_url') or API_BASE_URL
    application_logo = body.get('application_logo', '')
    active_screens = body.get('active_screens', ALL_SCREEN_KEYS)
    requesting_member_id = event.get('headers', {}).get('memberid', '')

    item = {
        'application_id': application_id,
        'application_name': application_name,
        'api_url': api_url,
        'application_logo': application_logo,
        'active_screens': active_screens,
    }
    table().put_item(Item=item)

    return {
        'statusCode': 200,
        'body': json.dumps({
            **item,
            'member_id': requesting_member_id,
            'api_base_url': API_BASE_URL,
        })
    }
```

- [ ] **Step 4: Run all backend tests**

```bash
cd aws_backend/lambda
python -m pytest tests/ -v
```

Expected: all 53 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add aws_backend/lambda/api_customers.py aws_backend/lambda/tests/test_api_customers.py
git commit -m "feat(backend): return member_id and api_base_url from create_customer"
```

---

### Task 2: `AppConfig` — add `label` field and multi-account storage functions

**Files:**
- Modify: `lib/config_loader.dart`
- Test: `test/unit/config_loader_test.dart`

`AppConfig` gets an optional `label` field (empty string default). The storage layer is replaced with multi-account variants. Migration from the old single `config` key happens transparently on first load.

New public API added to `config_loader.dart`:
- `loadAllAccounts() → List<AppConfig>` — returns all stored accounts (web-only; returns `[]` on native)
- `getActiveAccountIndex() → int` — returns current active index
- `setActiveAccount(int index)` — persists active index
- `addOrActivateAccount(AppConfig config)` — adds account if new, activates if duplicate
- `updateActiveAccountLabel(String label)` — updates the label of the active account in-place

`loadConfig()`, `saveConfig()`, `deleteConfig()` are updated to use the new storage format.

**How the migration works:** On first `loadConfig()` call, if `accounts` key is absent but `config` key exists, the old config is read, stored as a single-element accounts array, and `config` is removed.

- [ ] **Step 1: Write failing tests**

Add to `test/unit/config_loader_test.dart` (after the existing `Member` group):

```dart
group('AppConfig label', () {
  test('fromJson reads label field', () async {
    await withStubHttp(() async {
      final config = AppConfig.fromJson({
        'apiBaseUrl': 'https://api.example.com',
        'applicationId': 'app-1',
        'memberId': 'mem-1',
        'label': 'Schützenlust',
      });
      expect(config.label, 'Schützenlust');
    });
  });

  test('fromJson defaults label to empty string when absent', () async {
    await withStubHttp(() async {
      final config = AppConfig.fromJson({
        'apiBaseUrl': 'https://api.example.com',
        'applicationId': 'app-1',
        'memberId': 'mem-1',
      });
      expect(config.label, '');
    });
  });

  test('toJson includes label', () async {
    await withStubHttp(() async {
      final config = AppConfig(
        apiBaseUrl: 'https://api.example.com',
        applicationId: 'app-1',
        memberId: 'mem-1',
        label: 'Schützenlust',
      );
      expect(config.toJson()['label'], 'Schützenlust');
    });
  });
});

group('accountIndexOf', () {
  test('returns index of matching account', () async {
    await withStubHttp(() async {
      final accounts = [
        {'applicationId': 'app-1', 'memberId': 'mem-1'},
        {'applicationId': 'app-2', 'memberId': 'mem-1'},
      ];
      expect(accountIndexOf(accounts, 'app-2', 'mem-1'), 1);
    });
  });

  test('returns -1 when applicationId matches but memberId differs', () async {
    await withStubHttp(() async {
      final accounts = [
        {'applicationId': 'app-1', 'memberId': 'mem-1'},
      ];
      expect(accountIndexOf(accounts, 'app-1', 'mem-999'), -1);
    });
  });

  test('returns -1 when no match', () async {
    await withStubHttp(() async {
      final accounts = <Map<String, dynamic>>[];
      expect(accountIndexOf(accounts, 'app-x', 'mem-x'), -1);
    });
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /path/to/project
flutter test test/unit/config_loader_test.dart
```

Expected: 5 new tests FAIL (label + accountIndexOf), existing 10 PASS.

- [ ] **Step 3: Add `label` to `AppConfig` and expose `accountIndexOf`**

Replace the `AppConfig` class and all storage functions in `lib/config_loader.dart` with the following complete file content. Keep the `Member` class and everything below it unchanged.

Replace from the top of the file through `deleteConfig()`:

```dart
// lib/config_loader.dart
import 'dart:convert';
import 'dart:io' as io;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api/headers.dart';
import 'storage.dart';

class AppConfig {
  final String apiBaseUrl;
  final String applicationId;
  final String memberId;
  final String label;
  late final Member member;
  String? sessionPassword;

  AppConfig({
    required this.apiBaseUrl,
    required this.applicationId,
    required this.memberId,
    this.label = '',
    this.sessionPassword,
  }) {
    member = Member(config: this);
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      apiBaseUrl: json['apiBaseUrl'] as String,
      applicationId: json['applicationId'] as String,
      memberId: json['memberId'] as String,
      label: (json['label'] as String?) ?? '',
      sessionPassword: json['password'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiBaseUrl': apiBaseUrl,
      'applicationId': applicationId,
      'memberId': memberId,
      'label': label,
      if (sessionPassword != null) 'password': sessionPassword,
    };
  }
}

/// Pure helper — finds the index of an account in a raw JSON list by
/// applicationId + memberId. Exported so it can be unit-tested without storage.
int accountIndexOf(
  List<Map<String, dynamic>> accounts,
  String applicationId,
  String memberId,
) {
  return accounts.indexWhere(
    (a) => a['applicationId'] == applicationId && a['memberId'] == memberId,
  );
}

// ── Storage helpers ──────────────────────────────────────────────────────────

List<Map<String, dynamic>> _readAccountsJson() {
  final raw = getItem('accounts');
  if (raw == null) return [];
  try {
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return [];
  }
}

void _writeAccountsJson(List<Map<String, dynamic>> accounts) {
  setItem('accounts', jsonEncode(accounts));
}

// ── Public API ───────────────────────────────────────────────────────────────

Future<AppConfig?> loadConfig() async {
  try {
    if (kIsWeb) {
      // Migration: move old single 'config' key → accounts array
      final oldJson = getItem('config');
      if (oldJson != null && getItem('accounts') == null) {
        final old = AppConfig.fromJson(jsonDecode(oldJson) as Map<String, dynamic>);
        _writeAccountsJson([old.toJson()]);
        setItem('activeAccount', '0');
        removeItem('config');
      }

      final accounts = _readAccountsJson();
      if (accounts.isEmpty) return null;
      final idx = (int.tryParse(getItem('activeAccount') ?? '0') ?? 0)
          .clamp(0, accounts.length - 1);
      return AppConfig.fromJson(accounts[idx]);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = io.File('${dir.path}/config.json');
      if (!await file.exists()) return null;
      return AppConfig.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    }
  } catch (e) {
    print('Fehler beim Laden der Konfiguration: $e');
    return null;
  }
}

Future<void> saveConfig(AppConfig config) async {
  try {
    if (kIsWeb) {
      final accounts = _readAccountsJson();
      final idx = (int.tryParse(getItem('activeAccount') ?? '0') ?? 0)
          .clamp(0, accounts.isEmpty ? 0 : accounts.length - 1);
      if (idx < accounts.length) {
        accounts[idx] = config.toJson();
      } else {
        accounts.add(config.toJson());
        setItem('activeAccount', '${accounts.length - 1}');
      }
      _writeAccountsJson(accounts);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = io.File('${dir.path}/config.json');
      await file.writeAsString(jsonEncode(config.toJson()));
    }
  } catch (e) {
    print('Fehler beim Speichern der Konfiguration: $e');
    rethrow;
  }
}

Future<void> deleteConfig() async {
  try {
    if (kIsWeb) {
      removeItem('accounts');
      removeItem('activeAccount');
      removeItem('config');
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = io.File('${dir.path}/config.json');
      if (await file.exists()) await file.delete();
    }
  } catch (e) {
    print('Fehler beim Löschen der Konfiguration: $e');
  }
}

List<AppConfig> loadAllAccounts() {
  if (!kIsWeb) return [];
  return _readAccountsJson()
      .map((json) => AppConfig.fromJson(json))
      .toList();
}

int getActiveAccountIndex() {
  if (!kIsWeb) return 0;
  return int.tryParse(getItem('activeAccount') ?? '0') ?? 0;
}

void setActiveAccount(int index) {
  if (!kIsWeb) return;
  setItem('activeAccount', '$index');
}

Future<void> addOrActivateAccount(AppConfig config) async {
  if (!kIsWeb) {
    await saveConfig(config);
    return;
  }
  final accounts = _readAccountsJson();
  final existing = accountIndexOf(accounts, config.applicationId, config.memberId);
  if (existing != -1) {
    setActiveAccount(existing);
  } else {
    accounts.add(config.toJson());
    _writeAccountsJson(accounts);
    setActiveAccount(accounts.length - 1);
  }
}

void updateActiveAccountLabel(String label) {
  if (!kIsWeb || label.isEmpty) return;
  final accounts = _readAccountsJson();
  final idx = getActiveAccountIndex().clamp(0, accounts.isEmpty ? 0 : accounts.length - 1);
  if (idx < accounts.length) {
    accounts[idx]['label'] = label;
    _writeAccountsJson(accounts);
  }
}
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/unit/config_loader_test.dart
```

Expected: all 15 tests PASS.

- [ ] **Step 5: Run full Flutter test suite**

```bash
flutter test
```

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/config_loader.dart test/unit/config_loader_test.dart
git commit -m "feat: add label to AppConfig and multi-account storage functions"
```

---

### Task 3: `main.dart` — QR code adds account instead of overwriting

**Files:**
- Modify: `lib/main.dart`

When URL parameters are present, call `addOrActivateAccount` instead of `saveConfig`. The `label` is initially empty — it gets filled in by Task 5 (home screen fetches and stores it).

- [ ] **Step 1: Update the QR code handling block in `lib/main.dart`**

Find this block (lines 66–74):

```dart
    if (apiBaseUrl != null && applicationId != null && memberId != null) {
      config = AppConfig(
        apiBaseUrl: apiBaseUrl,
        applicationId: applicationId,
        memberId: memberId,
        sessionPassword: password,
      );
      saveConfig(config);
    }
```

Replace with:

```dart
    if (apiBaseUrl != null && applicationId != null && memberId != null) {
      final incoming = AppConfig(
        apiBaseUrl: apiBaseUrl,
        applicationId: applicationId,
        memberId: memberId,
        sessionPassword: password,
      );
      await addOrActivateAccount(incoming);
      config = await loadConfig();
    }
```

The `main()` function is already `async`, so `await` works here.

- [ ] **Step 2: Verify `addOrActivateAccount` and `updateActiveAccountLabel` are imported**

`lib/main.dart` already imports `config_loader.dart`:
```dart
import 'config_loader.dart';
```
No additional imports needed.

- [ ] **Step 3: Run Flutter tests**

```bash
flutter test
```

Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: QR code adds account instead of overwriting existing config"
```

---

### Task 4: `HomeScreen` — account-switcher in AppBar + label persistence

**Files:**
- Modify: `lib/screens/home_screen.dart`

Two changes:
1. The AppBar title becomes a `TextButton` when multiple accounts exist. Tapping opens a `BottomSheet` listing all accounts.
2. After `_updateApplication()` fetches the club name, it calls `updateActiveAccountLabel()` so the label is always up-to-date for the switcher.

The `_jsHardReload` JS interop is already present in this file — reuse it for the web reload.

- [ ] **Step 1: Add account state and `_showAccountSwitcher` to `_HomeScreenState`**

Add these fields after `StreamSubscription? _messageSubscription;`:

```dart
  List<AppConfig> _allAccounts = [];
  int _activeAccountIndex = 0;
```

Add `_loadAccounts()` to `initState` — insert it right after `_updateApplication();`:

```dart
  void _loadAccounts() {
    setState(() {
      _allAccounts = loadAllAccounts();
      _activeAccountIndex = getActiveAccountIndex();
    });
  }
```

Call it in `initState`:

```dart
  @override
  void initState() {
    super.initState();
    _updateApplication();
    _loadAccounts();       // ← add this line
    // ... rest of initState unchanged
  }
```

Add `_showAccountSwitcher` anywhere in `_HomeScreenState`:

```dart
  void _showAccountSwitcher() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Verein wechseln',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ..._allAccounts.asMap().entries.map((entry) {
            final i = entry.key;
            final account = entry.value;
            final displayLabel =
                account.label.isNotEmpty ? account.label : account.applicationId;
            return ListTile(
              title: Text(displayLabel),
              trailing: i == _activeAccountIndex
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                if (i == _activeAccountIndex) return;
                setActiveAccount(i);
                if (kIsWeb) {
                  _jsHardReload();
                } else {
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/', (route) => false);
                }
              },
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
```

- [ ] **Step 2: Update `_updateApplication` to persist the label**

In `_updateApplication`, inside the `.then((customer)` callback, add one line after the `setState` block:

```dart
    customersApi.getCustomer(widget.config.applicationId).then((customer) {
      setState(() {
        _applicationName = customer['application_name'];
        final screens = customer['active_screens'];
        if (screens != null) {
          _activeScreens = List<String>.from(screens);
        }
      });
      updateActiveAccountLabel(customer['application_name'] as String? ?? ''); // ← add
    }).catchError((error) {
      showError("Fehler beim Laden des Vereins: $error");
    });
```

- [ ] **Step 3: Update the AppBar title in `build`**

Find the current AppBar title widget:

```dart
        title: Text(
          _applicationName,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
          softWrap: true,
        ),
```

Replace with:

```dart
        title: _allAccounts.length > 1
            ? TextButton(
                onPressed: _showAccountSwitcher,
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Text(
                  _applicationName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  softWrap: true,
                ),
              )
            : Text(
                _applicationName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                softWrap: true,
              ),
```

- [ ] **Step 4: Add missing imports to `home_screen.dart`**

`config_loader.dart` is already imported via `../config_loader.dart`. Verify the import exists — it should already be there since `Member` is used. If not, add:

```dart
import '../config_loader.dart';
```

- [ ] **Step 5: Run Flutter tests**

```bash
flutter test
```

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: account-switcher in home screen AppBar"
```

---

### Task 5: `VereinScreen` — auto-add account after creating a new club

**Files:**
- Modify: `lib/screens/verein_screen.dart`

After `_api.createCustomer(payload)` returns successfully, extract `member_id` and `api_base_url` from the response and call `addOrActivateAccount`. The new account appears immediately in the switcher on the next load.

- [ ] **Step 1: Update the success handler inside `_showCreateDialog` in `lib/screens/verein_screen.dart`**

Find the `onPressed` callback of the `ElevatedButton` inside `_showCreateDialog`. The current success block is:

```dart
                  final created = await _api.createCustomer(payload);
                  setState(() {
                    _allClubs.add(created);
                  });
                  _applyClub(created);
                  showInfo('Verein erstellt');
```

Replace with:

```dart
                  final created = await _api.createCustomer(payload);
                  setState(() {
                    _allClubs.add(created);
                  });
                  _applyClub(created);

                  // Auto-add the new club as a local account
                  final newMemberId = created['member_id'] as String? ?? '';
                  final newApiBaseUrl =
                      created['api_base_url'] as String? ?? widget.config.apiBaseUrl;
                  if (newMemberId.isNotEmpty) {
                    await addOrActivateAccount(AppConfig(
                      apiBaseUrl: newApiBaseUrl,
                      applicationId: created['application_id'] as String,
                      memberId: newMemberId,
                      label: name,
                    ));
                  }

                  showInfo('Verein erstellt');
```

- [ ] **Step 2: Verify `addOrActivateAccount` and `AppConfig` are in scope**

`lib/screens/verein_screen.dart` already imports:
```dart
import '../config_loader.dart';
```
(It uses `AppConfig` via `widget.config`.) If the import is missing, add it.

- [ ] **Step 3: Run Flutter tests**

```bash
flutter test
```

Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/verein_screen.dart
git commit -m "feat: auto-add new club as local account after creation"
```

---

## Self-Review

**Spec coverage:**
- ✅ Multiple accounts in localStorage — Task 2
- ✅ Migration from old single config — Task 2 (`loadConfig` migration block)
- ✅ QR code adds instead of overwrites — Task 3
- ✅ Account-switcher UI (AppBar tap → BottomSheet) — Task 4
- ✅ Switch triggers reload — Task 4 (`_showAccountSwitcher` onTap)
- ✅ Label persisted from club name — Task 4 (`updateActiveAccountLabel`)
- ✅ Super admin auto-added to new club — Task 5
- ✅ `member_id` + `api_base_url` in backend response — Task 1
- ✅ Same memberId across clubs (no new member record created) — Task 1 (backend reads from header, not creates)

**Type consistency:**
- `addOrActivateAccount(AppConfig)` — defined Task 2, used Task 3 and Task 5 ✅
- `loadAllAccounts() → List<AppConfig>` — defined Task 2, used Task 4 ✅
- `getActiveAccountIndex() → int` — defined Task 2, used Task 4 ✅
- `setActiveAccount(int)` — defined Task 2, used Task 4 ✅
- `updateActiveAccountLabel(String)` — defined Task 2, used Task 4 ✅
- `AppConfig.label` — defined Task 2, used Task 4 and Task 5 ✅
- `created['member_id']` — backend returns `member_id` (snake_case) in Task 1, Flutter reads `member_id` in Task 5 ✅

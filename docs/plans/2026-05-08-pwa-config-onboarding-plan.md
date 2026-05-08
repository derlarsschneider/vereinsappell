# PWA Config Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to configure the app after installing it as a PWA on iOS or Android, where the browser's localStorage is not shared with the installed PWA.

**Architecture:** Extract URL-parsing logic into a testable top-level function `parseInviteLink`. Update the web login form: add an "Einladungslink einfügen" field that auto-fills the four config fields on change, add a camera QR-scan button (MobileScanner widget works on web via WebRTC), and remove the broken "QR-Code aus Bild laden" button (calls `analyzeImage`, unsupported on web). Move the `if (scanning)` branch above the `if (kIsWeb)` guard so the camera scanner is reachable on web.

**Tech Stack:** Flutter/Dart, `mobile_scanner` ^7.0.1 (already in use), `flutter_test`

---

## File map

- Modify: `lib/screens/config_missing_screen.dart`
- Create: `test/unit/config_missing_screen_test.dart`

---

### Task 1: Extract and test `parseInviteLink`

**Files:**
- Modify: `lib/screens/config_missing_screen.dart`
- Create: `test/unit/config_missing_screen_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/unit/config_missing_screen_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/screens/config_missing_screen.dart';

void main() {
  group('parseInviteLink', () {
    test('parses all four params from a full URL', () {
      final result = parseInviteLink(
        'https://app.example.com/?apiBaseUrl=https%3A%2F%2Fapi.example.com&applicationId=app-1&memberId=mem-1&password=secret',
      );
      expect(result['apiBaseUrl'], 'https://api.example.com');
      expect(result['applicationId'], 'app-1');
      expect(result['memberId'], 'mem-1');
      expect(result['password'], 'secret');
    });

    test('returns only present params — no password key when absent', () {
      final result = parseInviteLink(
        'https://app.example.com/?apiBaseUrl=https%3A%2F%2Fapi.example.com&applicationId=app-1&memberId=mem-1',
      );
      expect(result['apiBaseUrl'], 'https://api.example.com');
      expect(result['applicationId'], 'app-1');
      expect(result['memberId'], 'mem-1');
      expect(result.containsKey('password'), false);
    });

    test('returns empty map for non-URL input', () {
      expect(parseInviteLink('not a url'), isEmpty);
    });

    test('returns empty map for URL missing required params', () {
      expect(parseInviteLink('https://app.example.com/'), isEmpty);
    });

    test('returns empty map for empty string', () {
      expect(parseInviteLink(''), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/unit/config_missing_screen_test.dart
```

Expected: compile error — `parseInviteLink` not exported from `config_missing_screen.dart`.

- [ ] **Step 3: Add `parseInviteLink` as a top-level function**

In `lib/screens/config_missing_screen.dart`, add this function before the `class ConfigMissingScreen` declaration:

```dart
Map<String, String> parseInviteLink(String text) {
  final Uri? uri = Uri.tryParse(text.trim());
  if (uri == null) return {};
  final p = uri.queryParameters;
  if (!p.containsKey('apiBaseUrl') ||
      !p.containsKey('applicationId') ||
      !p.containsKey('memberId')) {
    return {};
  }
  return {
    'apiBaseUrl': p['apiBaseUrl']!,
    'applicationId': p['applicationId']!,
    'memberId': p['memberId']!,
    if (p.containsKey('password')) 'password': p['password']!,
  };
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/unit/config_missing_screen_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/screens/config_missing_screen.dart test/unit/config_missing_screen_test.dart
git commit -m "feat: extract parseInviteLink with unit tests"
```

---

### Task 2: Update web form — invite-link field + camera scan button

**Files:**
- Modify: `lib/screens/config_missing_screen.dart`

**Context:** The current `build()` has three branches in this order:
1. `if (kIsWeb)` → returns early with text fields + broken image picker
2. `if (scanning)` → returns MobileScanner (unreachable on web due to branch 1)
3. else → native form

This task: add `_inviteLinkController` + `_applyInviteLink`, then replace `build()` with a version that checks `scanning` first (so it works on all platforms), adds the invite-link field to the web form, adds a camera scan button on web, and removes the `pickImageAndScanQR` button on web.

- [ ] **Step 1: Add controller and `_applyInviteLink` method**

In `_ConfigMissingScreenState`, add the controller alongside the existing four:

```dart
final _inviteLinkController = TextEditingController();
```

In `dispose()`, add:

```dart
_inviteLinkController.dispose();
```

Add the handler method to `_ConfigMissingScreenState`:

```dart
void _applyInviteLink(String text) {
  final parsed = parseInviteLink(text);
  if (parsed.isEmpty) return;
  setState(() {
    _apiBaseUrlController.text = parsed['apiBaseUrl']!;
    _applicationIdController.text = parsed['applicationId']!;
    _memberIdController.text = parsed['memberId']!;
    _passwordController.text = parsed['password'] ?? '';
  });
}
```

- [ ] **Step 2: Replace `build()` with the final version**

Replace the entire `build()` method with:

```dart
@override
Widget build(BuildContext context) {
  if (scanning) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR-Code scannen')),
      body: MobileScanner(
        controller: cameraController,
        onDetect: (capture) {
          final barcode = capture.barcodes.first;
          final String? code = barcode.rawValue;
          if (code != null) {
            cameraController.stop();
            handleQRCode(code);
          }
        },
      ),
    );
  }

  if (kIsWeb) {
    return Scaffold(
      appBar: AppBar(title: const Text('Web-Anmeldung')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _inviteLinkController,
              decoration: const InputDecoration(labelText: 'Einladungslink einfügen'),
              onChanged: _applyInviteLink,
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            TextField(
              controller: _apiBaseUrlController,
              decoration: const InputDecoration(labelText: 'API Base URL'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _applicationIdController,
              decoration: const InputDecoration(labelText: 'Application ID'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _memberIdController,
              decoration: const InputDecoration(labelText: 'Member ID'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Passwort'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: handleLogin,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
              child: const Text('🔐 Anmelden', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: startQRScan,
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
              child: const Text('📷 QR-Code scannen', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }

  return Scaffold(
    appBar: AppBar(title: const Text('Willkommen')),
    body: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('⚙️ Keine Konfiguration gefunden',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => CreateVereinScreen()));
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
            child: const Text('🆕 Neuen Verein anlegen', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: startQRScan,
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
            child: const Text('📷 Einem Verein beitreten', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: pickImageAndScanQR,
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
            child: const Text('🖼️ QR-Code aus Bild', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 3: Manual test — invite-link field (Chrome)**

```bash
flutter run -d chrome
```

Navigate to the config screen. Paste a URL into the top field:

```
https://whatever/?apiBaseUrl=https%3A%2F%2Fapi.test&applicationId=app-1&memberId=mem-1&password=pw
```

Expected: the four fields below fill automatically.

- [ ] **Step 4: Manual test — camera QR scan on web (Chrome)**

Still running in Chrome. Tap "📷 QR-Code scannen". Browser requests camera permission. Accept. Camera preview appears. Hold a valid config QR code up to the camera.

Expected: app parses QR code and navigates to `HomeScreen`.

- [ ] **Step 5: Manual test — native form unchanged**

```bash
flutter run -d <android-or-ios-device>
```

Expected: native form shows "Neuen Verein anlegen", "Einem Verein beitreten", and "QR-Code aus Bild". No regression.

- [ ] **Step 6: Run unit tests**

```bash
flutter test test/unit/
```

Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
git add lib/screens/config_missing_screen.dart
git commit -m "feat: add invite-link field and camera QR scan to web login form"
```

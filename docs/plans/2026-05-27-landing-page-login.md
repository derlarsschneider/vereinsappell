# Landing Page Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a collapsible username/password login section to the landing page so iOS users who lost their localStorage can get back into the app in 1–2 clicks.

**Architecture:** Username = `applicationId`, Password = `memberId`. No backend changes. The submit handler constructs the full invite URL with the hardcoded prod `apiBaseUrl` and navigates to it, triggering the existing Flutter load. A short re-invite link (`?applicationId=X&memberId=Y`) pre-fills and auto-expands the form. The Flutter app gains a "Mein Zugang" tile in the account switcher to let users copy their credentials proactively.

**Tech Stack:** Vanilla JS + HTML/CSS (landing page), Flutter/Dart + `flutter/services.dart` Clipboard (app)

---

## File Map

| File | Change |
|------|--------|
| `web/index.html` | CSS + HTML login section + JS functions + pre-fill logic |
| `web/index-a.html` | Identical to index.html changes |
| `web/index-c.html` | Identical to index.html changes |
| `lib/screens/home_screen.dart` | "Mein Zugang" tile in `_showAccountSwitcher()` bottom sheet |

---

## Task 1: CSS for collapsible login section (index.html)

**Files:**
- Modify: `web/index.html` (inside the `<style>` block, before `</style>`)

- [ ] **Add CSS** — paste before the closing `</style>` tag:

```css
    .lp-login{background:#fff;border-radius:10px;box-shadow:0 1px 4px rgba(0,0,0,.06);margin-bottom:14px;overflow:hidden}
    .lp-login-hd{display:flex;align-items:center;gap:8px;padding:12px 16px;cursor:pointer;user-select:none;font-size:12px;font-weight:600;color:#444}
    .lp-login-hd:hover{background:#f9fafb}
    .lp-chevron{color:#2d6a2d;font-size:10px;transition:transform .2s;line-height:1}
    .lp-chevron.open{transform:rotate(90deg)}
    .lp-login-bd{display:none;padding:0 16px 14px}
    .lp-login-row{display:flex;gap:8px;flex-wrap:wrap}
    .lp-login-row input{flex:1;min-width:120px;border:1.5px solid #ddd;border-radius:8px;padding:10px 12px;font-size:16px;outline:none;font-family:inherit}
    .lp-login-row input:focus{border-color:#2d6a2d}
    .lp-login-row button{background:#2d6a2d;color:#fff;border:none;border-radius:8px;padding:10px 18px;font-size:16px;cursor:pointer;font-weight:700}
    .lp-prefill-note{font-size:11px;color:#2d6a2d;margin-top:6px}
```

- [ ] **Commit**

```bash
git add web/index.html
git commit -m "style: add collapsible login section CSS to index.html"
```

---

## Task 2: HTML login section (index.html)

**Files:**
- Modify: `web/index.html` — insert after the `<div class="lp-hint">...</div>` block (line ~233) and before the first `<div class="lp-ad">` block

- [ ] **Add HTML** — insert after the closing `</div>` of `lp-hint`:

```html
    <div class="lp-login">
      <div class="lp-login-hd" onclick="toggleLogin()">
        <span class="lp-chevron" id="login-chevron">▶</span>
        <span>Bereits registriert?</span>
      </div>
      <div class="lp-login-bd" id="login-body">
        <div class="lp-login-row">
          <input id="login-user" type="text" placeholder="Benutzername" autocomplete="username">
          <input id="login-pass" type="password" placeholder="Passwort" autocomplete="current-password">
          <button onclick="submitLogin()">→</button>
        </div>
        <div id="login-msg" class="lp-msg"></div>
        <div id="login-prefill-note" class="lp-prefill-note" style="display:none">✓ Vom Einladungslink vorausgefüllt</div>
      </div>
    </div>
```

- [ ] **Commit**

```bash
git add web/index.html
git commit -m "feat: add collapsible login section HTML to index.html"
```

---

## Task 3: JavaScript login functions (index.html)

**Files:**
- Modify: `web/index.html` — add functions inside the existing `<script>` block that contains `openModal`/`closeModal` (around line ~455)

- [ ] **Add JS functions** — paste before the closing `</script>` of the modal script block:

```javascript
  function toggleLogin() {
    const body = document.getElementById('login-body');
    const chevron = document.getElementById('login-chevron');
    const isOpen = body.style.display === 'block';
    body.style.display = isOpen ? 'none' : 'block';
    chevron.classList.toggle('open', !isOpen);
  }

  function submitLogin() {
    const user = document.getElementById('login-user').value.trim();
    const pass = document.getElementById('login-pass').value.trim();
    if (!user || !pass) {
      showMsg('login-msg', 'Bitte Benutzername und Passwort eingeben.', false);
      return;
    }
    const p = new URLSearchParams(window.location.search);
    const apiBaseUrl = p.get('apiBaseUrl') || 'https://v49kyt4758.execute-api.eu-central-1.amazonaws.com';
    window.location.href = '/?apiBaseUrl=' + encodeURIComponent(apiBaseUrl) +
      '&applicationId=' + encodeURIComponent(user) +
      '&memberId=' + encodeURIComponent(pass);
  }
```

- [ ] **Commit**

```bash
git add web/index.html
git commit -m "feat: add toggleLogin and submitLogin JS functions to index.html"
```

---

## Task 4: Pre-fill logic on page load (index.html)

**Files:**
- Modify: `web/index.html` — inside the `DOMContentLoaded` handler, in the `else` branch (where `lp` is shown)

- [ ] **Add pre-fill** — inside the `else` branch, after `document.getElementById('lp').style.display = 'block';`, add:

```javascript
      // Pre-fill login form if applicationId + memberId are in the URL
      (function () {
        const loginUser = p.get('applicationId');
        const loginPass = p.get('memberId');
        if (loginUser && loginPass) {
          document.getElementById('login-user').value = loginUser;
          document.getElementById('login-pass').value = loginPass;
          document.getElementById('login-body').style.display = 'block';
          document.getElementById('login-chevron').classList.add('open');
          document.getElementById('login-prefill-note').style.display = 'block';
        }
      })();
```

- [ ] **Manual test** — open `web/index.html` locally (or via `flutter run -d chrome`) and verify:
  - Page without params: login section visible but collapsed
  - Click "Bereits registriert?": fields expand, chevron rotates
  - Click again: fields collapse
  - Page with `?applicationId=abc&memberId=xyz`: fields pre-filled and expanded, note visible
  - Submit with empty fields: error message appears
  - Submit with values: navigates to `/?apiBaseUrl=...&applicationId=abc&memberId=xyz`

- [ ] **Commit**

```bash
git add web/index.html
git commit -m "feat: pre-fill login form from URL params in index.html"
```

---

## Task 5: Apply all changes to index-a.html

**Files:**
- Modify: `web/index-a.html` — same four changes as Tasks 1–4

- [ ] **Add CSS** — same block as Task 1, paste before `</style>` in `index-a.html`

- [ ] **Add HTML** — same block as Task 2, insert after `lp-hint` closing div in `index-a.html`

- [ ] **Add JS functions** — same block as Task 3, add to the modal script block in `index-a.html`

- [ ] **Add pre-fill** — same block as Task 4, add to the `else` branch in `index-a.html`

- [ ] **Commit**

```bash
git add web/index-a.html
git commit -m "feat: add collapsible login section to index-a.html"
```

---

## Task 6: Apply all changes to index-c.html

**Files:**
- Modify: `web/index-c.html` — same four changes as Tasks 1–4

- [ ] **Add CSS** — same block as Task 1, paste before `</style>` in `index-c.html`

- [ ] **Add HTML** — same block as Task 2, insert after `lp-hint` closing div in `index-c.html`

- [ ] **Add JS functions** — same block as Task 3, add to the modal script block in `index-c.html`

- [ ] **Add pre-fill** — same block as Task 4, add to the `else` branch in `index-c.html`

- [ ] **Commit**

```bash
git add web/index-c.html
git commit -m "feat: add collapsible login section to index-c.html"
```

---

## Task 7: "Mein Zugang" tile in Flutter account switcher

**Files:**
- Modify: `lib/screens/home_screen.dart`

The account switcher bottom sheet is built in `_showAccountSwitcher()` (line ~141). Add a "Mein Zugang" `ListTile` at the bottom of the sheet's `Column`, after the existing account tiles.

- [ ] **Add import** — `dart:io` is already imported conditionally; verify `flutter/services.dart` is imported (add if missing):

```dart
import 'package:flutter/services.dart';
```

- [ ] **Add `_showCredentials()` method** — add after `_showAccountSwitcher()`:

```dart
  void _showCredentials() {
    final appId = widget.config.applicationId;
    final memId = widget.config.memberId;
    final shortLink = 'https://vereinsappell.web.app/?applicationId=${Uri.encodeComponent(appId)}&memberId=${Uri.encodeComponent(memId)}';
    bool memIdVisible = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateSheet) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mein Zugang', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _credentialRow(
                label: 'Benutzername',
                value: appId,
                obscure: false,
                onCopy: () => Clipboard.setData(ClipboardData(text: appId)),
                onToggle: null,
                visible: true,
              ),
              const SizedBox(height: 10),
              _credentialRow(
                label: 'Passwort',
                value: memId,
                obscure: !memIdVisible,
                onCopy: () => Clipboard.setData(ClipboardData(text: memId)),
                onToggle: () => setStateSheet(() => memIdVisible = !memIdVisible),
                visible: memIdVisible,
              ),
              const SizedBox(height: 10),
              _credentialRow(
                label: 'Kurzlink',
                value: shortLink,
                obscure: false,
                onCopy: () => Clipboard.setData(ClipboardData(text: shortLink)),
                onToggle: null,
                visible: true,
              ),
              const SizedBox(height: 8),
              Text(
                'Speichere diese Daten — du brauchst sie wenn die App zurückgesetzt wird.',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _credentialRow({
    required String label,
    required String value,
    required bool obscure,
    required Future<void> Function()? onCopy,
    required VoidCallback? onToggle,
    required bool visible,
  }) {
    final display = obscure ? '•' * 12 : value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                display,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onToggle != null)
              IconButton(
                icon: Icon(visible ? Icons.visibility_off : Icons.visibility, size: 18),
                onPressed: onToggle,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: onCopy == null ? null : () async {
                await onCopy();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$label kopiert'), duration: const Duration(seconds: 2)),
                  );
                }
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ],
    );
  }
```

- [ ] **Add "Mein Zugang" tile to account switcher** — in `_showAccountSwitcher()`, inside the `Column`'s `children` list, add after the last account tile and before the closing `]`:

```dart
          const Divider(),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Mein Zugang'),
            subtitle: const Text('Benutzername, Passwort & Kurzlink'),
            onTap: () {
              Navigator.pop(ctx);
              _showCredentials();
            },
          ),
          const SizedBox(height: 8),
```

- [ ] **Run analyze**

```bash
flutter analyze lib/screens/home_screen.dart 2>&1 | grep -E "^  error" | head -20
```

Expected: no errors (existing warnings are pre-existing and unrelated)

- [ ] **Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: add Mein Zugang credentials view to account switcher"
```

---

## Self-Review

**Spec coverage:**
- ✅ Collapsible section, collapsed by default (Tasks 1–2)
- ✅ Chevron rotates on expand (Task 3 `toggleLogin`)
- ✅ Benutzername + Passwort fields (Task 2 HTML)
- ✅ Submit builds full URL with prod apiBaseUrl (Task 3 `submitLogin`)
- ✅ apiBaseUrl passthrough from URL for dev (Task 3 `p.get('apiBaseUrl') || ...`)
- ✅ Pre-fill from `?applicationId=X&memberId=Y` + auto-expand (Task 4)
- ✅ "Vom Einladungslink vorausgefüllt" note (Task 4)
- ✅ Validation + error message (Task 3)
- ✅ All three HTML files covered (Tasks 1–6)
- ✅ Credentials view in app: applicationId, memberId (masked + reveal), short link, all copyable (Task 7)

**Placeholder scan:** None found.

**Type consistency:** `_credentialRow` is defined and called with the same named parameters throughout Task 7.

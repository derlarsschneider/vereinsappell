# Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a public landing page to vereinsappell.web.app that renders when no app parameters are in the URL, with flows for new club registration and member join requests, backed by two new unauthenticated API endpoints that send emails via AWS SES.

**Architecture:** `web/index.html` detects URL params at load time and either renders an inline landing page (HTML/CSS/JS) or bootstraps the Flutter app. Two new public API endpoints (`POST /join/club`, `POST /join/member`) in the existing AWS Lambda backend send notification emails via SES. Infrastructure is wired via Terraform.

**Tech Stack:** Python 3.10 (Lambda), boto3 SES, Terraform, HTML/CSS/JS (no framework), jsQR 1.4.0 (CDN)

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `aws_backend/lambda/api_join.py` | Create | Handlers for `/join/club` and `/join/member` |
| `aws_backend/lambda/tests/test_api_join.py` | Create | Unit tests for api_join |
| `aws_backend/lambda/lambda_handler.py` | Modify | Add dispatch entries for `/join/*` |
| `aws_backend/api_join.tf` | Create | Terraform API Gateway routes (public, no auth) |
| `aws_backend/roles.tf` | Modify | Add SES send permission to lambda role |
| `aws_backend/lambda_backend.tf` | Modify | Add `CONTACT_EMAIL` env var to lambda |
| `web/index.html` | Modify | Parameter detection + landing page HTML/CSS/JS |

---

## Task 1: Backend handler `api_join.py`

**Files:**
- Create: `aws_backend/lambda/api_join.py`
- Create: `aws_backend/lambda/tests/test_api_join.py`

- [ ] **Step 1.1: Write failing tests**

Create `aws_backend/lambda/tests/test_api_join.py`:

```python
import json
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

sys.modules.setdefault('boto3', MagicMock())

sys.path.insert(0, '.')
import api_join


def _club_event(body):
    return {
        'requestContext': {'http': {'method': 'POST', 'path': '/join/club'}},
        'headers': {'origin': 'https://vereinsappell.web.app'},
        'body': json.dumps(body),
    }


def _member_event(body):
    return {
        'requestContext': {'http': {'method': 'POST', 'path': '/join/member'}},
        'headers': {'origin': 'https://vereinsappell.web.app'},
        'body': json.dumps(body),
    }


class TestHandleJoinClub(unittest.TestCase):
    def setUp(self):
        api_join.ses = MagicMock()
        os.environ['CONTACT_EMAIL'] = 'info@vereinsappell.de'

    def test_returns_200_on_valid_payload(self):
        api_join.ses.send_email.return_value = {'MessageId': 'abc123'}
        event = _club_event({
            'clubName': 'Schützenverein Test',
            'contact': 'Max Mustermann',
            'email': 'max@example.com',
        })
        response = api_join.handle_join_club(event, {})
        self.assertEqual(response['statusCode'], 200)

    def test_sends_email_with_club_details(self):
        api_join.ses.send_email.return_value = {'MessageId': 'abc123'}
        event = _club_event({
            'clubName': 'Schützenverein Test',
            'contact': 'Max Mustermann',
            'email': 'max@example.com',
            'phone': '+49 123 456',
            'message': 'Wir haben 42 Mitglieder.',
        })
        api_join.handle_join_club(event, {})
        call_kwargs = api_join.ses.send_email.call_args[1]
        body_text = call_kwargs['Message']['Body']['Text']['Data']
        self.assertIn('Schützenverein Test', body_text)
        self.assertIn('Max Mustermann', body_text)
        self.assertIn('max@example.com', body_text)

    def test_returns_400_when_required_field_missing(self):
        event = _club_event({'clubName': 'Test'})  # missing contact and email
        response = api_join.handle_join_club(event, {})
        self.assertEqual(response['statusCode'], 400)

    def test_has_cors_header(self):
        api_join.ses.send_email.return_value = {'MessageId': 'abc123'}
        event = _club_event({
            'clubName': 'Test', 'contact': 'Test', 'email': 'test@test.de'
        })
        response = api_join.handle_join_club(event, {})
        self.assertIn('Access-Control-Allow-Origin', response['headers'])


class TestHandleJoinMember(unittest.TestCase):
    def setUp(self):
        api_join.ses = MagicMock()
        os.environ['CONTACT_EMAIL'] = 'info@vereinsappell.de'

    def test_returns_200_on_valid_payload(self):
        api_join.ses.send_email.return_value = {'MessageId': 'abc123'}
        event = _member_event({
            'name': 'Max Mustermann',
            'clubName': 'Schützenverein Test',
            'email': 'max@example.com',
        })
        response = api_join.handle_join_member(event, {})
        self.assertEqual(response['statusCode'], 200)

    def test_sends_email_with_member_details(self):
        api_join.ses.send_email.return_value = {'MessageId': 'abc123'}
        event = _member_event({
            'name': 'Max Mustermann',
            'clubName': 'Schützenverein Test',
            'email': 'max@example.com',
            'message': 'Ich möchte beitreten.',
        })
        api_join.handle_join_member(event, {})
        call_kwargs = api_join.ses.send_email.call_args[1]
        body_text = call_kwargs['Message']['Body']['Text']['Data']
        self.assertIn('Max Mustermann', body_text)
        self.assertIn('Schützenverein Test', body_text)

    def test_returns_400_when_required_field_missing(self):
        event = _member_event({'name': 'Max'})  # missing clubName and email
        response = api_join.handle_join_member(event, {})
        self.assertEqual(response['statusCode'], 400)
```

- [ ] **Step 1.2: Run tests to verify they fail**

```bash
cd aws_backend/lambda
python -m pytest tests/test_api_join.py -v 2>&1 | head -30
```

Expected: `ModuleNotFoundError: No module named 'api_join'`

- [ ] **Step 1.3: Implement `api_join.py`**

Create `aws_backend/lambda/api_join.py`:

```python
import json
import os
import boto3

ses = boto3.client('ses', region_name='eu-central-1')

_CORS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'OPTIONS,POST',
}

_REQUIRED_CLUB = {'clubName', 'contact', 'email'}
_REQUIRED_MEMBER = {'name', 'clubName', 'email'}


def _contact_email():
    return os.environ.get('CONTACT_EMAIL', 'info@vereinsappell.de')


def _bad_request(msg):
    return {'statusCode': 400, 'headers': _CORS, 'body': json.dumps({'error': msg})}


def _ok():
    return {'statusCode': 200, 'headers': _CORS, 'body': json.dumps({'ok': True})}


def handle_join_club(event, context):
    if event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
        return {'statusCode': 204, 'headers': _CORS}

    try:
        data = json.loads(event.get('body') or '{}')
    except json.JSONDecodeError:
        return _bad_request('Invalid JSON')

    missing = _REQUIRED_CLUB - set(k for k, v in data.items() if v)
    if missing:
        return _bad_request(f'Missing fields: {", ".join(sorted(missing))}')

    lines = [
        f'Vereinsname: {data["clubName"]}',
        f'Ansprechpartner: {data["contact"]}',
        f'E-Mail: {data["email"]}',
    ]
    if data.get('phone'):
        lines.append(f'Telefon: {data["phone"]}')
    if data.get('message'):
        lines.append(f'\nNachricht:\n{data["message"]}')

    body = '\n'.join(lines)
    ses.send_email(
        Source=_contact_email(),
        Destination={'ToAddresses': [_contact_email()]},
        Message={
            'Subject': {'Data': f'Neue Vereinsanmeldung: {data["clubName"]}'},
            'Body': {'Text': {'Data': body}},
        },
        ReplyToAddresses=[data['email']],
    )
    return _ok()


def handle_join_member(event, context):
    if event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
        return {'statusCode': 204, 'headers': _CORS}

    try:
        data = json.loads(event.get('body') or '{}')
    except json.JSONDecodeError:
        return _bad_request('Invalid JSON')

    missing = _REQUIRED_MEMBER - set(k for k, v in data.items() if v)
    if missing:
        return _bad_request(f'Missing fields: {", ".join(sorted(missing))}')

    lines = [
        f'Name: {data["name"]}',
        f'Vereinsname: {data["clubName"]}',
        f'E-Mail: {data["email"]}',
    ]
    if data.get('message'):
        lines.append(f'\nNachricht:\n{data["message"]}')

    body = '\n'.join(lines)
    ses.send_email(
        Source=_contact_email(),
        Destination={'ToAddresses': [_contact_email()]},
        Message={
            'Subject': {'Data': f'Beitrittsanfrage: {data["name"]} → {data["clubName"]}'},
            'Body': {'Text': {'Data': body}},
        },
        ReplyToAddresses=[data['email']],
    )
    return _ok()
```

- [ ] **Step 1.4: Run tests to verify they pass**

```bash
cd aws_backend/lambda
python -m pytest tests/test_api_join.py -v
```

Expected: all 8 tests PASS

- [ ] **Step 1.5: Commit**

```bash
git add aws_backend/lambda/api_join.py aws_backend/lambda/tests/test_api_join.py
git commit -m "feat(backend): add api_join handler for club registration and member requests"
```

---

## Task 2: Wire dispatch in `lambda_handler.py`

**Files:**
- Modify: `aws_backend/lambda/lambda_handler.py`

- [ ] **Step 2.1: Add dispatch entries**

In `aws_backend/lambda/lambda_handler.py`, add to the `_dispatch` function after the last `elif` block, before `return None`:

```python
    elif method == 'POST' and path == '/join/club':
        import api_join
        return api_join.handle_join_club(event, context)
    elif method == 'POST' and path == '/join/member':
        import api_join
        return api_join.handle_join_member(event, context)
    elif method == 'OPTIONS' and path in ('/join/club', '/join/member'):
        import api_join
        return api_join.handle_join_club(event, context)
```

- [ ] **Step 2.2: Verify existing tests still pass**

```bash
cd aws_backend/lambda
python -m pytest tests/ -v --ignore=tests/test_api_reminders.py 2>&1 | tail -20
```

Expected: all tests PASS (test_api_reminders.py is excluded as it requires network)

- [ ] **Step 2.3: Commit**

```bash
git add aws_backend/lambda/lambda_handler.py
git commit -m "feat(backend): dispatch /join/club and /join/member to api_join"
```

---

## Task 3: Terraform — routes and IAM

**Files:**
- Create: `aws_backend/api_join.tf`
- Modify: `aws_backend/roles.tf`
- Modify: `aws_backend/lambda_backend.tf`

- [ ] **Step 3.1: Create `api_join.tf`**

Create `aws_backend/api_join.tf`:

```hcl
resource "aws_apigatewayv2_route" "join_club_post" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "POST /join/club"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "NONE"
}

resource "aws_apigatewayv2_route" "join_club_options" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "OPTIONS /join/club"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "NONE"
}

resource "aws_apigatewayv2_route" "join_member_post" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "POST /join/member"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "NONE"
}

resource "aws_apigatewayv2_route" "join_member_options" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "OPTIONS /join/member"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "NONE"
}
```

- [ ] **Step 3.2: Add SES policy to `roles.tf`**

Append to `aws_backend/roles.tf`:

```hcl
resource "aws_iam_policy" "ses_policy" {
    name = "${local.name_prefix}-ses_policy"

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect   = "Allow"
            Action   = ["ses:SendEmail", "ses:SendRawEmail"]
            Resource = "*"
        }]
    })
}

resource "aws_iam_role_policy_attachment" "ses_policy_attachment" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = aws_iam_policy.ses_policy.arn
}
```

- [ ] **Step 3.3: Add `CONTACT_EMAIL` env var to `lambda_backend.tf`**

In `aws_backend/lambda_backend.tf`, add to the `environment.variables` block of `aws_lambda_function.lambda_backend`:

```hcl
CONTACT_EMAIL = "info@vereinsappell.de"
```

- [ ] **Step 3.4: Validate Terraform**

```bash
cd aws_backend
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3.5: Commit**

```bash
git add aws_backend/api_join.tf aws_backend/roles.tf aws_backend/lambda_backend.tf
git commit -m "feat(infra): add public API routes for /join/club and /join/member with SES permission"
```

> **Note:** After merging, run `terraform apply` and then manually verify `info@vereinsappell.de` as an SES identity in the AWS console (eu-central-1) before the endpoints can send email. SES sandbox mode requires both sender and recipient to be verified — request production access if needed.

---

## Task 4: Landing page in `web/index.html`

**Files:**
- Modify: `web/index.html`

This task replaces the unconditional `<script src="flutter_bootstrap.js" async></script>` with param-detection logic and embeds the full landing page HTML.

The API base URL for fetch calls is read from the window — use the existing prod endpoint. At runtime the frontend calls the API Gateway directly; the URL is injected as a constant in the JS.

**The API Gateway endpoint URL** can be found by running `terraform output api_url` in `aws_backend/`. It looks like `https://<id>.execute-api.eu-central-1.amazonaws.com`. Substitute the actual value for `API_URL` in the script below.

- [ ] **Step 4.1: Run `terraform output` to get the API URL**

```bash
cd aws_backend
terraform output api_url
```

Note the URL — you will use it in the next step.

- [ ] **Step 4.2: Replace `web/index.html`**

Replace the entire contents of `web/index.html` with the following (substitute `<API_URL>` with the value from Step 4.1):

```html
<!DOCTYPE html>
<html lang="de">
<head>
  <base href="$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="google-adsense-account" content="ca-pub-4535258076297789">
  <meta name="description" content="Vereins Appell: Die App für deinen Verein. Mitgliederverwaltung, Termine, Abstimmungen und mehr.">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="Vereins Appell">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <meta name="theme-color" content="#283f22">
  <link rel="icon" type="image/png" href="favicon.png">
  <title>Vereins Appell: Die App für deinen Verein</title>
  <link rel="manifest" href="manifest.json">
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:system-ui,-apple-system,sans-serif;background:#f0f4f0}
    #lp{display:none}
    .lp-nav{background:#1a3a1a;color:#fff;padding:14px 24px;display:flex;align-items:center;gap:12px}
    .lp-nav img{width:32px;height:32px;border-radius:6px}
    .lp-nav-title{font-weight:700;font-size:16px;letter-spacing:1px}
    .lp-nav-sub{font-size:11px;opacity:.7}
    .lp-hero{background:linear-gradient(135deg,#1a3a1a 0%,#2d6a2d 100%);color:#fff;text-align:center;padding:40px 20px 30px}
    .lp-hero h1{font-size:26px;font-weight:800;margin-bottom:8px}
    .lp-hero p{font-size:14px;opacity:.85;max-width:420px;margin:0 auto}
    .lp-section{max-width:560px;margin:0 auto;padding:0 16px}
    .lp-cards{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;margin:-20px 0 16px}
    .lp-card{background:#fff;border-radius:12px;padding:20px 12px;text-align:center;cursor:pointer;border:2px solid transparent;box-shadow:0 2px 8px rgba(0,0,0,.08);display:flex;flex-direction:column;align-items:center;transition:border-color .2s,box-shadow .2s}
    .lp-card:hover{border-color:#2d6a2d;box-shadow:0 4px 16px rgba(45,106,45,.15)}
    .lp-card .ic{font-size:32px;margin-bottom:8px}
    .lp-card h2{font-size:12px;font-weight:700;color:#1a3a1a;margin-bottom:5px;line-height:1.3}
    .lp-card p{font-size:11px;color:#666;line-height:1.4;flex:1}
    .lp-btn{margin-top:12px;display:inline-block;background:#2d6a2d;color:#fff;border-radius:6px;padding:6px 12px;font-size:11px;font-weight:600;border:none;cursor:pointer;width:100%}
    .lp-btn-outline{background:#fff;color:#2d6a2d;border:1.5px solid #2d6a2d}
    .lp-hint{background:#fff;border-radius:10px;padding:14px 18px;text-align:center;font-size:12px;color:#888;box-shadow:0 1px 4px rgba(0,0,0,.06);margin-bottom:16px}
    .lp-hint a{color:#2d6a2d;font-weight:600;text-decoration:none}
    .lp-features{background:#fff;border-radius:12px;padding:20px;box-shadow:0 1px 4px rgba(0,0,0,.06);margin-bottom:16px}
    .lp-features h3{font-size:12px;font-weight:700;color:#888;text-transform:uppercase;letter-spacing:1px;margin-bottom:14px}
    .lp-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
    .lp-fi{display:flex;align-items:flex-start;gap:8px}
    .lp-fi span:first-child{font-size:18px}
    .lp-fi strong{display:block;color:#1a3a1a;font-size:12px}
    .lp-fi em{color:#777;font-size:11px;font-style:normal}
    .lp-footer{text-align:center;padding:20px;font-size:11px;color:#aaa}
    .lp-modal{display:none;position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:100;align-items:center;justify-content:center;padding:16px}
    .lp-modal.open{display:flex}
    .lp-box{background:#fff;border-radius:14px;padding:24px;width:100%;max-width:440px;max-height:90vh;overflow-y:auto}
    .lp-box h2{font-size:16px;font-weight:700;color:#1a3a1a;margin-bottom:16px}
    .lp-field{margin-bottom:12px}
    .lp-field label{display:block;font-size:12px;font-weight:600;color:#444;margin-bottom:4px}
    .lp-field input,.lp-field textarea{width:100%;border:1.5px solid #ddd;border-radius:8px;padding:9px 12px;font-size:13px;outline:none;font-family:inherit}
    .lp-field input:focus,.lp-field textarea:focus{border-color:#2d6a2d}
    .lp-field textarea{min-height:80px;resize:vertical}
    .lp-row{display:flex;gap:8px;margin-top:4px}
    .lp-close{background:none;border:none;font-size:20px;cursor:pointer;color:#888;float:right;margin-top:-4px}
    .lp-msg{font-size:12px;margin-top:8px;padding:8px 12px;border-radius:6px;display:none}
    .lp-msg.ok{background:#e8f5e9;color:#2d6a2d;display:block}
    .lp-msg.err{background:#fdecea;color:#c62828;display:block}
    #qr-wrap{display:none;margin-top:12px}
    #qr-wrap video{width:100%;border-radius:8px}
    #qr-error{font-size:12px;color:#c62828;margin-top:6px;display:none}
    @media(max-width:400px){.lp-cards{grid-template-columns:1fr}}
  </style>
</head>
<body>

<!-- Service worker + hardReload (always runs, for both landing and Flutter) -->
<script>
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/firebase-messaging-sw.js', { scope: '/' });
  }
  window.hardReload = async function () {
    try {
      if ('serviceWorker' in navigator) {
        const regs = await navigator.serviceWorker.getRegistrations();
        for (const r of regs) await r.unregister();
      }
      if ('caches' in window) {
        const keys = await window.caches.keys();
        for (const k of keys) await window.caches.delete(k);
      }
    } catch (e) { console.error('Hard reload failed:', e); }
    setTimeout(() => { window.location.href = window.location.origin + '/'; }, 200);
  };
</script>

<!-- Routing: Flutter if params present, landing page otherwise -->
<script>
  (function () {
    const p = new URLSearchParams(window.location.search);
    if (p.has('apiBaseUrl') && p.has('applicationId') && p.has('memberId')) {
      const s = document.createElement('script');
      s.src = 'flutter_bootstrap.js';
      document.body.appendChild(s);
    } else {
      document.getElementById('lp').style.display = 'block';
    }
  })();
</script>

<!-- jsQR for QR scanning (only loaded when user clicks QR button) -->
<div id="lp">
  <nav class="lp-nav">
    <img src="icons/Icon-192.png" alt="Logo">
    <div>
      <div class="lp-nav-title">VEREINS APPELL</div>
      <div class="lp-nav-sub">Die App für deinen Verein</div>
    </div>
  </nav>

  <div class="lp-hero">
    <h1>Was möchtest du tun?</h1>
    <p>Vereinsverwaltung einfach gemacht — für Schützenvereine, Sportvereine und mehr.</p>
  </div>

  <div class="lp-section">
    <div class="lp-cards">
      <div class="lp-card">
        <div class="ic">🏛️</div>
        <h2>Meinen Verein anmelden</h2>
        <p>Vereinsverwaltung einrichten und alle Mitglieder einladen.</p>
        <button class="lp-btn" onclick="openModal('club')">Jetzt anmelden</button>
      </div>
      <div class="lp-card">
        <div class="ic">📷</div>
        <h2>QR-Code scannen</h2>
        <p>Einladungs-QR vom Admin scannen und sofort loslegen.</p>
        <button class="lp-btn lp-btn-outline" onclick="openModal('qr')">QR scannen</button>
      </div>
      <div class="lp-card">
        <div class="ic">✉️</div>
        <h2>Beitrittsanfrage</h2>
        <p>Keinen QR-Code? Anfrage an deinen Vereinsadmin schicken.</p>
        <button class="lp-btn lp-btn-outline" onclick="openModal('member')">Anfrage stellen</button>
      </div>
    </div>

    <div class="lp-hint">
      Bereits registriert? Öffne deinen <a href="#" onclick="openModal('link');return false">Einladungslink</a> oder scanne den QR-Code.
    </div>

    <div class="lp-features">
      <h3>Was Vereins Appell kann</h3>
      <div class="lp-grid">
        <div class="lp-fi"><span>📋</span><div><strong>Mitgliederverwaltung</strong><em>Alle Daten an einem Ort</em></div></div>
        <div class="lp-fi"><span>📅</span><div><strong>Terminkalender</strong><em>Mit Push-Erinnerungen</em></div></div>
        <div class="lp-fi"><span>💶</span><div><strong>Umlagen &amp; Strafen</strong><em>Transparent &amp; nachvollziehbar</em></div></div>
        <div class="lp-fi"><span>📄</span><div><strong>Dokumente</strong><em>Protokolle &amp; Unterlagen</em></div></div>
        <div class="lp-fi"><span>🗳️</span><div><strong>Abstimmungen</strong><em>Schnell &amp; anonym abstimmen</em></div></div>
        <div class="lp-fi"><span>🍺</span><div><strong>Getränkebestellungen</strong><em>Vorbestellung für Veranstaltungen</em></div></div>
      </div>
    </div>
  </div>

  <div class="lp-footer">© 2026 Vereins Appell</div>
</div>

<!-- Modal: Verein anmelden -->
<div id="modal-club" class="lp-modal">
  <div class="lp-box">
    <button class="lp-close" onclick="closeModal('club')">✕</button>
    <h2>🏛️ Verein anmelden</h2>
    <div class="lp-field"><label>Vereinsname *</label><input id="club-name" type="text" placeholder="Schützenverein Musterstadt"></div>
    <div class="lp-field"><label>Ansprechpartner *</label><input id="club-contact" type="text" placeholder="Max Mustermann"></div>
    <div class="lp-field"><label>E-Mail *</label><input id="club-email" type="email" placeholder="max@example.com"></div>
    <div class="lp-field"><label>Telefon</label><input id="club-phone" type="tel" placeholder="+49 123 456789"></div>
    <div class="lp-field"><label>Nachricht</label><textarea id="club-message" placeholder="Kurze Beschreibung eures Vereins..."></textarea></div>
    <div class="lp-row">
      <button class="lp-btn lp-btn-outline" style="flex:1" onclick="closeModal('club')">Abbrechen</button>
      <button class="lp-btn" style="flex:2" onclick="submitClub()">Absenden</button>
    </div>
    <div id="club-msg" class="lp-msg"></div>
  </div>
</div>

<!-- Modal: Beitrittsanfrage -->
<div id="modal-member" class="lp-modal">
  <div class="lp-box">
    <button class="lp-close" onclick="closeModal('member')">✕</button>
    <h2>✉️ Beitrittsanfrage</h2>
    <div class="lp-field"><label>Dein Name *</label><input id="member-name" type="text" placeholder="Max Mustermann"></div>
    <div class="lp-field"><label>Vereinsname *</label><input id="member-club" type="text" placeholder="Schützenverein Musterstadt"></div>
    <div class="lp-field"><label>Deine E-Mail *</label><input id="member-email" type="email" placeholder="max@example.com"></div>
    <div class="lp-field"><label>Nachricht</label><textarea id="member-message" placeholder="Optional: Kurze Nachricht an den Admin..."></textarea></div>
    <div class="lp-row">
      <button class="lp-btn lp-btn-outline" style="flex:1" onclick="closeModal('member')">Abbrechen</button>
      <button class="lp-btn" style="flex:2" onclick="submitMember()">Absenden</button>
    </div>
    <div id="member-msg" class="lp-msg"></div>
  </div>
</div>

<!-- Modal: QR-Code scannen -->
<div id="modal-qr" class="lp-modal">
  <div class="lp-box">
    <button class="lp-close" onclick="closeModal('qr')">✕</button>
    <h2>📷 QR-Code scannen</h2>
    <p style="font-size:12px;color:#666;margin-bottom:12px">Halte die Kamera auf den Einladungs-QR-Code deines Admins.</p>
    <button class="lp-btn" onclick="startQr()">Kamera starten</button>
    <div id="qr-wrap">
      <video id="qr-video" autoplay playsinline muted></video>
      <canvas id="qr-canvas" style="display:none"></canvas>
    </div>
    <div id="qr-error"></div>
  </div>
</div>

<!-- Modal: Einladungslink einfügen -->
<div id="modal-link" class="lp-modal">
  <div class="lp-box">
    <button class="lp-close" onclick="closeModal('link')">✕</button>
    <h2>🔗 Einladungslink eingeben</h2>
    <p style="font-size:12px;color:#666;margin-bottom:12px">Füge den Link ein, den du von deinem Admin erhalten hast.</p>
    <div class="lp-field"><label>Einladungslink</label><input id="invite-link" type="url" placeholder="https://vereinsappell.web.app/?apiBaseUrl=..."></div>
    <div class="lp-row">
      <button class="lp-btn lp-btn-outline" style="flex:1" onclick="closeModal('link')">Abbrechen</button>
      <button class="lp-btn" style="flex:2" onclick="submitLink()">Öffnen</button>
    </div>
    <div id="link-msg" class="lp-msg"></div>
  </div>
</div>

<script>
  const API_URL = 'REPLACE_WITH_TERRAFORM_OUTPUT_API_URL';

  function openModal(name) { document.getElementById('modal-' + name).classList.add('open'); }
  function closeModal(name) { document.getElementById('modal-' + name).classList.remove('open'); stopQr(); }

  function showMsg(id, text, isOk) {
    const el = document.getElementById(id);
    el.textContent = text;
    el.className = 'lp-msg ' + (isOk ? 'ok' : 'err');
  }

  async function post(path, body) {
    const r = await fetch(API_URL + path, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(body),
    });
    if (!r.ok) throw new Error('Fehler ' + r.status);
  }

  async function submitClub() {
    const name = document.getElementById('club-name').value.trim();
    const contact = document.getElementById('club-contact').value.trim();
    const email = document.getElementById('club-email').value.trim();
    if (!name || !contact || !email) { showMsg('club-msg', 'Bitte alle Pflichtfelder ausfüllen.', false); return; }
    try {
      await post('/join/club', {
        clubName: name, contact, email,
        phone: document.getElementById('club-phone').value.trim(),
        message: document.getElementById('club-message').value.trim(),
      });
      showMsg('club-msg', 'Vielen Dank! Wir melden uns in Kürze bei dir.', true);
    } catch (e) { showMsg('club-msg', 'Fehler beim Senden. Bitte versuche es später nochmal.', false); }
  }

  async function submitMember() {
    const name = document.getElementById('member-name').value.trim();
    const club = document.getElementById('member-club').value.trim();
    const email = document.getElementById('member-email').value.trim();
    if (!name || !club || !email) { showMsg('member-msg', 'Bitte alle Pflichtfelder ausfüllen.', false); return; }
    try {
      await post('/join/member', {
        name, clubName: club, email,
        message: document.getElementById('member-message').value.trim(),
      });
      showMsg('member-msg', 'Deine Anfrage wurde weitergeleitet. Du erhältst bald Nachricht.', true);
    } catch (e) { showMsg('member-msg', 'Fehler beim Senden. Bitte versuche es später nochmal.', false); }
  }

  function submitLink() {
    const val = document.getElementById('invite-link').value.trim();
    try {
      const u = new URL(val);
      const p = u.searchParams;
      if (!p.has('apiBaseUrl') || !p.has('applicationId') || !p.has('memberId')) {
        showMsg('link-msg', 'Der Link ist unvollständig. Bitte prüfe ihn und versuche es nochmal.', false);
        return;
      }
      window.location.href = val;
    } catch {
      showMsg('link-msg', 'Ungültiger Link.', false);
    }
  }

  // QR scanner
  let qrStream = null;
  let qrAnimFrame = null;
  let jsQrLoaded = false;

  async function loadJsQr() {
    if (jsQrLoaded) return;
    await new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = 'https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.js';
      s.onload = resolve; s.onerror = reject;
      document.head.appendChild(s);
    });
    jsQrLoaded = true;
  }

  async function startQr() {
    const errEl = document.getElementById('qr-error');
    errEl.style.display = 'none';
    try {
      await loadJsQr();
      qrStream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
      const video = document.getElementById('qr-video');
      video.srcObject = qrStream;
      document.getElementById('qr-wrap').style.display = 'block';
      scanFrame();
    } catch (e) {
      errEl.textContent = 'Kamera konnte nicht gestartet werden: ' + e.message;
      errEl.style.display = 'block';
    }
  }

  function scanFrame() {
    const video = document.getElementById('qr-video');
    const canvas = document.getElementById('qr-canvas');
    if (video.readyState === video.HAVE_ENOUGH_DATA) {
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
      const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
      const code = jsQR(imageData.data, imageData.width, imageData.height);
      if (code) {
        stopQr();
        handleQrResult(code.data);
        return;
      }
    }
    qrAnimFrame = requestAnimationFrame(scanFrame);
  }

  function stopQr() {
    if (qrStream) { qrStream.getTracks().forEach(t => t.stop()); qrStream = null; }
    if (qrAnimFrame) { cancelAnimationFrame(qrAnimFrame); qrAnimFrame = null; }
    document.getElementById('qr-wrap').style.display = 'none';
  }

  function handleQrResult(data) {
    try {
      const u = new URL(data);
      const p = u.searchParams;
      if (p.has('apiBaseUrl') && p.has('applicationId') && p.has('memberId')) {
        window.location.href = data;
        return;
      }
    } catch {}
    const errEl = document.getElementById('qr-error');
    errEl.textContent = 'Ungültiger QR-Code. Bitte den Einladungs-QR vom Admin scannen.';
    errEl.style.display = 'block';
  }
</script>

</body>
</html>
```

- [ ] **Step 4.3: Substitute the real API URL**

In `web/index.html`, find `const API_URL = 'REPLACE_WITH_TERRAFORM_OUTPUT_API_URL';` and replace the placeholder with the actual URL from Step 4.1, e.g.:

```js
const API_URL = 'https://abc123.execute-api.eu-central-1.amazonaws.com';
```

- [ ] **Step 4.4: Build and smoke-test locally**

```bash
cd /path/to/vereinsappell
flutter build web --release
cd build/web
python3 -m http.server 8080
```

Open http://localhost:8080 in a browser:
- Without URL params → landing page visible with three cards
- With `?apiBaseUrl=x&applicationId=y&memberId=z` → Flutter app loads (spinner appears)
- Click "Verein anmelden" → modal opens with form
- Click "QR-Code scannen" → modal opens, "Kamera starten" button visible
- Click "Beitrittsanfrage" → modal opens with form
- Click "Einladungslink" hint → link-entry modal opens

- [ ] **Step 4.5: Commit**

```bash
git add web/index.html
git commit -m "feat(web): add landing page with club registration, member join, and QR scanner"
```

---

## Task 5: Deploy

- [ ] **Step 5.1: Deploy backend (Lambda + Terraform)**

```bash
cd aws_backend/lambda
bash build.sh
bash update.sh
cd ..
terraform apply
```

- [ ] **Step 5.2: Verify SES identity in AWS console**

In the AWS console (eu-central-1 → SES):
1. Add email identity `info@vereinsappell.de` (or the domain `vereinsappell.de`)
2. Complete DNS/email verification
3. If still in SES sandbox: request production access or add recipient addresses as verified identities

- [ ] **Step 5.3: Deploy frontend**

```bash
firebase deploy --only hosting
```

- [ ] **Step 5.4: Smoke-test production**

- Open https://vereinsappell.web.app — landing page should appear
- Open https://vereinsappell.web.app/?apiBaseUrl=X&applicationId=Y&memberId=Z — Flutter app should load
- Submit "Verein anmelden" form with test data — email should arrive at info@vereinsappell.de
- Submit "Beitrittsanfrage" with test data — email should arrive

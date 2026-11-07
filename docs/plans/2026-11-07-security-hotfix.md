# Security Hotfix (Phase 0 + 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the authorization gaps that allow privilege escalation, cross-club access, data deletion and SSRF, without changing the login model yet.

**Architecture:** The API Gateway authorizer starts verifying that the `(applicationId, memberId)` pair is an existing, active member. A new backend module `authz.py` loads the caller once per request and provides role checks; every route in `lambda_handler.py`, `api_customers.py`, `api_docs.py` and `api_monitoring.py` gets an explicit role gate. The remote image download in `update_customer` is restricted to public HTTPS hosts without redirects.

**Tech Stack:** Python 3.10 Lambda, boto3/DynamoDB, API Gateway HTTP API (Terraform), pytest + unittest.mock.

**Spec:** Security analysis from 2026-11-07 (not committed on purpose; summary in `.claude/TODOS.md`, section "Security-Audit 2026-11-07").

## Global Constraints

- Code, comments and commit messages in English; no `Co-Authored-By` line; no `git push`.
- No changes to the login model (memberId stays the credential) — that is Phase 2, separate plan.
- Firebase Realtime DB rules are out of scope (Phase 3, separate plan).
- Every 403 response body is `{"error": "Nicht berechtigt"}` (same as `api_members.ERROR_403`) and carries the CORS headers of the route.
- Role semantics (from frontend gating): `isSuperAdmin` = platform operator; `isAdmin` = club admin; `isSpiess` = manages fines. A super admin is checked in the caller's **current** club row `(applicationId, memberId)`.
- Inactive members (`isActive == False`) are rejected by the authorizer, except super admins.
- Tests run with `cd aws_backend/lambda && pytest tests/` and `cd aws_backend/authorizer && pytest tests/`.

## Review Focus

1. Caller header `memberid` missing or empty → 403 on every gated route, never a crash (KeyError/None access). Test in Task 2.
2. Super admin of club A calling `PUT /customers/B` → allowed; admin of club A calling `PUT /customers/B` → 403. Test in Task 3.
3. `ad_banner_image_source_url` with `http://`, `file://`, an IP literal, `localhost`, or a host resolving to `10.x/127.x/169.254.x` → 400, no request made. Test in Task 4.
4. `POST /monitoring/timing` still works for normal members (startup timer sends it on every app start). Test in Task 5.
5. `DELETE /fines/{fineId}` for a fineId of another club → no deletion outside the caller's club (key already contains applicationId; keep it that way). Test in Task 6.

---

## Task 0: Incident check (manual, operator)

Not code. Must happen before deploying, because deploying changes nothing about past abuse.

- [ ] **Step 1:** In CloudWatch Logs Insights on `/aws/lambda/vereins-app-beta-lambda_backend` (range: since the customers routes exist, max. retention), run:

```
fields @timestamp, applicationId, memberId, path, httpMethod
| filter log_type = "api_access"
| filter (httpMethod = "POST" and path = "/customers")
     or (httpMethod = "PUT" and path like /^\/customers\//)
     or path like /^\/monitoring\//
| sort @timestamp desc
```

Expected: only your own memberIds. Any other memberId → treat as incident.

- [ ] **Step 2:** Same for `/aws/lambda/vereins-app-beta-restore` and `-backup` (all invocations). Expected: only your own runs.
- [ ] **Step 3:** In the S3 bucket, list `*/ad_banner/banner.jpg` and check each file is actually an image (`file` command after download). A text file containing `AWS_ACCESS_KEY_ID` means credentials leaked → rotate by redeploying the Lambda role (new session creds) and check CloudTrail for foreign API calls.
- [ ] **Step 4:** Compare `paypal_account` of every customer row with what the clubs expect.
- [ ] **Step 5:** If any check is positive: GDPR Art. 33 notification within 72 h, inform affected clubs.

---

### Task 1: Authorizer verifies the member

**Files:**
- Modify: `aws_backend/authorizer/authorizer.py`
- Modify: `aws_backend/lambda_authorizer.tf` (add `environment { variables = { MEMBERS_TABLE_NAME = aws_dynamodb_table.members_table.name } }`)
- Create: `aws_backend/authorizer/tests/__init__.py`, `aws_backend/authorizer/tests/test_authorizer.py`
- Modify: `aws_backend/authorizer/zip.sh` (exclude `tests/` and `__pycache__`: `zip --filesync -r "$ZIP" . -x 'tests/*' '__pycache__/*'`)
- Modify: `.github/workflows/firebase-hosting-merge.yml`, `.github/workflows/firebase-hosting-pull-request.yml` (second test step, `working-directory: aws_backend/authorizer`, `run: pytest tests/`)

**Interfaces:**
- Produces: `lambda_authorizer(event, context) -> {"isAuthorized": bool}`; `_get_member(application_id: str, member_id: str) -> dict | None` (DynamoDB `get_item` on `MEMBERS_TABLE_NAME`, key `applicationId`/`memberId`). The customers-table scan `get_application_ids()` is removed.

- [ ] **Step 1: Write failing tests** in `test_authorizer.py` (mock `boto3` via `sys.modules` like `lambda/tests/test_api_members.py`; patch `authorizer._get_member`):
  - `test_unknown_member_denied`: `_get_member` returns `None` → `isAuthorized is False`
  - `test_missing_headers_denied`: headers `{}` → `False` and `_get_member` not called
  - `test_active_member_allowed`: returns `{"isActive": True}` → `True`
  - `test_member_without_isActive_allowed`: returns `{}` → `True` (legacy rows default to active)
  - `test_inactive_member_denied`: `{"isActive": False}` → `False`
  - `test_inactive_super_admin_allowed`: `{"isActive": False, "isSuperAdmin": True}` → `True`
  - `test_eventbridge_allowed`: `{"source": "aws.events"}` → `True`
- [ ] **Step 2:** `cd aws_backend/authorizer && pytest tests/ -v` → FAIL.
- [ ] **Step 3:** Implement as specified in Interfaces.
- [ ] **Step 4:** `pytest tests/ -v` → PASS.
- [ ] **Step 5:** Commit `fix(auth): authorizer verifies applicationId/memberId pair against members table`.

---

### Task 2: `authz.py` caller model

**Files:**
- Create: `aws_backend/lambda/authz.py`
- Create: `aws_backend/lambda/tests/test_authz.py`

**Interfaces:**
- Produces:
  - `@dataclass(frozen=True) class Caller: application_id: str; member_id: str; is_admin: bool; is_spiess: bool; is_super_admin: bool`
  - `get_caller(event: dict) -> Caller` — reads headers `applicationid`/`memberid`, one `get_item` on `MEMBERS_TABLE_NAME`; unknown/missing member → all flags `False`.
  - `forbidden(headers: dict) -> dict` — `{"statusCode": 403, **headers, "body": json.dumps({"error": "Nicht berechtigt"})}` (merge order so that `statusCode`/`body` win).
  - `Caller.can_manage_club(customer_id: str) -> bool` — `is_super_admin or (is_admin and customer_id == application_id)`.

- [ ] **Step 1: Write failing tests:**
  - `test_get_caller_reads_flags`: item `{"isAdmin": True, "isSpiess": False, "isSuperAdmin": True}` → `Caller(..., True, False, True)`
  - `test_get_caller_unknown_member_has_no_roles`: `get_item` returns `{}` → all flags `False`
  - `test_get_caller_missing_memberid_does_not_query`: headers without `memberid` → flags `False`, table not called
  - `test_forbidden_shape`: status 403, body `{"error": "Nicht berechtigt"}`, CORS header preserved
  - `test_can_manage_club`: admin own club `True`; admin other club `False`; super admin other club `True`; plain member own club `False`
- [ ] **Step 2:** `pytest tests/test_authz.py -v` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(auth): add caller/role helper module`.

---

### Task 3: Gate customer routes

**Files:**
- Modify: `aws_backend/lambda/lambda_handler.py` (customers branch of `_dispatch`)
- Test: `aws_backend/lambda/tests/test_lambda_handler_authz.py` (new; mock `authz.get_caller` and `api_customers`)

**Interfaces:**
- Consumes: `authz.get_caller`, `authz.forbidden`, `Caller.can_manage_club` (Task 2).
- Produces: in `_dispatch`, `caller = get_caller(event)` computed once and reused by Tasks 5–7.

Rules:

| Route | Allowed |
|---|---|
| `GET /customers` | super admin |
| `POST /customers` | super admin |
| `GET /customers/{id}` | `id == caller.application_id` or super admin |
| `PUT /customers/{id}` | `caller.can_manage_club(id)` |

- [ ] **Step 1: Write failing tests**, one per row × (allowed caller → 200 and handler called, denied caller → 403 and handler not called). Plus `test_put_other_club_as_admin_forbidden` and `test_put_other_club_as_super_admin_allowed` (Review Focus 2).
- [ ] **Step 2:** `pytest tests/test_lambda_handler_authz.py -v` → FAIL.
- [ ] **Step 3:** Implement the gates in `_dispatch`; `api_customers` functions stay unaware of auth.
- [ ] **Step 4:** `pytest tests/ -v` → all PASS (existing `test_api_customers.py` unchanged).
- [ ] **Step 5:** Commit `fix(auth): restrict customer endpoints to super admins / own club admins`.

---

### Task 4: Safe banner image download (SSRF)

**Files:**
- Modify: `aws_backend/lambda/api_customers.py` (replace `urllib.request.urlopen` call at line ~89)
- Test: `aws_backend/lambda/tests/test_api_customers.py` (new class `TestFetchBannerImage`)

**Interfaces:**
- Produces: `class InvalidImageUrl(ValueError)`; `_fetch_banner_image(url: str) -> bytes`. `update_customer` catches `InvalidImageUrl` and returns `{"statusCode": 400, "body": json.dumps({"error": "Ungültige Bild-URL"})}` without updating the table.

Rules for `_fetch_banner_image`: scheme must be `https`; hostname must not be an IP literal or `localhost`; every address from `socket.getaddrinfo(host, 443)` must satisfy `ipaddress.ip_address(a).is_global`; redirects are not followed (opener with a `HTTPRedirectHandler` subclass whose `redirect_request` raises `InvalidImageUrl`); response `Content-Type` must start with `image/`; read at most `5 * 1024 * 1024 + 1` bytes and reject if larger; timeout 10 s.

- [ ] **Step 1: Write failing tests** (patch `socket.getaddrinfo` and the opener):
  - `test_rejects_http`, `test_rejects_file_scheme`, `test_rejects_ip_literal`, `test_rejects_localhost`
  - `test_rejects_private_resolution` (getaddrinfo → `10.0.0.1`), `test_rejects_link_local` (`169.254.169.254`), `test_rejects_loopback` (`127.0.0.1`)
  - `test_rejects_non_image_content_type` (`text/plain`)
  - `test_rejects_oversized` (5 MiB + 1 byte)
  - `test_accepts_public_https_image` (getaddrinfo → `93.184.216.34`, `image/png`) → returns bytes
  - `test_update_customer_invalid_url_returns_400_and_no_db_write`
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `pytest tests/ -v` → PASS.
- [ ] **Step 5:** Commit `fix(security): restrict banner image download to public https hosts`.

---

### Task 5: Gate monitoring routes

**Files:**
- Modify: `aws_backend/lambda/lambda_handler.py` (monitoring branches)
- Test: `aws_backend/lambda/tests/test_lambda_handler_authz.py`

Rules: `GET /monitoring/stats|startup|perf|errors` → super admin only. `POST /monitoring/timing` → any authorized caller (unchanged).

- [ ] **Step 1: Write failing tests:** for each GET route, plain member → 403, super admin → 200; `test_timing_allowed_for_plain_member` (Review Focus 4).
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** `pytest tests/ -v` → PASS.
- [ ] **Step 5:** Commit `fix(auth): restrict monitoring read endpoints to super admins`.

---

### Task 6: Gate fines, marschbefehl and photos

**Files:**
- Modify: `aws_backend/lambda/lambda_handler.py`
- Test: `aws_backend/lambda/tests/test_lambda_handler_authz.py`

Rules:

| Route | Allowed |
|---|---|
| `GET /fines?memberId=X` | `X == caller.member_id` or spiess or admin |
| `POST /fines`, `DELETE /fines/{id}` | spiess or admin |
| `POST/DELETE /marschbefehl` | admin |
| `GET /marschbefehl`, `GET /photos*`, `POST /photos` | any authorized caller (unchanged) |
| `DELETE /photos/*` | admin |

- [ ] **Step 1: Write failing tests**, allowed + denied per row; `test_get_fines_of_other_member_as_plain_member_forbidden`; `test_delete_fine_uses_caller_application_id` (assert `fines_table.delete_item` key `applicationId == caller.application_id`, Review Focus 5).
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** `pytest tests/ -v` → PASS (existing `test_lambda_handler_fines.py` and `test_photos.py` need `authz.get_caller` patched to an admin caller in their `setUp`; adjust there, not the assertions).
- [ ] **Step 5:** Commit `fix(auth): enforce roles for fines, marschbefehl and photo deletion`.

---

### Task 7: Docs — admin writes, no hardcoded password

**Files:**
- Modify: `aws_backend/lambda/api_docs.py`
- Modify: `aws_backend/lambda_backend.tf` (env `DOCS_PASSWORD = data.aws_secretsmanager_secret_version.docs_password.secret_string`)
- Modify: `aws_backend/secretsmanager.tf` (`aws_secretsmanager_secret "docs_password"` named `docs-password`, plus `data "aws_secretsmanager_secret_version"`; value set manually via AWS console/CLI, never in the repo)
- Test: `aws_backend/lambda/tests/test_api_docs.py`

**Interfaces:**
- Consumes: `authz.get_caller`, `authz.forbidden`.

Rules: remove the `'geheim123'` fallback; empty/unset `DOCS_PASSWORD` → every docs call 401 (fail closed); compare with `hmac.compare_digest`; `POST /docs` and `DELETE /docs/*` additionally require admin (403 otherwise).

- [ ] **Step 1: Write failing tests:** `test_no_password_configured_denies_all`; `test_upload_as_non_admin_forbidden`; `test_delete_as_non_admin_forbidden`; `test_upload_as_admin_with_password_ok`; `test_list_as_member_with_password_ok`.
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** `pytest tests/ -v` → PASS.
- [ ] **Step 5:** Commit `fix(security): docs password from Secrets Manager, admin-only writes`.
- [ ] **Step 6 (operator, before deploy):** create the secret value. To avoid breaking existing invite links, set it to the current value first; rotating it (and regenerating links) is a follow-up in `.claude/TODOS.md`.

---

### Task 8: Verification & deploy

- [ ] **Step 1:** `cd aws_backend/lambda && pytest tests/ -v` and `cd ../authorizer && pytest tests/ -v` → all PASS.
- [ ] **Step 2:** `cd aws_backend && terraform plan` → changes only: authorizer env, backend env `DOCS_PASSWORD`, new secret + data source (Terraform reads the secret at deploy time, so the Lambda role needs no new IAM permission).
- [ ] **Step 3:** Deploy to `dev` stage, smoke test in the app with (a) a plain member: strafen, termine, galerie, dokumente read; (b) a spiess: add/delete fine; (c) an admin: marschbefehl, doc upload; (d) super admin: verein screen, monitoring. Then a curl with a random `memberId` → 403 from the authorizer.
- [ ] **Step 4:** Promote to prod, update `.claude/TODOS.md` (tick Phase-1 items).

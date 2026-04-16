# Multi-Account & Account-Switcher Design

## Goal

Allow users to hold multiple club accounts locally and switch between them. QR code invitations add a new account instead of overwriting the existing one. Super admins are automatically linked to every new club they create.

## Architecture

A thin `AccountStore` layer wraps localStorage. `AppConfig` and all screens are unchanged — only `loadConfig`/`saveConfig` and `main.dart` are updated to work with the new multi-account storage. The active config is still a single `AppConfig` object passed through the widget tree.

## Data Model

Two localStorage keys replace the existing `config` key:

**`accounts`** — JSON array of account objects:
```json
[
  {
    "apiBaseUrl": "https://abc.execute-api.eu-central-1.amazonaws.com",
    "applicationId": "schuetzenlust",
    "memberId": "super123",
    "label": "Schützenlust"
  },
  {
    "apiBaseUrl": "https://abc.execute-api.eu-central-1.amazonaws.com",
    "applicationId": "neuer-verein-uuid",
    "memberId": "super123",
    "label": "Neuer Verein"
  }
]
```

**`activeAccount`** — integer index into the accounts array, defaults to 0.

`loadConfig()` returns `accounts[activeAccount]` as an `AppConfig`. `saveConfig()` updates the active slot. A new `addOrActivateAccount()` function checks for duplicates by `applicationId + memberId` and either sets `activeAccount` to the existing slot or appends and activates.

Migration: on first load, if `config` key exists and `accounts` does not, the old config is migrated into a single-element accounts array.

## Account-Switcher UI

The AppBar title in `HomeScreen` becomes a `TextButton`. Tapping it opens a `BottomSheet` listing all accounts by their `label`. The active account is highlighted. Tapping another account calls `setActiveAccount(index)` and reloads the app:
- Web: `hardReload()` (existing JS interop)
- Native: `Navigator.pushNamedAndRemoveUntil('/', ...)`

## QR Code Flow

`main.dart` already reads `apiBaseUrl`, `applicationId`, `memberId` from URL parameters. With this change, instead of calling `saveConfig()` (which overwrites), it calls `addOrActivateAccount()`. The label is fetched asynchronously from `GET /customers/{applicationId}` after the app starts and stored back into the accounts array.

Duplicate detection: same `applicationId` AND same `memberId` = same account. If only `applicationId` matches but `memberId` differs, it is treated as a new account (different member in the same club).

## New Club Creation (Super Admin)

`POST /customers` response gains two additional fields:

```json
{
  "application_id": "uuid-generated",
  "application_name": "Neuer Verein",
  "api_url": "...",
  "active_screens": [...],
  "member_id": "super123",
  "api_base_url": "https://..."
}
```

The backend reads `member_id` from the `memberid` request header and `api_base_url` from the `API_BASE_URL` environment variable (already present). No new member record is created — the super admin's existing member record (same `memberId`) works in all clubs.

The Flutter `VereinScreen` receives the response, builds an `AccountConfig` from the new fields, and calls `addOrActivateAccount()`. The new account appears immediately in the switcher with the entered club name as label.

## Backend Changes

`api_customers.py` — `create_customer`:
- Read `member_id` from `event['headers'].get('memberid', '')`
- Add `member_id` and `api_base_url` to the returned JSON body

`lambda_backend.tf` — no changes needed (CORS and routes already cover this).

## Flutter Changes

**`lib/config_loader.dart`**
- Add `label` field to `AppConfig`
- Replace `loadConfig` / `saveConfig` / `deleteConfig` with multi-account variants
- Add `addOrActivateAccount(AppConfig)` and `setActiveAccount(int)`
- Add `loadAllAccounts()` returning `List<AppConfig>`
- Migration: auto-migrate old `config` key on first load

**`lib/main.dart`**
- Use `addOrActivateAccount` instead of `saveConfig` for QR code params
- Fetch label asynchronously after load

**`lib/screens/home_screen.dart`**
- AppBar title → `TextButton` opening account-switcher `BottomSheet`
- After switch: reload via `hardReload()` / `pushNamedAndRemoveUntil`

**`lib/screens/verein_screen.dart`**
- After `_api.createCustomer(payload)` succeeds: extract `member_id` + `api_base_url` from response, call `addOrActivateAccount`

**`lib/api/customers_api.dart`**
- No changes needed (returns raw response map as-is)

## Testing

- `config_loader_test.dart`: migrate old config, add account, duplicate detection, set active account
- `test_api_customers.py`: `create_customer` response includes `member_id` and `api_base_url`
- Manual: QR scan adds account; second scan of same QR does not duplicate; new club appears in switcher

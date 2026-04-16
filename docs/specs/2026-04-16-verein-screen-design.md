# Verein Screen Design

## Overview

A new "Verein" settings screen that allows club admins to manage their club's configuration (name, logo, active screens) and super-admins to manage all clubs centrally, including creating new ones.

## Roles

- **Super-admin**: `isSuperAdmin` flag on the member. Can see all clubs in a dropdown, edit any club, and create new clubs.
- **Club admin**: `isAdmin` flag on the member. Can only see and edit their own club's settings.
- **Others**: Screen is not visible.

## Data Model

### `vereinsappell-customers` DynamoDB table — new field

```
active_screens: ["termine", "marschbefehl", "strafen", "dokumente", "galerie", "schere_stein_papier"]
```

Full set of configurable screen keys: `termine`, `marschbefehl`, `strafen`, `dokumente`, `galerie`, `schere_stein_papier`

Role-gated screens (`mitglieder`, `verein`) are not in `active_screens` — governed by `isAdmin`/`isSuperAdmin` flags only.

`spiess` tile visibility requires both `isSpiess === true` AND `"strafen"` in `active_screens`.

If `active_screens` is absent from a customer record, all screens are shown (backwards-compatible default).

### Members DynamoDB table — new field

```
isSuperAdmin: bool
```

Read and written like `isAdmin`.

## Backend

### `api_customers.py` — new functions

- `list_customers()`: scans entire `vereinsappell-customers` table, returns all items (id, name, logo, active_screens, api_url)
- `update_customer(event)`: updates `application_name`, `application_logo`, `active_screens` for a given `application_id`
- `create_customer(event)`: creates a new entry with `application_id` (required), `application_name` (required), `application_logo` (optional), `api_url` (optional — backend defaults to the value of the `API_BASE_URL` environment variable if omitted), `active_screens` (defaults to all six configurable screen keys)

### `lambda_handler.py` — new routes

| Method | Path | Handler |
|--------|------|---------|
| `GET` | `/customers` | `list_customers()` |
| `PUT` | `/customers/{customerId}` | `update_customer()` |
| `POST` | `/customers` | `create_customer()` |

Existing `GET /customers/{customerId}` route stays unchanged.

### `api_members.py`

Add `isSuperAdmin` field: read from DynamoDB and returned in member response; written on member save.

### Authorization

All endpoints use existing `applicationId`/`memberId` header-based auth. Super-admin enforcement (list all / create) is frontend-only for now. Club admins are restricted to their own club by the frontend.

## Frontend

### `lib/api/customers_api.dart`

Three new methods alongside existing `getCustomer`:
- `listCustomers()` → `GET /customers`
- `updateCustomer(String id, Map<String, dynamic> data)` → `PUT /customers/{id}`
- `createCustomer(Map<String, dynamic> data)` → `POST /customers`

### `lib/config_loader.dart` (Member class)

Add `isSuperAdmin` boolean field, read/written like `isAdmin`.

### `lib/screens/verein_screen.dart` — new screen

Extends `DefaultScreen`. Behavior varies by role:

**Super-admin view:**
- Dropdown listing all clubs (loaded from `GET /customers`)
- "New Club" button that opens a create dialog with fields:
  - `application_id` (required, text field)
  - Name (required, text field)
  - API URL (optional, text field — backend uses default if empty)
  - Logo (optional, file picker → base64)
- When a club is selected from the dropdown, its settings load into the edit form

**Club admin view:**
- No dropdown — own club is pre-loaded on screen open
- No "New Club" button

**Shared edit form:**
- Name (text field)
- Logo (file picker showing current logo preview; pick new file to replace)
- Active Screens (toggle list for each of the 6 configurable screen keys)
- Save button — calls `updateCustomer()`

### `lib/screens/home_screen.dart`

**Active screens filtering:** On init, load the customer record via `getCustomer()`. Use `active_screens` to filter the menu tile list. If `active_screens` is absent, show all tiles (backwards-compatible).

**Tile visibility rules:**
- `spiess`: `isSpiess && active_screens.contains("strafen")`
- `mitglieder`: `isAdmin` (unchanged)
- `verein`: `isAdmin || isSuperAdmin` (new tile: "🏛️ Verein")
- All other tiles: `active_screens.contains(key)`

**New tile:** "🏛️ Verein" navigates to `VereinScreen`.

# Abstimmungen Screen — Design Spec

**Date:** 2026-05-07

## Overview

A new screen for polls/votes. Members see all visible polls in a single scrollable list, oldest at top, newest at bottom. Admins can create and edit polls; Super Admins can delete them. All data is stored in Firestore with real-time listeners.

---

## Data Model

### Poll (Firestore: `applications/{appId}/polls/{pollId}`)

| Field | Type | Description |
|---|---|---|
| `id` | String | Firestore document ID |
| `title` | String | Poll title |
| `description` | String? | Optional explanatory text |
| `options` | List<`{id: String, text: String}`> | Answer options |
| `allowMultiple` | bool | If true, members may select more than one option |
| `isActive` | bool | If true, members can vote or change their vote |
| `isVisible` | bool | If true, the poll is shown to all members (even if inactive) |
| `isSecretBallot` | bool | If true, results are hidden until `isActive` becomes false |
| `authorId` | String | Member ID of the creator |
| `createdAt` | Timestamp | Creation time — used for sort order |

### Vote (Firestore: `applications/{appId}/polls/{pollId}/votes/{memberId}`)

| Field | Type | Description |
|---|---|---|
| `memberId` | String | The voting member |
| `optionIds` | List<String> | Selected option IDs |
| `updatedAt` | Timestamp | Last modification time |

---

## Firestore Structure

```
applications/{appId}/
  polls/{pollId}          ← Poll document
    votes/{memberId}      ← Vote subcollection
```

Real-time listeners are attached to both the poll collection and the votes subcollection for the current member. Aggregate vote counts are computed client-side from the votes subcollection (all votes readable by all members; only `memberId` is needed for counts, full content only for non-secret ballots).

---

## Screen: Abstimmungen

### Layout

Single `Scaffold` with:
- `AppBar` with title "Abstimmungen"
- If admin: `IconButton(Icons.add)` in `AppBar.actions` (top right) to create a new poll
- `StreamBuilder` over Firestore poll collection → scrollable `ListView` of poll cards
- Polls sorted by `createdAt` ascending (oldest at top, newest at bottom)
- Only polls with `isVisible: true` are shown to regular members; admins see all polls

### Poll Card

Each poll is rendered as a `Card` with:

**Header row:**
- Title (bold) + optional description below
- Status badge: `● Aktiv` (green) / `⏹ Beendet` (grey)
- If `isSecretBallot`: lock icon 🔒

**Voting area** (only if `isActive: true`):
- List of options as tappable tiles
- Selected option(s) highlighted (checkmark + colored border)
- `allowMultiple: false` → radio-style (selecting one deselects others)
- `allowMultiple: true` → checkbox-style (toggle each option)
- Button: "Stimme abgeben" (if no vote yet) or "Stimme ändern" (if already voted)
- Tapping button writes/updates the Vote document in Firestore

**Results area:**
- Shown when: `isSecretBallot: false` (always) OR `isActive: false` (after poll ends)
- "X von Y haben abgestimmt" subtitle
- For each option: label + horizontal bar (width = share of votes) + absolute count

**Admin actions** (only for `isAdmin` or `isSuperAdmin`):
- Edit icon or long-press opens an edit bottom sheet / dialog
- Edit dialog fields: title, description, options (add/remove), `allowMultiple`, `isActive`, `isVisible`, `isSecretBallot`
- Changing options on a poll that already has votes is allowed; existing votes referencing a deleted option are ignored in count
- Super Admin only: "Abstimmung löschen" button in the edit dialog (deletes poll + all votes)

---

## Create Poll Dialog

Triggered by the `+` icon in the AppBar (admin only). A `showModalBottomSheet` or `showDialog` with:

- Title text field (required)
- Description text field (optional)
- Option list: at least 2 options required; "+" button to add more, swipe-to-delete or trash icon per option
- Toggle: "Mehrfachauswahl erlauben"
- Toggle: "Geheime Wahl"
- Toggle: "Sofort aktivieren" (sets `isActive: true` on creation; default: true)
- Toggle: "Sichtbar" (sets `isVisible: true` on creation; default: true)
- "Erstellen" button → writes to Firestore

---

## Behaviour Details

| Scenario | Behaviour |
|---|---|
| Member votes | Writes `votes/{memberId}` with selected `optionIds` |
| Member changes vote | Overwrites `votes/{memberId}` — allowed only while `isActive: true` |
| Admin sets `isActive: false` | Voting disabled; if `isSecretBallot`, results now become visible |
| Admin sets `isVisible: false` | Poll hidden from member list (remains in Firestore) |
| Admin edits options | Votes referencing removed option IDs are excluded from count |
| Super Admin deletes | Poll document + all vote documents deleted |
| No polls visible | Empty-state message: "Keine Abstimmungen vorhanden" |

---

## Navigation & Integration

- New menu tile in `home_screen.dart`: `📊 Abstimmungen`
- Controlled by `_isScreenActive('abstimmungen')` (existing pattern)
- Screen key: `'abstimmungen'`

---

## Out of Scope

- Push notifications for new polls
- Deadlines / expiry dates (handled manually via `isActive`)
- Role-restricted voting (all active members can vote)
- Result export

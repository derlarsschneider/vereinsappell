# Getränke Screen — Design Spec

## Overview

A new "Getränke" screen accessible from the home screen. All members can add tally marks (Striche) or bottle marks (Flaschen) per drink. Members with `isSaftschubse` can reset all marks. All members see live updates.

## Drinks

| Drink | Emoji | Strich button | Flasche button |
|-------|-------|---------------|----------------|
| Alt | 🍺 | 🍺 | — |
| Pils | 🍻 | 🍺 | — |
| Cola | 🥤 | 🥤 | 🍾 |
| Fanta | 🥤 | 🥤 | 🍾 |
| Sprite | 🥤 | 🥤 | 🍾 |
| Cola Zero | 🥤 | 🥤 | 🍾 |
| Wasser | 💧 | 🫗 | 🍾 |

## UI Design

Each drink is displayed as a "Bierdeckel" card:
- Header row: drink emoji + name + tally marks inline
- Tally marks: classic 5-group style (4 vertical sticks + diagonal cross). Own marks in red, others in black. Bottle marks shown as 🍾 symbol inline in the tally row. Empty tally area is blank (no placeholder text).
- Buttons below: glass emoji (always) + bottle emoji (Cola, Fanta, Sprite, Cola Zero, Wasser only). Both buttons equal size.

If `isSaftschubse`: a red "Alle Striche löschen" button appears at the top of the screen, with a confirmation dialog before executing.

## Architecture

### Real-time: Firebase Realtime Database (direct write from Flutter)

Flutter writes directly to Firebase Realtime Database. No Lambda intermediary needed. Flutter listens via `.onValue` stream for live updates.

### Firebase Data Model

```
tallies/
  {applicationId}/
    {drinkId}/           # "alt", "pils", "cola", "fanta", "sprite", "cola_zero", "wasser"
      {entryId}/
        memberId: string
        type: "strich" | "flasche"
        timestamp: number
```

Each tap creates a new entry. Saftschubse reset = delete entire `tallies/{applicationId}` path.

### Firebase Security Rules

Open read/write restricted by `applicationId` path structure. Acceptable for an internal club screen; Firebase Auth is not used in this app.

### Flutter Package

Add `firebase_database` to `pubspec.yaml`. Firebase is already configured in the project (`google-services.json` present).

## Components

### `GetraenkeScreen`
- Extends `DefaultScreen`
- Subscribes to `watchTallies(applicationId)` stream on init
- Renders 7 `BierdeckelCard` widgets
- Shows reset button at top if `member.isSaftschubse`

### `GetraenkeApi`
- `addMark(applicationId, drinkId, memberId, type)` — push new entry to Firebase
- `clearAll(applicationId)` — delete `tallies/{applicationId}` path
- `watchTallies(applicationId)` → `Stream<Map>` — live Firebase stream

### `BierdeckelCard`
- Stateless widget receiving drink data + current user's memberId
- Renders tally marks: 5-groups with diagonal, own marks in red, bottle marks as 🍾 inline
- Two buttons (or one for beer): equal size, filled + outlined style

### Home Screen
- New tile `🍺 Getränke` in `_buildGridMenu`
- Controlled via `active_screens` key `"getraenke"`

## Member Model Changes

### Backend (DynamoDB / Lambda)
- New field `isSaftschubse: bool` on member items (missing = `false`)
- `api_members.py` / `handle_members`: read and write `isSaftschubse`

### Flutter (`Member` class in `config_loader.dart`)
- New `_isSaftschubse` field with getter/setter
- Included in `updateMember()` and `encodeMember()`

### Admin UI (`MitgliederScreen`)
- New toggle for `isSaftschubse` when editing a member

## Edge Cases

- **Empty tally:** Card tally area is blank.
- **Offline:** Firebase SDK buffers writes locally; marks are not lost on short disconnects.
- **Connection error:** Show error via existing `showError()` SnackBar.
- **isSaftschubse missing on old members:** Defaults to `false`, no migration needed.
- **Reset confirmation:** Dialog shown before clearing all marks.
- **iOS:** `firebase_database` plugin supports iOS. `GoogleService-Info.plist` setup is out of scope for this ticket.

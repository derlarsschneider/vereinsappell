# Umlage Screen Design

**Date:** 2026-05-22  
**Status:** Approved

## Summary

New screen for collecting Vereins-Umlagen (member levies). A new `isGeldeintreiber` flag identifies levy collectors. The screen has three tabs and uses Firebase Realtime Database for live persistence. All active members can view the screen; only collectors can manage their own active collection.

---

## Data Model (Firebase Realtime Database)

```
umlagen/
  {applicationId}/
    active/
      {collectorMemberId}/
        amount: 20                        // selected banknote denomination
        name: "Vereinsfest Mai"           // or auto-name "Umlage 22.05.2026 19:32"
        startedAt: 1748000000000          // unix ms timestamp
        participants/
          {memberId}: "pending" | "paid" | "excluded"
    history/
      {pushId}/
        collectorId: "member123"
        amount: 20
        name: "Jahresfeier 2025"
        startedAt: 1748000000000
        closedAt: 1748003600000
        totalPaid: 220
        participants/
          {memberId}: "paid" | "excluded"
    stats/
      {memberId}/
        totalCollected: 500               // sum of totalPaid across all closed collections by this member
        collectionsCount: 12              // number of closed collections by this member
```

**Key decisions:**
- `active/{collectorId}` — exactly one active Umlage per collector; starting a new one overwrites the previous (after explicit confirmation).
- `history/` — Firebase push key as ID; immutable after closing.
- `stats/` — atomically incremented via `update()` when closing a collection.
- All reads use `onValue` streams for live updates without polling.

---

## Member Flag

New boolean field `isGeldeintreiber` added to the `Member` class in `config_loader.dart`, parallel to existing flags (`isSpiess`, `isAdmin`, `isSaftschubse`).

- Stored and fetched via the existing members API.
- Editable in `mitglieder_screen.dart` via a new `SwitchListTile`.
- Controls tab visibility and default tab on screen open.

---

## Navigation & Home Integration

- New menu tile `'💶 Umlagen'` in `home_screen.dart`, gated behind `_isScreenActive('umlagen')`.
- `'umlagen'` added to the active screens list in `verein_screen.dart`.
- Default tab on open: "Meine Sammlung" if `isGeldeintreiber`, otherwise "Alle aktiven".

---

## Screen: UmlagenScreen (3 Tabs)

### Tab 1 — "Meine Sammlung" (collectors only)

**State A — No active Umlage:**
- Centered start button.
- Banknote picker (€5 / €10 / €20 / €50) + optional name text field.
- Tapping start writes to `active/{collectorMemberId}` with all active members as `"pending"`.
- Auto-name format: `"Umlage DD.MM.YYYY HH:mm"` if name left empty.

**State B — Active Umlage running:**

*Header area:*
- Banknote picker — denomination locked once at least one member has paid (to prevent inconsistency).
- Progress bar + label: "X von Y bezahlt · €Z gesammelt".
- Animated background: linear gradient from red (0% paid) to green (100% paid).
- Green border overlay when all participants have paid.

*Member list (alphabetical, active members only):*
- Tap → mark as `"paid"`, item turns green with ✅ checkmark.
- Tap again → revert to `"pending"`.
- Swipe (left or right) → mark as `"excluded"`: red ❌ briefly flashes, item disappears from list. Excluded members do not count toward the progress total.

*Footer:*
- "Umlage abschließen" button → writes entry to `history/`, atomically updates `stats/`, deletes `active/{collectorMemberId}`.
- Confirmation dialog before closing if unpaid members remain.

**State C — Non-collector:**
- Tab not shown.

---

### Tab 2 — "Alle aktiven" (all members, read-only)

- Streams all entries under `active/` for the current `applicationId`.
- One card per active Umlage:
  - Collector name, Umlage name, denomination (€ per person).
  - Mini progress bar (paid / total participants).
  - Badge: "✅ Du hast bezahlt" or "⬜ Du hast noch nicht bezahlt".
- No interactive elements — purely informational.
- Empty state: "Aktuell läuft keine Umlage."

---

### Tab 3 — "Abgeschlossen" (all members, read-only)

- Reads `history/` for current `applicationId`, sorted by `closedAt` descending.
- Initial load: 20 entries. "Mehr anzeigen" button loads additional 20.
- Per entry:
  - Name (or auto-name), date, collector name, total amount collected.
  - Green dot (✅) if `participants/{currentMemberId} == "paid"`, red dot (❌) otherwise.

---

## New API: UmlagenApi

New file `lib/api/umlagen_api.dart` wrapping Firebase Realtime Database calls:

| Method | Description |
|---|---|
| `Stream<UmlageSession?> watchActiveSession(collectorId)` | Live stream of one collector's active session |
| `Stream<List<UmlageSession>> watchAllActive()` | Live stream of all active sessions |
| `Future<void> startSession(UmlageSession)` | Write to `active/` |
| `Future<void> updateParticipant(collectorId, memberId, status)` | Update one participant's status |
| `Future<void> closeSession(collectorId)` | Move to `history/`, update `stats/`, delete from `active/` |
| `Future<List<HistoryEntry>> fetchHistory({int limit, String? startAfter})` | Paginated history read |

---

## New Model: UmlageSession

New file `lib/models/umlage.dart`:

```dart
class UmlageSession {
  final String collectorId;
  final int amount;
  final String name;
  final int startedAt;
  final Map<String, String> participants; // memberId → "pending"|"paid"|"excluded"
}

class HistoryEntry {
  final String id;
  final String collectorId;
  final int amount;
  final String name;
  final int startedAt;
  final int closedAt;
  final int totalPaid;
  final Map<String, String> participants;
}
```

---

## Out of Scope

- Push notifications when a new Umlage starts.
- Editing a closed history entry.
- Exporting history as PDF/CSV.
- Multiple simultaneous active Umlagen per collector.

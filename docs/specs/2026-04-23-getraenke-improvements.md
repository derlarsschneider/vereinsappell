# Getränke Screen — Improvements Spec

## Overview

Two improvements to the existing Getränke screen:

1. **Layout restructuring:** Single-line layout per drink with drink info on left, buttons on right (buttons narrower)
2. **Delete own marks:** Members can tap their own tally marks (sticks and bottles) to remove them one at a time

## UI Changes

### Card Layout

Each `BierdeckelCard` is restructured from a two-row layout (header row + button row) to a single line:
- **Left section:** Drink emoji + name + tally marks (inline, exactly as current header row)
- **Right section:** Action buttons (Strich button + optional Flasche button, narrower)
- Buttons no longer span full width

### Mark Interaction

**Tappable marks:**
- Your own sticks (red) — tap to delete
- Your own bottle marks (red) — tap to delete
- Other members' sticks (black) — read-only
- Other members' bottle marks (black/uncolored) — read-only

**Deletion behavior:**
- Single tap deletes that entry immediately
- No confirmation dialog
- Firebase entry is removed
- UI updates live via stream

### Visual Changes

- Own bottle marks are colored red (matching own sticks) for consistency
- Buttons visually smaller due to narrower layout

## Architecture

### Components

**`BierdeckelCard`** (modified)
- Layout restructured using `Row` instead of `Column`
- Each mark in `_TallyRow` wrapped to identify owner and type
- Red marks wrapped in `GestureDetector` with `onTap` callback

**`_TallyRow`** (modified)
- Returns list of `Widget`s instead of raw widgets
- Each mark widget includes owner/type metadata for hit detection
- Bottle marks rendered with red `TextStyle(color: red)` for own marks

**`GetraenkeApi`** (new method)
- `deleteMark(drinkId, entryId)` — removes specific entry from Firebase
- Calls `ref.child(drinkId).child(entryId).remove()`

**`_GetraenkeScreenState`** (modified)
- Passes `deleteMark` callback to `BierdeckelCard`
- Error handling for failed deletes (SnackBar via `showError`)

### Firebase Changes

No schema changes. Deletion uses the existing `DatabaseReference.remove()` on the individual entry node.

## Edge Cases

- **Delete during refresh:** Firebase handles eventual consistency; entry simply doesn't exist in next update
- **User deletes own mark while others edit same drink:** No conflict; each edit is independent
- **No undo:** Single-mark deletions are low-risk; users can immediately re-add if needed
- **Offline delete attempt:** Firebase SDK queues the operation locally; syncs on reconnect

## Testing

- Widget test: `_TallyRow` renders red marks for own entries
- Widget test: Tapping own mark calls deletion callback
- Integration test: Delete mark updates Firebase and refreshes UI

## Implementation Order

1. Restructure `BierdeckelCard` layout (row instead of column)
2. Update `_TallyRow` to support tappable marks with owner/type info
3. Add `deleteMark()` to `GetraenkeApi`
4. Wire callbacks in `_GetraenkeScreenState`
5. Add red color to own bottle marks
6. Test and verify

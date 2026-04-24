# Getränke Screen Redesign

## Summary

Redesign of `BierdeckelCard` to fix the tally-mark overflow problem (own + others' marks rendered as separate colored sticks side by side) and replace the single emoji tap-button with explicit +/− controls. Own count is surfaced as a notification badge on the card border.

## Current Problems

1. **Overflow**: Red (own) and black (others') tally marks are rendered in the same `Wrap`, allowing 8+ individual sticks side by side when both counts are non-zero.
2. **Ambiguous delete UX**: Tapping a tally mark deletes it — not discoverable and easy to trigger accidentally.
3. **No quick own-count summary**: Users must count their own marks visually.

## Design

### BierdeckelCard Layout

```
┌─────────────────────────────────────────┐  ← badge on top border
│  🍺 Alt                    [−] 🍺 [+]  │
│  ╫╫╫ ╫╫╫ ╫                             │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐  ← badge "2🥤·1🍾"
│  🥤 Cola           [−] 🥤 [+]          │
│  ╫ ╫ 🍾 🍾         [−] 🍾 [+]          │
└─────────────────────────────────────────┘
```

### Tally Area (left/center)

- Shows **total** count across all members (own + others combined).
- Single color for all marks — no red/black distinction.
- Tally sticks grouped in fives with diagonal, exactly as today.
- Bottle emoji (`🍾`) rendered inline after sticks for **total** bottle count.
- No tap-to-delete on marks.

### Buttons (right column)

- Drinks without bottle (`hasBottle == false`): one row — `[−] buttonEmoji [+]`
- Drinks with bottle (`hasBottle == true`): two rows — `[−] 🥤 [+]` and `[−] 🍾 [+]`
- `−` button: white circle with brown border (same style as current outlined button).
- `+` button: filled brown circle (same style as current filled button).
- Tapping `−` deletes the most recent own entry of that type (same backend call as current tap-to-delete).
- `−` button is disabled / no-op when own count for that type is 0.

### Own-Count Badge

- Positioned `top: -10px, right: 14px` — sits on the top border of the card.
- Red pill (`#E53935`), white text, white border (to lift off the card background), subtle shadow.
- **Content**:
  - Only striche, no bottles: `"3"`
  - Only bottles, no striche: `"1🍾"`
  - Both: `"2🥤·1🍾"`
  - Own count == 0: badge is hidden entirely.
- For drinks without bottle support, badge shows strich count only.

## Data Flow

No changes to `GetraenkeApi` or `TallyEntry`. The screen continues to receive a flat `List<TallyEntry>` and derives counts locally:

- `totalStriche` = entries where `type == 'strich'`
- `totalFlaschen` = entries where `type == 'flasche'`
- `myStriche` = entries where `type == 'strich' && memberId == myMemberId`
- `myFlaschen` = entries where `type == 'flasche' && memberId == myMemberId`

The `−` button calls `onDeleteMark` with the id of the most recent own entry of that type (sorted by timestamp descending).

## What Changes

| Component | Change |
|---|---|
| `BierdeckelCard` | New layout: badge, unified tally, +/− buttons |
| `_TallyRow` | Renders total (not split by member); no color distinction; includes bottle emojis |
| `_TallyButton` | Replaced by two `IconButton`-style +/− widgets |
| New `_OwnBadge` widget | Renders the count pill, hidden when count is 0 |

## What Stays the Same

- `GetraenkeApi`, `TallyEntry`, Firebase structure
- Bierdeckel gradient, border, border-radius, shadow
- Tally group of 5 with diagonal stroke
- `GetraenkeScreen` state management and stream subscription
- Saftschubse reset button

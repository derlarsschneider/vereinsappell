# Marschbefehl Auto-Scroll Design

## Goal

When the Marschbefehl screen loads, automatically scroll with animation to the first upcoming entry so that past entries are not immediately visible, but can be reached by scrolling up.

## Behavior

- On initial load only (not on pull-to-refresh), the list animates to the first entry whose `datetime >= now` (truncated to minute precision).
- If all entries are in the past, no auto-scroll occurs.
- Past entries remain accessible by scrolling up.

## Datetime Comparison

`DateTime.now()` is truncated to minute precision before comparison:

```dart
final now = DateTime.now();
final nowByMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute);
```

This ensures that at e.g. 09:00:54 the 09:00 entry is still treated as the next upcoming entry.

## Implementation

**File:** `lib/screens/marschbefehl_screen.dart`

### Changes

1. **Replace `ListView.builder` with `ListView`** — All items are rendered upfront so Flutter knows their exact render positions.

2. **Add `GlobalKey _nextItemKey`** — Assigned to the card of the first upcoming entry. If no upcoming entry exists, the key is unused and no scroll is triggered.

3. **Auto-scroll after initial load** — In `_fetchMarschbefehl`, after the initial `setState`, register a `WidgetsBinding.instance.addPostFrameCallback` that calls:

   ```dart
   Scrollable.ensureVisible(
     _nextItemKey.currentContext!,
     duration: const Duration(milliseconds: 600),
     curve: Curves.easeInOut,
     alignment: 0.0,
   )
   ```

   `alignment: 0.0` positions the target item at the top of the viewport.

4. **No scroll on refresh** — A `bool _initialLoadDone` flag prevents re-triggering auto-scroll on subsequent refreshes.

## Edge Cases

| Situation | Behavior |
|---|---|
| All entries in the past | No auto-scroll |
| All entries in the future | Scrolls to index 0 (already visible, no-op) |
| Empty list | No auto-scroll |
| Pull-to-refresh | No auto-scroll |

# Design: Monitoring Screen Improvements

## Overview

Improve the existing `MonitoringScreen` for super-admin/developer use. The screen currently has unlabeled axes, no summary metrics, missing startup stats UI, and no endpoint or per-member breakdown.

## Target User

Super-admin / developer. Technical depth is prioritized over simplicity.

---

## Screen Layout

Dashboard-Grid layout: summary tiles at top, scrollable charts below.

### Header Controls (always visible)
- **Timeframe selector** (existing): Min · Std · Tag · Woche
- **Global club filter** (new): Dropdown "Alle Vereine" + one entry per `applicationId` from the loaded data. Affects the Endpoint and Member charts only — the Club chart always shows all clubs.

### Summary Tiles (3 tiles in a row)
| Tile | Value | Source |
|------|-------|--------|
| API Calls gesamt | Sum of all `calls_per_club[].count` | computed client-side |
| Aktive Vereine | Count of distinct `applicationId` entries | computed client-side |
| Ø Startup p50 | Average of all `startup_stats[].p50` | computed client-side |

### Charts (horizontal bar charts, scrollable)

All charts use horizontal bars: Y-axis = category label, X-axis = call count. Each bar shows the numeric value at its right end.

**1. API Calls pro Verein**
- Data: `calls_per_club` (all entries, not affected by club filter)
- Y-axis label: Verein (applicationId)
- X-axis label: Anzahl Aufrufe
- Bar color: blue (#89b4fa)
- Sorted descending by count

**2. API Calls pro Endpunkt**
- Data: `calls_per_endpoint`, filtered client-side by selected club (or all if "Alle Vereine")
- Y-axis label: Endpunkt (path)
- X-axis label: Anzahl Aufrufe
- Bar color: purple (#cba6f7)
- Subtitle shows active filter: "(Alle Vereine)" or "(TZG)"
- Sorted descending by count

**3. API Calls pro Member**
- Data: `calls_per_member`, filtered client-side by selected club (or all if "Alle Vereine")
- Y-axis label: Member-ID
- X-axis label: Anzahl Aufrufe
- Bar color: red (#f38ba8)
- Subtitle shows active filter
- Sorted descending by count

### Startup-Zeiten Tabelle
- Data: `startup_stats` (existing, currently loaded but not rendered)
- Columns: Member-ID, p50, p95, p99, Starts
- p50 colored green, p95 yellow, p99 red
- Sorted by p50 ascending

---

## Backend Changes

### `aws_backend/lambda/api_monitoring.py` — `handle_monitoring()`

Extend the CloudWatch Logs Insights query to also fetch `path`:

```
fields applicationId, memberId, path, @timestamp
| filter log_type = "api_access"
| sort @timestamp desc
```

Extend the aggregation loop to additionally build `calls_per_endpoint` and `calls_per_member`:

```python
calls_per_endpoint[path] = calls_per_endpoint.get(path, 0) + 1  # global (for "all clubs")
calls_per_endpoint_by_club[app_id][path] = ...                   # per-club
calls_per_member[app_id][mem_id] = ...                           # per-club member counts
```

Return shape (added fields highlighted):

```json
{
  "calls_per_club": [{"applicationId": "TZG", "count": 450}],
  "calls_per_endpoint": [{"applicationId": "TZG", "path": "/members", "count": 310}],
  "calls_per_member":   [{"applicationId": "TZG", "memberId": "m001", "count": 198}],
  "active_members": [...],
  "timeframe": "day"
}
```

`calls_per_endpoint` and `calls_per_member` include the `applicationId` field so the client can filter.

---

## Frontend Changes

### `lib/api/monitoring_api.dart`

`getStats()` already returns `Map<String, dynamic>` — no signature change needed.

### `lib/screens/monitoring_screen.dart`

1. **State**: add `String? _selectedClub` (null = all clubs).
2. **Club filter dropdown**: derive available clubs from `_stats['calls_per_club']`; show as `DropdownButton<String?>` with "Alle Vereine" as null option. Place in a Row next to the existing timeframe selector.
3. **Summary tiles**: new `_buildSummaryTiles()` widget, computed from loaded data.
4. **Replace `_buildCallsChart()`** with a horizontal bar chart version using `fl_chart`'s `BarChart` with `BarChartData(barGroups: ..., titlesData: ...)` where left titles show category labels and bottom titles show counts.
5. **Add `_buildEndpointChart()`**: same horizontal bar pattern, filters `calls_per_endpoint` by `_selectedClub`.
6. **Add `_buildMemberChart()`**: same horizontal bar pattern, filters `calls_per_member` by `_selectedClub`.
7. **Add `_buildStartupTable()`**: `DataTable` or manual `Table` widget rendering `startup_stats` with color-coded p50/p95/p99 cells.
8. **Remove `_buildActiveMembersSection()`**: replaced by `_buildMemberChart()` — the expansion tile list adds no value once a chart shows the same data.

### Helper: `_buildHorizontalBarChart()`

fl_chart's `BarChart` is vertical-only. The horizontal bar layout (label | bar | count) is implemented as a custom widget — no chart library needed for this pattern:

```dart
Widget _buildHorizontalBarChart({
  required String title,
  String? subtitle,
  required List<MapEntry<String, int>> entries, // label → count, pre-sorted descending
  required Color barColor,
})
```

Each row: `Row` with a fixed-width label `Text`, a `Flexible` `LinearProgressIndicator` (value = count / maxCount), and a fixed-width count `Text`. Wrapped in a `Card` with the title and optional subtitle above.

---

## Data Flow

```
_loadData()
  → GET /monitoring/stats?timeframe=X
  → setState(_stats, _startupStats)

_selectedClub changes (dropdown)
  → setState(_selectedClub)   // no network call, client-side filter

_buildEndpointChart()
  → filter _stats['calls_per_endpoint'] where applicationId == _selectedClub (or all)
  → pass to _buildHorizontalBarChart()
```

---

## Out of Scope

- Time-series line charts (current data model is aggregates, not time-bucketed)
- Per-endpoint startup timing breakdown
- Push notifications or alerts on thresholds

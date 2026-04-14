# Design: Erinnerungsbenachrichtigungen für Kalendertermine

**Datum:** 2026-04-14
**Status:** Approved

## Zusammenfassung

Jedes Mitglied kann in der App Erinnerungen für Kalendertermine aktivieren und einen festen Zeitraum vor dem Termin wählen. Ein stündlich laufender AWS-Lambda schickt die FCM-Push-Notifications zur richtigen Zeit.

---

## Datenmodell

### Member-Record (DynamoDB + Dart)

Zwei neue optionale Felder im bestehenden Members-DynamoDB-Eintrag:

| Feld | Typ | Default | Werte |
|---|---|---|---|
| `reminderEnabled` | bool | `true` (wenn nicht gesetzt) | `true / false` |
| `reminderHoursBefore` | int | `24` (wenn nicht gesetzt) | `2, 6, 24, 48` |

Die bestehenden Methoden `saveMember()` und `encodeMember()` in der Dart-`Member`-Klasse werden um diese Felder erweitert. Kein neuer API-Endpunkt notwendig.

### Neue DynamoDB-Tabelle: `reminders_sent`

Verhindert doppelte Benachrichtigungen (z.B. bei Lambda-Retries).

- **PK:** `memberId` (String)
- **SK:** `eventId` (String — die UID aus dem ICS-Eintrag)
- **`ttl`** (Number) — Unix-Timestamp 7 Tage nach Terminbeginn; DynamoDB löscht den Eintrag automatisch

---

## Backend

### Neue Datei: `api_reminders.py`

Funktion `check_reminders(event, context)`:

1. Heutiges ICS-File aus S3 laden (gleiche Logik wie `api_calendar.py`)
2. Alle `VEVENT`-Einträge parsen → `(uid, dtstart, summary)` extrahieren
3. Alle Mitglieder aus DynamoDB scannen
4. Für jedes Mitglied mit `reminderEnabled=True` und gültigem FCM-Token (`token != ""`):
   - `hours_until = (dtstart - now).total_seconds() / 3600`
   - Trifft zu wenn: `reminderHoursBefore - 1 ≤ hours_until < reminderHoursBefore`
   - Dedup-Check: `reminders_sent.get_item(memberId, uid)` — überspringen wenn vorhanden
   - FCM-Notification senden via bestehendes `send_push_notification()`
   - Dedup-Eintrag schreiben: `reminders_sent.put_item(memberId, uid, ttl)`

**Notification-Inhalt:**
```json
{
  "title": "Erinnerung: <summary>",
  "body": "Termin am <dtstart formatted>",
  "type": "reminder"
}
```

### EventBridge-Cron

- Neues `aws_cloudwatch_event_rule` in Terraform: `rate(1 hour)`
- Ruft `check_reminders` auf — entweder als separater Lambda-Handler oder als neuer Entry-Point in der bestehenden Lambda (via neuem `source` im Event).
- Separat von der bestehenden API-Lambda empfohlen, um Timeouts zu vermeiden (Members-Scan kann bei vielen Mitgliedern länger dauern).

### Matching-Logik im Detail

Bei stündlichem Lauf um z.B. 14:05 Uhr:
- `hours_until` für Termin um 15:00 Uhr am nächsten Tag ≈ 24.9h
- Mitglied mit `reminderHoursBefore=24`: Fenster ist `[23, 24)` → kein Treffer
- Lauf um 15:05 Uhr: `hours_until` ≈ 23.9h → Treffer ✓

Die Dedup-Tabelle fängt Edge-Cases ab (Lambda-Retry, zwei Läufe in Folge wegen Timing).

---

## Flutter UI

### Einstieg

Zahnrad-Icon (`Icons.settings`) in der AppBar des `CalendarScreen` → öffnet `AlertDialog`.

Die Dialog-Logik wird als eigenständige Methode/Widget implementiert, damit sie später auch aus dem Marschbefehl-Screen aufgerufen werden kann.

### Dialog

```
┌─ Erinnerungseinstellungen ──────────────────┐
│  Erinnerungen aktivieren         [Toggle ON] │
│                                              │
│  Wie lange vorher?               (nur wenn   │
│  ○ 2 Stunden                      Toggle an) │
│  ○ 6 Stunden                                 │
│  ● 1 Tag                                     │
│  ○ 2 Tage                                    │
│                                  [Speichern] │
└──────────────────────────────────────────────┘
```

- **Toggle aus** → RadioGroup versteckt
- **Speichern:** `member.reminderEnabled` und `member.reminderHoursBefore` setzen → `member.saveMember()` → Dialog schließen → `showInfo('Einstellungen gespeichert')`
- **Fehler beim Speichern:** `showError(...)` im Dialog

### Member-Klasse (Dart)

Zwei neue private Felder mit Gettern/Settern analog zu bestehenden Feldern:

```dart
bool _reminderEnabled = true;
int _reminderHoursBefore = 24;

bool get reminderEnabled => _reminderEnabled;
int get reminderHoursBefore => _reminderHoursBefore;
set reminderEnabled(bool v) => _reminderEnabled = v;
set reminderHoursBefore(int v) => _reminderHoursBefore = v;
```

`updateMember()` liest die Felder aus dem JSON (mit Defaults wenn nicht vorhanden).
`encodeMember()` schreibt beide Felder immer mit raus.

---

## Nicht im Scope

- Marschbefehl-Erinnerungen (explizit für später vorgesehen)
- Erinnerungen für vergangene Termine überspringen (Lambda prüft nur positive `hours_until`)
- Opt-in/Opt-out je einzelnem Termin
- iOS/Android native Notification-Permissions (bestehende TODO in CLAUDE.md)

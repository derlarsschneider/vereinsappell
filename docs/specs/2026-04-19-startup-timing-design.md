# Startup-Time Messung & Monitoring

**Datum:** 2026-04-19  
**Status:** Approved

## Ziel

Startup-Zeiten der Web-PWA pro Mitglied messen, ans Backend senden (ohne Frontend-Performance zu beeinträchtigen) und im bestehenden Monitoring-Dashboard auswertbar machen. Optimierungen folgen datenbasiert in einem späteren Schritt.

---

## Gemessene Phasen

| Phase | Von → Bis | Typ |
|---|---|---|
| `firebase_ms` | `main()` start → `Firebase.initializeApp()` done | awaited, potenziell 0–10 s |
| `config_ms` | Firebase done → `loadConfig()` done | awaited, localStorage ≈ schnell |
| `first_frame_ms` | `runApp()` → erstes Frame gerendert | Flutter-Framework-Overhead |
| `fetch_member_ms` | `initState()` → `fetchMember()` done | API-Call |
| `get_customer_ms` | `initState()` → `getCustomer()` done | API-Call, parallel zu fetch_member |
| `total_ms` | `main()` start → `fetchMember()` done | Summe der wahrnehmbaren Wartezeit |

`total_ms` entspricht dem Zeitpunkt, an dem die UI vollständig befüllt ist.

---

## Architektur

### Frontend

**Neues Modul: `lib/utils/startup_timer.dart`**

- Globales Singleton `StartupTimer`
- Intern: ein `Stopwatch`, gestartet beim ersten Aufruf in `main()`
- Methode `mark(String phase)` → speichert Millisekunden seit Start in einer Map
- Methode `send(AppConfig config)` → fire-and-forget `POST /monitoring/timing`; wirft nie (Fehler werden geloggt, nicht weitergegeben)
- Im Debug-Mode: zusätzlich `console.log` jeder Phase

**Instrumentierungspunkte:**

```
main()
  StartupTimer.instance.start()
  await Firebase.initializeApp()  → mark('firebase')
  await loadConfig()              → mark('config')
  runApp()
    WidgetsBinding.addPostFrameCallback → mark('first_frame')

HomeScreen.initState()
  // Both run in parallel; send() fires after both complete
  Future.wait([
    fetchMember().then((_) {
      mark('fetch_member')
      registerPushSubscriptionWeb()
    }),
    getCustomer().then((_) → mark('get_customer')),
  ]).then((_) => StartupTimer.instance.send(config))   // fire-and-forget
   .catchError((_) => StartupTimer.instance.send(config)) // send even on partial failure
```

**Payload (`POST /monitoring/timing`):**

```json
{
  "applicationId": "...",
  "memberId": "...",
  "phases": {
    "firebase_ms": 1200,
    "config_ms": 8,
    "first_frame_ms": 180,
    "fetch_member_ms": 420,
    "get_customer_ms": 390
  },
  "total_ms": 1808
}
```

Auth: Standard `headers(config)` (applicationId, memberId, password) — nach `loadConfig()` verfügbar.

---

### Backend

**`lambda_handler.py`:** Neuer Route-Eintrag:
```python
elif method == 'POST' and path == '/monitoring/timing':
    import api_monitoring
    return {**headers, **api_monitoring.handle_timing(event, context)}
```

**`api_monitoring.py` — neue Funktion `handle_timing`:**
- Liest Body, validiert Felder (applicationId, memberId, phases, total_ms)
- Schreibt einen strukturierten CloudWatch-Log-Eintrag:
  ```json
  {
    "log_type": "startup_timing",
    "applicationId": "...",
    "memberId": "...",
    "firebase_ms": 1200,
    "config_ms": 8,
    "first_frame_ms": 180,
    "fetch_member_ms": 420,
    "get_customer_ms": 390,
    "total_ms": 1808,
    "timestamp": "2026-04-19T12:00:00"
  }
  ```
- Gibt `200 OK` zurück; kein DynamoDB-Schreibzugriff nötig
- Kein neues IAM-Policy-Recht nötig (nur `print()` → CloudWatch, bereits erlaubt)

---

### MonitoringScreen — neue Sektion "Startup-Zeiten"

**Backend-Query (CloudWatch Insights):**
```
fields applicationId, memberId, total_ms, firebase_ms, fetch_member_ms, @timestamp
| filter log_type = "startup_timing"
| sort @timestamp desc
```

Aggregation im Python-Handler: p50/p95/p99 von `total_ms` pro `memberId`.

**UI-Erweiterung in `monitoring_screen.dart`:**
- Neue Sektion unter den bestehenden Charts
- Tabelle: `memberId | Verein | p50 | p95 | Messungen | Letzte Messung`
- Aufklappbar pro Member: Phase-Breakdown (firebase / config / first_frame / fetch_member / get_customer)
- Nutzt denselben Timeframe-Selector wie die bestehenden Charts

---

## Was nicht geändert wird

- Keine Änderung an der Startup-Logik selbst (Optimierungen folgen später)
- Keine neuen Terraform-Ressourcen (kein neues Lambda, keine neue API-Route im Infra — nur neuer Code-Pfad im bestehenden Lambda)
- Kein neues IAM-Recht erforderlich

---

## Offene Fragen / Abgrenzung

- `registerPushSubscriptionWeb` wird nicht gemessen (läuft nach der wahrnehmbaren Wartezeit, Nutzer sieht bereits die UI)
- Timing-Daten werden nur auf Web (`kIsWeb`) gesendet, da iOS/Android nicht im Scope
- Fehler beim Senden der Timing-Daten werden still geloggt, nie dem User angezeigt

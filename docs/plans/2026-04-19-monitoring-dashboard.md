# Plan: Monitoring Dashboard (Single Page)

## 1. Zielsetzung
Aufbau einer Monitoring-Oberfläche zur Überwachung der Systemnutzung und Mitgliederaktivität.
Die Oberfläche soll ausschließlich für berechtigte Administratoren (Super-Admins) zugänglich sein und folgende Insights bieten:
- **API-Aufrufe pro Verein:** Aggregiert nach Minute, Stunde, Tag, Woche, Monat, Jahr.
- **Mitgliederaktivität:** Identifikation der aktiven Mitglieder in den Zeiträumen (letzte Minute, Stunde, Tag) sowie deren Aktivitätslevel (Anzahl der Requests).

---

## 2. Technologie-Vorschlag

### Datenquelle / Backend-Tracking
**Empfehlung: AWS CloudWatch Logs Insights**
Anstatt jede API-Anfrage in eine teure und latenzsteigernde DynamoDB-Tracking-Tabelle zu schreiben, nutzen wir das bestehende AWS-Ökosystem.
- Der AWS Lambda Handler generiert extrem schnell JSON-strukturierte Log-Einträge.
- *CloudWatch Logs Insights* bietet eine mächtige SQL-ähnliche Abfragesprache, um diese Logs "on-the-fly" zu aggregieren (z.B. `stats count(*) by applicationId, bin(1h)`).
- **Vorteile:** Keine Latenz für den Endnutzer, keine zusätzlichen DynamoDB-Kosten für Writes, beliebig skalierbar.

### Frontend / SPA
**Empfehlung: Integrierter Flutter-Screen in der bestehenden App**
Die "Single Page" wird als neuer Screen (`monitoring_screen.dart`) in die bestehende Flutter-App integriert und für Super-Admins im Home-Screen-Grid freigeschaltet.
- **Vorteile:** Die App ist durch die Firebase/PWA-Infrastruktur bereits im Web verfügbar. Die Authentifizierung (Token-Handling) existiert bereits und muss nicht für ein komplett neues Vue/React-Projekt neu geschrieben werden.
- **Visualisierung:** Nutzung des beliebten und leistungsstarken Flutter-Packages `fl_chart` für interaktive Graphen.

---

## 3. Erforderliche Änderungen im Backend (AWS & Terraform)

### Schritt 1: Strukturiertes Logging integrieren (`aws_backend/lambda/lambda_handler.py`)
Der Haupt-Einstiegspunkt für alle API-Calls muss angepasst werden. Nach erfolgreicher Autorisierung (durch den bestehenden API Gateway Authorizer) hat der Handler Zugriff auf `applicationId` und `memberId`.
- Hinzufügen einer zentralen Log-Anweisung am Start jedes Requests:
  ```python
  import json
  logger.info(json.dumps({
      "log_type": "api_access",
      "applicationId": event["requestContext"]["authorizer"].get("applicationId"),
      "memberId": event["requestContext"]["authorizer"].get("memberId"),
      "path": event.get("path"),
      "httpMethod": event.get("httpMethod")
  }))
  ```

### Schritt 2: Neuer Monitoring-Endpoint (`aws_backend/lambda/api_monitoring.py`)
Ein neues Lambda, das die CloudWatch Logs abfragt.
- **Route:** `GET /monitoring/stats?timeframe=hour`
- **Logik:** Nutzt die `boto3` Bibliothek, um `start_query` und `get_query_results` auf die Log-Gruppe des Haupt-Handlers auszuführen.
- **Queries:**
  - *Requests per Club:* Zählt die Logs gruppiert nach `applicationId` und Zeitintervall.
  - *Active Members:* Zählt die Logs gruppiert nach `memberId` für den aktuellen Tag/Stunde.

### Schritt 3: Terraform Updates (`aws_backend/`)
- Erstellen von `api_monitoring.tf` zur Bereitstellung des neuen Endpoints.
- Die IAM-Rolle des Monitoring-Lambdas muss Rechte für CloudWatch Logs Insights erhalten (`logs:StartQuery`, `logs:GetQueryResults`, `logs:FilterLogEvents`).

---

## 4. Erforderliche Änderungen in der App (Flutter Frontend)

### Schritt 1: Abhängigkeiten hinzufügen (`pubspec.yaml`)
- `fl_chart: ^0.65.0` (oder aktuelle Version) für Liniendiagramme und Bar-Charts hinzufügen.

### Schritt 2: API Client erweitern (`lib/api/monitoring_api.dart`)
- Eine neue API-Klasse erstellen, die den `GET /monitoring/stats`-Endpoint anspricht und die aggregierten JSON-Daten in Dart-Objekte umwandelt.

### Schritt 3: Monitoring UI erstellen (`lib/screens/monitoring_screen.dart`)
Ein neues Dashboard-Layout implementieren:
- **Header-Bereich:** Dropdown / SegmentedButton zur Auswahl des Zeitraums (Min, Stunde, Tag, etc.).
- **Chart-Bereich (API Aufrufe):** Ein Liniendiagramm (`LineChart`), das die X-Achse (Zeit) und Y-Achse (Anzahl Aufrufe) darstellt, idealerweise mit unterschiedlichen Linien pro Verein.
- **Listen-Bereich (Aktive Mitglieder):** Eine Liste (oder Tabelle), sortiert nach Aktivitätslevel (Anzahl der API-Aufrufe), mit Hervorhebung von Mitgliedern, die in der letzten Minute/Stunde aktiv waren.

### Schritt 4: Navigation einbinden (`lib/screens/home_screen.dart`)
- Das Grid-Menü um eine Kachel erweitern: `📈 Monitoring` (nur sichtbar, wenn `member.isSuperAdmin == true`).

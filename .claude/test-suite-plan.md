# Test-Suite Implementierungsplan

Jeder Abschnitt ist ein eigener Commit. Status: ⬜ offen / ✅ fertig

---

## ✅ Vorbereitung
- `aws_backend/lambda/tests/` Verzeichnis erstellen

---

## ✅ Commit 1: Python Backend Tests

**Dateien anlegen:**
- `aws_backend/lambda/tests/__init__.py` (leer)
- `aws_backend/lambda/tests/test_api_members.py`
- `aws_backend/lambda/tests/test_api_docs.py`
- `aws_backend/lambda/tests/test_lambda_handler_fines.py`

**Strategie:**
- `sys.path.insert(0, ...)` auf das lambda-Verzeichnis
- `lambda_handler.py` importiert `push_notifications` und `error_handler` → vor dem Import via `sys.modules` mocken
- Boto3 wird importiert aber macht keine Netzwerkaufrufe beim Erzeugen von Resource/Client
- In `setUp()` die Modul-Level-Variablen direkt ersetzen:
  - `api_members.members_table = MagicMock()`
  - `api_docs.s3 = MagicMock()`, `api_docs.s3_bucket_name = 'test-bucket'`, `api_docs.DOCS_PASSWORD = 'pw'`
  - `lambda_handler.members_table = MagicMock()`, `lambda_handler.fines_table = MagicMock()`
- Für `botocore.exceptions.ClientError` in `add_doc`-Test: `mock_s3.exceptions.ClientError = ClientError` setzen

**test_api_members.py – Tests:**
- `list_members` als Admin → 200 mit Items
- `list_members` als Nicht-Admin → 403
- `get_member` reduzierte Felder (kein `street`, kein `phone1`)
- `get_member` nicht gefunden → 404
- `add_member` speichert `isActive=True` per Default
- `add_member` speichert `isActive=False` wenn mitgegeben
- `delete_member` ruft `delete_item` mit korrektem Key auf
- `delete_member` als Nicht-Admin → 403

**test_api_docs.py – Tests:**
- `_check_password` korrektes PW → True
- `_check_password` falsches PW → False
- `_check_password` kein PW → False
- `get_docs` ruft `list_objects_v2` mit `Prefix='docs/'` auf
- `get_docs` falsches PW → 401, kein S3-Aufruf
- `get_docs` gibt Namen ohne Prefix zurück (`'Protokolle/file.pdf'`, nicht `'docs/Protokolle/file.pdf'`)
- `get_doc` verwendet korrekten S3-Key `'docs/file.pdf'`
- `get_doc` mit Kategorie → S3-Key `'docs/Protokolle/file.pdf'`
- `add_doc` speichert in S3 wenn Datei noch nicht existiert
- `add_doc` → 409 wenn Datei bereits existiert
- `delete_doc` ruft `delete_object` mit korrektem Key auf

**test_lambda_handler_fines.py – Tests:**
- `get_fines` ohne `memberId` → 400
- `get_fines` gibt `name` und `fines` zurück
- `get_fines` serialisiert `decimal.Decimal` korrekt als String
- `add_fine` generiert UUID als `fineId`
- `add_fine` speichert alle Felder
- `delete_fine` ruft `delete_item` mit `{memberId, fineId}` auf

**Ausführen:**
```bash
cd aws_backend/lambda && python -m pytest tests/ -v
```

---

## ✅ Commit 2: Reine Dart-Logik extrahieren + Unit-Tests

**Neue Dateien:**
- `lib/logic/ssp_logic.dart` – öffentliche Typen aus `schere_stein_papier_screen.dart`
- `lib/logic/documents_logic.dart` – `groupDocuments()` und `fullDocumentName()` aus `documents_screen.dart`

**Geänderte Dateien:**
- `lib/screens/schere_stein_papier_screen.dart` – private `_Zug`, `_zugFromString`, `_zugToString`, `_ergebnis`, `_Spielstand` → importieren aus `ssp_logic.dart` (ohne `_`-Prefix)
- `lib/screens/documents_screen.dart` – `_group()` → `groupDocuments()`, `_fullName()` → `fullDocumentName()`

**Test-Dateien:**
- `test/unit/ssp_logic_test.dart`
- `test/unit/documents_logic_test.dart`
- `test/unit/headers_test.dart`
- `test/unit/config_loader_test.dart`

**ssp_logic_test.dart – Tests:**
- `ergebnis(stein, schere)` → 1 (alle 9 Kombinationen)
- `zugFromString('stein')` → `Zug.stein`
- `zugFromString('ungültig')` → null
- `zugFromString(null)` → null
- `zugToString` / `zugFromString` Roundtrip für alle 3 Züge
- `Spielstand.fromJson({'s':3,'n':1,'u':2})` → korrekte Felder
- `Spielstand().toJson()` → `{'s':0,'n':0,'u':0}`
- `Spielstand.fromJson(s.toJson())` Roundtrip

**documents_logic_test.dart – Tests:**
- Leere Liste → leere Map
- Datei ohne `/` → Kategorie `''`, Name unverändert
- `'Protokolle/file.pdf'` → Kategorie `'Protokolle'`, Name `'file.pdf'`
- Benannte Kategorien alphabetisch sortiert
- `''` kommt nach benannten Kategorien
- Dateien innerhalb einer Kategorie alphabetisch sortiert
- `fullDocumentName('', 'file.pdf')` → `'file.pdf'`
- `fullDocumentName('Protokolle', 'file.pdf')` → `'Protokolle/file.pdf'`

**headers_test.dart – Tests:**
- Enthält alle Pflichtfelder (`Content-Type`, `applicationId`, `memberId`, `password`)
- `password` ist `''` wenn `sessionPassword == null`
- `applicationId` und `memberId` werden korrekt übernommen

**config_loader_test.dart – Tests:**
- `AppConfig.fromJson` mit allen Feldern
- `AppConfig.fromJson` ohne `password` → `sessionPassword == null`
- `AppConfig.toJson` Roundtrip
- `AppConfig.toJson` enthält kein `password`-Key wenn `sessionPassword == null`
- `Member.updateMember(null)` → alle Felder leer/false, keine Exception
- `Member.encodeMember()` gibt valides JSON zurück mit allen Feldern

**Ausführen:**
```bash
flutter test test/unit/
```

---

## ✅ Commit 3: HTTP-Client in API-Klassen injizierbar machen

**Geänderte Dateien** (alle 5 API-Klassen):
- `lib/api/members_api.dart`
- `lib/api/fines_api.dart`
- `lib/api/documents_api.dart`
- `lib/api/gallery_api.dart`
- `lib/api/customers_api.dart`

**Änderung pro Datei:**
```dart
class XxxApi {
  final AppConfig config;
  final http.Client _client;

  XxxApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  // Alle http.get / http.post / http.delete ersetzen durch _client.get / ...
}
```

**Ausführen:**
```bash
flutter analyze lib/api/
```

---

## ✅ Commit 4: API-Layer Dart-Tests

**Neue Test-Dateien:**
- `test/api/members_api_test.dart`
- `test/api/fines_api_test.dart`
- `test/api/documents_api_test.dart`
- `test/api/gallery_api_test.dart`

**Strategie:** `MockClient` aus `package:http/testing.dart`, eingebaut in `http`-Package.

```dart
final client = MockClient((request) async {
  expect(request.url.path, '/members');
  expect(request.headers['applicationId'], 'test-app');
  return Response(jsonEncode([...]), 200);
});
final api = MembersApi(config, client: client);
```

**members_api_test.dart:**
- `fetchMembers` 200 → Liste zurück
- `fetchMembers` 403 → Exception mit statusCode
- `createMember` → POST auf `/members`, Body enthält `applicationId`-Prefix in memberId
- `saveMember` → POST mit korrektem JSON-Body
- `deleteMember` → DELETE auf `/members/{id}`
- Auth-Header: `applicationId`, `memberId` vorhanden

**fines_api_test.dart:**
- `fetchFines` 200 → Map mit `name` und `fines`
- `fetchFines` 500 → Exception
- `addFine` → Body enthält `fineId`, `memberId`, `reason`, `amount`
- `deleteFine` → DELETE auf `/fines/{id}?memberId={id}`

**documents_api_test.dart:**
- `fetchDocuments` 200 → Liste
- `fetchDocuments` 401 → Exception mit "Falsches Passwort"
- `uploadDocument` → Body ist JSON mit `name` und base64-`file`
- `_docsUrl('file.pdf')` → `/docs/file.pdf`
- `_docsUrl('Protokolle/file.pdf')` → `/docs/Protokolle/file.pdf`
- `_docsUrl('Ä B/üml.pdf')` → korrekte Prozent-Enkodierung

**gallery_api_test.dart:**
- `fetchThumbnails` 200 → Liste
- `uploadPhoto` → macht genau 2 POST-Requests
- `uploadPhoto` erstes POST schlägt fehl → Exception, zweites POST nicht mehr
- `deletePhoto` → DELETE auf korrekter URL

**Ausführen:**
```bash
flutter test test/api/
```

---

## ✅ Commit 5: Widget-Tests

**Neue Screen-Parameter** (minimale Änderung für Testbarkeit):
- `StrafenScreen`: `final FinesApi? finesApi;` + `initState: api = widget.finesApi ?? FinesApi(widget.config)`
- `DocumentScreen`: `final DocumentApi? documentApi;` + analog

**Neue Test-Dateien:**
- `test/widget/strafen_screen_test.dart`
- `test/widget/documents_screen_test.dart`

**Wrapper-Helper** `test/widget/test_helpers.dart`:
```dart
Widget wrapScreen(Widget screen, AppConfig config) => MaterialApp(
  home: ChangeNotifierProvider<Member>.value(value: config.member, child: screen),
);
```

**strafen_screen_test.dart:**
- Rendert Lade-Spinner während API-Call läuft
- Rendert "Keine Strafen vorhanden" bei leerer Liste
- Rendert Strafen-Items mit Grund und Betrag
- Gesamtbetrag korrekt berechnet und angezeigt
- Fehler beim Laden → SnackBar mit Fehlertext

**documents_screen_test.dart:**
- Kategorien als ExpansionTile mit korrektem Titel
- `''`-Kategorie erscheint als "Allgemein"
- PDF-Datei hat `Icons.picture_as_pdf`
- Nicht-Admin sieht keinen Upload-Button
- Admin sieht Upload-Button

**Ausführen:**
```bash
flutter test test/widget/
```

---

## Alle Tests auf einmal ausführen

```bash
# Dart
flutter test

# Python
cd aws_backend/lambda && python -m pytest tests/ -v
```

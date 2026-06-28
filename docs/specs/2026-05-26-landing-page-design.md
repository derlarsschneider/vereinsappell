# Design: Landing Page mit Registrierung

**Datum:** 2026-05-26
**Status:** Approved

## Zusammenfassung

Die bestehende `web/index.html` (Flutter-Einstiegspunkt) wird um eine Landing Page erweitert. Sind beim Aufruf alle drei App-Parameter in der URL vorhanden, startet die Flutter App wie bisher. Fehlen sie, rendert dieselbe `index.html` eine statische Landing Page mit Marketing-Inhalt und Registrierungsflows. Damit sieht Googles AdSense-Crawler echten HTML-Inhalt und der Verstoß wegen "Screens without Publisher-Content" wird behoben.

---

## Routing

| URL | Inhalt |
|---|---|
| `/` mit `apiBaseUrl` + `applicationId` + `memberId` | Flutter App startet (wie bisher) |
| `/` ohne vollständige Parameter | Landing Page wird gerendert |

Die Prüfung erfolgt per JS in `index.html` beim Laden:

```js
const p = new URLSearchParams(window.location.search);
if (p.has('apiBaseUrl') && p.has('applicationId') && p.has('memberId')) {
  // flutter_bootstrap.js laden
} else {
  // Landing Page HTML in <body> rendern
}
```

Keine Änderungen an `firebase.json` nötig.

---

## Landing Page

### Struktur

1. **Navigationsleiste** — Logo "VEREINS APPELL", grüner Hintergrund (`#1a3a1a`)
2. **Hero** — Headline "Was möchtest du tun?", kurzer Untertitel, grüner Gradient-Hintergrund
3. **Drei Aktionskarten:**
   - 🏛️ **Meinen Verein anmelden** → öffnet Registrierungsformular (inline, kein Page-Load)
   - 📷 **QR-Code scannen** → öffnet Kamera inline, startet App bei Erfolg
   - ✉️ **Beitrittsanfrage stellen** → öffnet Beitrittsformular (inline)
4. **Hinweis** — "Bereits registriert? Öffne deinen Einladungslink."
5. **Feature-Übersicht** — Mitgliederverwaltung, Terminkalender, Umlagen & Strafen, Dokumente, Abstimmungen, Getränkebestellungen
6. **Footer** — © Vereins Appell

### Design

- Farben: Dunkelgrün `#1a3a1a`, Grün `#2d6a2d`, Hintergrund `#f0f4f0`, Weiß für Cards
- Mobile-first, max-width 560px, zentriert
- Kein externes CSS-Framework — reines CSS inline in `index.html`

---

## Flow 1: Verein anmelden

Formularfelder:
- Vereinsname (Pflicht)
- Ansprechpartner / Name (Pflicht)
- E-Mail-Adresse (Pflicht)
- Telefon (optional)
- Freitext / Nachricht (optional)

Beim Absenden: `POST /join/club` → Bestätigungstext inline ("Wir melden uns in Kürze!"), kein Page-Reload.

---

## Flow 2: QR-Code scannen

- JS-Bibliothek `jsQR` per CDN (kein npm, kein Build-Step)
- Kamera-Stream öffnet sich inline auf der Landing Page
- Erkannter QR-Code wird mit `parseInviteLink()` geprüft (gleiche Logik wie Dart)
- Bei validen Parametern: Redirect auf `/?apiBaseUrl=...&applicationId=...&memberId=...` → Flutter App startet
- Bei ungültigem Code: Inline-Fehlermeldung

---

## Flow 3: Beitrittsanfrage

Formularfelder:
- Name (Pflicht)
- Vereinsname (Pflicht)
- E-Mail-Adresse (Pflicht)
- Nachricht (optional)

Beim Absenden: `POST /join/member` → Bestätigungstext inline ("Deine Anfrage wurde weitergeleitet."), kein Page-Reload.

---

## Backend: Neue API-Endpunkte

### `POST /join/club`

Payload:
```json
{
  "clubName": "Schützenverein Beispiel",
  "contact": "Max Mustermann",
  "email": "max@example.com",
  "phone": "+49 123 456789",
  "message": "Wir haben 42 Mitglieder..."
}
```

Aktion: AWS SES sendet E-Mail an `info@vereinsappell.de` mit den Formulardaten. Antwort: `200 OK`.

### `POST /join/member`

Payload:
```json
{
  "name": "Max Mustermann",
  "clubName": "Schützenverein Beispiel",
  "email": "max@example.com",
  "message": "Ich möchte gerne beitreten..."
}
```

Aktion: AWS SES sendet E-Mail an `info@vereinsappell.de`. Antwort: `200 OK`.

Beide Endpunkte werden als neue Handler-Funktionen in `aws_backend/` angelegt, analog zu bestehenden Endpunkten.

---

## E-Mail-Setup (AWS SES)

- Domain `vereinsappell.de` in SES verifizieren (DNS-Einträge: DKIM, SPF, DMARC)
- Absenderadresse: `info@vereinsappell.de`
- Empfängeradresse initial: `info@vereinsappell.de` mit Weiterleitung konfigurierbar
- Ziel: kein direkter Einsatz der privaten E-Mail-Adresse im Code

---

## Nicht im Scope

- Automatisches Anlegen von Vereinen (bleibt manuell)
- Authentifizierung der Formulare (kein CAPTCHA in V1 — kann später ergänzt werden)
- Mehrsprachigkeit der Landing Page

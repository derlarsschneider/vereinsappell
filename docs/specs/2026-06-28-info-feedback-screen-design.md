# Design: Info & Feedback Screen

**Date:** 2026-06-28  
**Status:** Approved

---

## Overview

A new screen reachable from the home menu for all active members. It contains three tabs: News (app-wide announcements), Feedback (member-to-admin communication), and Legal (Datenschutzerklärung + Impressum). The screen is always visible — no `active_screens` gate — because legal content must always be accessible.

---

## Tab 1 — News (Neuigkeiten)

**Who reads:** All active members across all clubs.  
**Who writes:** SuperAdmin only.

News items appear in reverse-chronological order. The SuperAdmin sees a "+" button at the top to open the create form. Each item shows a delete button for the SuperAdmin only.

### News item fields

| Field | Type | Required |
|---|---|---|
| `newsId` | String (UUID) | Yes |
| `title` | String | Yes |
| `body` | String | Yes |
| `date` | ISO timestamp | Yes |
| `createdBy` | memberId | Yes |
| `expiresAt` | ISO timestamp | No |
| `question` | String | No |
| `questionOptions` | List\<String\> | No |

### Expiry

The backend filters out items where `expiresAt` is in the past on every `GET /news` call. The SuperAdmin sets expiry via chips: **1 Woche**, **1 Monat**, **📅 Datum wählen**, **∞ Unbegrenzt**. Selecting "Datum wählen" opens a date picker.

### News with question

A news item can carry an optional question. Two modes:

- **Freitext** — member types a free-text answer
- **Auswahloptionen** — SuperAdmin defines 2+ answer options; member taps one to select, then submits

After submitting, the news card shows a green "✅ Deine Antwort gesendet" confirmation. A member can answer each news question only once (backend enforces via `memberId` + `newsId`). The answer is stored as a `feedback_table` entry with `newsId` set.

---

## Tab 2 — Feedback

### Member view

- Text field + "📤 Feedback senden" button at the top
- Below: list of the member's own past feedback entries, newest first
- Each entry shows the member's message and, if present, the SuperAdmin's reply (green background)
- Entries without a reply show no status indicator
- Answers to news questions appear in the same list, marked with a purple tint and the original question text

### SuperAdmin view

- Shows all feedback from all clubs
- Counter chips: "● N offen" (red) and "● N beantwortet" (green)
- **Open** entries: red border, red tint background. Shows a reply text field + "↩️ Antworten" button
- **Answered** entries: green border, green tint. Shows the sent reply
- Feedback originating from a news question shows the question text above the answer

### Notifications when feedback is received

When `POST /feedback` is called:
1. Push notification to the SuperAdmin's device token (via Firebase, reusing existing `push_notifications.py`)
2. Email via AWS SES to a configured admin address (Lambda env var `ADMIN_EMAIL`)

SES must be set up in the AWS account and the sender domain verified before this works.

---

## Tab 3 — Rechtliches

Two expandable sections: **🔒 Datenschutzerklärung** and **📄 Impressum**. Text is loaded from the backend (`GET /legal`) and rendered as plain scrollable text.

SuperAdmin sees an "✏️ Texte bearbeiten" button that opens an edit dialog for both texts. Changes are saved via `PUT /legal` without any app deployment.

Both texts apply globally across all clubs.

---

## Data Model

### New DynamoDB tables

**`news_table`**  
Partition key: `newsId` (String)

**`feedback_table`**  
Partition key: `applicationId` (String), sort key: `feedbackId` (String)  
Additional fields: `memberId`, `memberName`, `message`, `date`, `newsId` (optional), `newsTitle` (optional), `newsQuestion` (optional — denormalized from news item to avoid a join when displaying), `reply` (optional), `repliedAt` (optional)

**`legal_texts_table`**  
Partition key: `id` (String)  
Two fixed items: `id = "datenschutz"` and `id = "impressum"`, each with a `text` field.

---

## Backend: New Lambda Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/news` | All | List non-expired news |
| POST | `/news` | SuperAdmin | Create news item |
| DELETE | `/news/{newsId}` | SuperAdmin | Delete news item |
| POST | `/feedback` | Any member | Submit feedback or news-question answer → push + email |
| GET | `/feedback` | SuperAdmin: all; Member: own | List feedback |
| POST | `/feedback/{feedbackId}/reply` | SuperAdmin | Add reply to a feedback entry |
| GET | `/legal` | All | Get Datenschutz + Impressum texts |
| PUT | `/legal` | SuperAdmin | Update Datenschutz + Impressum texts |

New Python files in `aws_backend/lambda/`:
- `api_news.py`
- `api_feedback.py`
- `api_legal.py`

Routes added to `lambda_handler.py` dispatch table.

---

## Flutter

### New files

- `lib/api/news_api.dart`
- `lib/api/feedback_api.dart`
- `lib/api/legal_api.dart`
- `lib/screens/info_feedback_screen.dart`

### Changed files

- `lib/screens/home_screen.dart` — add "ℹ️ Info & Feedback" tile to the grid menu, visible to all active members (no `_isScreenActive` check)

### Screen structure

`InfoFeedbackScreen` extends `DefaultScreen`. Uses `DefaultTabController` with 3 tabs. Each tab is a separate private widget class within the same file.

---

## AWS Infrastructure

- 3 new DynamoDB tables (provisioned via existing IaC or manually)
- AWS SES: verify sender domain/address, set `ADMIN_EMAIL` Lambda env var
- No new IAM roles needed if existing Lambda role already has DynamoDB full access; add `ses:SendEmail` permission

---

## App Store Legal Requirements

- **Privacy Policy (Datenschutzerklärung):** Required by both Apple App Store and Google Play Store. Stored in backend, editable without app update.
- **Impressum:** Required by German law (Telemediengesetz §5) for publicly accessible apps. Same storage approach.
- Both are surfaced in Tab 3 of this screen. The App Store submission URL should point to a publicly accessible version — consider also hosting the texts at a stable public URL (e.g., on your website).

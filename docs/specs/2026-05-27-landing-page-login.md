# Landing Page Login

## Problem

iOS clears localStorage frequently, causing members to land on the landing page instead of the app. They need a fast way back in without the admin having to reshare the full invite link.

## Solution

Add a username + password login section to the landing page. The credentials are the existing UUIDs — no new backend logic required.

- **Username** = `applicationId` (club UUID)
- **Password** = `memberId` (member UUID)
- **apiBaseUrl** = hardcoded prod endpoint: `https://v49kyt4758.execute-api.eu-central-1.amazonaws.com`

## Landing Page Changes

### Login section

Below the existing three action cards and the "Bereits registriert?" hint, add a collapsible login section. The fields are hidden by default; clicking the header toggles them open.

```
▶ Bereits registriert?          ← collapsed (default)

▼ Bereits registriert?          ← expanded
  [ Benutzername              ] [ Passwort ] [→]
```

- Header row is always visible and acts as the toggle (chevron rotates on expand)
- Fields and submit button are hidden by default, revealed on click
- When pre-filled from URL params the section auto-expands and shows a note: "Vom Einladungslink vorausgefüllt"
- Single row on wide screens, stacked on narrow screens
- "Benutzername" = text input for `applicationId`
- "Passwort" = password input (masked) for `memberId`
- Submit button navigates to:
  `/?apiBaseUrl=<prod_url>&applicationId=<input>&memberId=<input>`
- Validation: both fields must be non-empty (basic check)
- Error state: inline message below the form

### Pre-fill from URL params

When the page loads with `?applicationId=X&memberId=Y` in the URL (but without `apiBaseUrl`), the form fields are pre-filled and a subtle note appears: "Vom Einladungslink vorausgefüllt". One click on "Einloggen" gets the user in.

This enables a short re-invite link: `https://vereinsappell.web.app/?applicationId=X&memberId=Y`

### Existing full link stays unchanged

`?apiBaseUrl=...&applicationId=...&memberId=...` still loads Flutter directly (no change to existing behavior or QR codes).

### apiBaseUrl passthrough for dev

If the URL already contains `apiBaseUrl`, the login submit uses that value instead of the hardcoded prod URL. This keeps the dev workflow functional.

## App Changes

### Credentials view in settings

Add a "Mein Zugang" section in the app (profile/settings screen) that displays:

- **Benutzername**: `<applicationId>` (copyable)
- **Passwort**: `<memberId>` (copyable, masked by default with reveal toggle)
- Short re-invite link (copyable): `https://vereinsappell.web.app/?applicationId=X&memberId=Y`

This allows members to note down their credentials proactively.

## Files to Change

| File | Change |
|------|--------|
| `web/index.html` | Add login section + pre-fill logic |
| `web/index-a.html` | Same |
| `web/index-c.html` | Same |
| `lib/screens/home_screen.dart` or settings screen | Add credentials view |

## Out of Scope

- No backend changes
- No password hashing or session tokens
- No "Passwort vergessen" flow
- No email-based lookup

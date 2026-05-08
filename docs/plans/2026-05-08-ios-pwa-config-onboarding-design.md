# PWA Config Onboarding — Design

## Problem

Mobile browsers and installed PWAs have separate `localStorage` contexts — this is standard
PWA behaviour on both iOS (Safari) and Android (Chrome). When a user opens an invitation URL
(containing `apiBaseUrl`, `applicationId`, `memberId`, `password` as query params) in the
browser, the app saves the config — but that storage is invisible to the PWA once added to
the home screen. The PWA launches into `ConfigMissingScreen` with empty fields.

## Solution

Two independent improvements to `ConfigMissingScreen` (web branch):

### 1. Invite-link paste field

A new text field labelled "Einladungslink einfügen" is added at the top of the web form.
Whenever its value changes, `_parseInviteLink` attempts to parse the text as a URI and
auto-fills `_apiBaseUrlController`, `_applicationIdController`, `_memberIdController`, and
`_passwordController` from the matching query parameters. The four detail fields remain
visible below so the user can see and verify what was parsed.

`_parseInviteLink` is a no-op if the text is not a valid URI or lacks the required params —
no error shown, user just fills the fields manually.

### 2. Camera QR scan on web

`MobileScanner` (widget, live camera) supports web via the WebRTC camera API. Only
`analyzeImage` is unsupported. Changes:

- The "Kamera scannen" button is shown in the web form (was guarded by `!kIsWeb`).
- The existing `scanning` state and `MobileScanner` widget already work cross-platform —
  no logic changes needed there.
- The "QR-Code aus Bild laden" button is hidden on web (calls `analyzeImage`, unsupported).

## Scope

All changes are confined to `lib/screens/config_missing_screen.dart`. No new packages.

## Error handling

- Invalid invite link: silently ignored, fields stay as-is.
- Camera permission denied / not available on web: `MobileScanner` shows its built-in error
  state; user can fall back to paste-link or manual entry.

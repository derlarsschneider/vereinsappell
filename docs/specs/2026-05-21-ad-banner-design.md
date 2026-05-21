# Ad Banner System — Design Spec

**Date:** 2026-05-21
**Status:** Approved

## Overview

Add a configurable advertisement banner to the Home Screen, displayed in a persistent bottom bar next to the existing donation button. Admins configure the ad type in the VereinsScreen; the configuration is stored in DynamoDB per customer. Two ad modes are supported: a sponsor banner (image + link, configured by the admin) and Google AdSense (automatic ad network). If no ad is configured, the bottom bar still renders with just the donation button.

## Data Model

New fields on the `customers` DynamoDB item:

| Field | Type | Values |
|---|---|---|
| `ad_type` | string | `"none"` \| `"banner"` \| `"admob"` |
| `ad_banner_image_url` | string | URL to the sponsor image |
| `ad_banner_link_url` | string | URL opened on tap |
| `ad_admob_publisher_id` | string | e.g. `"ca-pub-1234567890123456"` |
| `ad_admob_ad_unit_id` | string | AdSense ad unit ID |

All fields are optional. Missing `ad_type` is treated as `"none"`.

## VereinsScreen Changes

A new **"Werbung"** section is added below the active screens list and above the save button. It contains:

- A `SegmentedButton` with three segments: **Keine** / **Sponsor-Banner** / **Google Ads**
- When **Sponsor-Banner** is selected: two `TextField` inputs appear — Bild-URL and Ziel-URL
- When **Google Ads** is selected: two `TextField` inputs appear — Publisher-ID and Ad-Unit-ID
- When **Keine** is selected: no extra inputs

All five fields (`ad_type`, `ad_banner_image_url`, `ad_banner_link_url`, `ad_admob_publisher_id`, `ad_admob_ad_unit_id`) are included in the existing `_save()` payload sent via `CustomersApi.updateCustomer()`.

`_applyClub()` is extended to populate the new state variables when loading existing club data.

## HomeScreen Changes

### Layout

The current `floatingActionButton` (donation button) is replaced by a `bottomNavigationBar` in the Scaffold containing a fixed-height `Row`:

```
[ AdBannerWidget (flex: 1) ][ donate button ]
```

The donate button keeps its existing tap behaviour (`_openDonation` → PayPal URL). It is only rendered when `_paypalAccount.isNotEmpty`, same as before. If neither an ad nor a donation button is needed, the bottom bar is omitted entirely (`bottomNavigationBar: null`).

### State

`_updateApplication()` reads and stores:
- `_adType` (String, default `"none"`)
- `_adBannerImageUrl` (String)
- `_adBannerLinkUrl` (String)
- `_adAdmobPublisherId` (String)
- `_adAdmobAdUnitId` (String)

### AdBannerWidget

A new stateless widget at `lib/widgets/ad_banner_widget.dart` receives the five ad config values and renders:

- `ad_type == "none"` → `SizedBox.shrink()`
- `ad_type == "banner"` → `GestureDetector` wrapping `Image.network(adBannerImageUrl)`, tap opens `adBannerLinkUrl` via `url_launcher`
- `ad_type == "admob"` → `HtmlElementView` backed by a registered platform view factory (Flutter Web only); falls back to `SizedBox.shrink()` on non-web platforms

## Google AdSense Web Integration

AdSense requires a real HTML element in the DOM — Flutter's canvas-based renderer cannot render it directly.

**Approach:**

1. `AdBannerWidget` registers a view factory via `ui_web.platformViewRegistry.registerViewFactory()` (only on `kIsWeb`). The factory creates an HTML `div` containing an `<ins class="adsbygoogle">` element with the correct `data-ad-client` and `data-ad-slot` attributes.
2. The AdSense `<script>` tag is injected dynamically into `document.head` via `dart:js_interop` using the publisher ID from config (so it works with the DynamoDB-stored value without requiring a static `index.html` change).
3. `adsbygoogle.push({})` is called after the element is mounted.
4. The view type key includes the ad unit ID to allow re-registration when config changes.

Because AdSense requires an approved account and a live domain, the widget renders an empty container in debug/local mode (no errors, no placeholder).

## Error Handling

- Sponsor banner: if `Image.network` fails to load, `errorBuilder` renders `SizedBox.shrink()` — no visible error to the user.
- AdSense: JS errors from the AdSense script are contained within the platform view iframe/element and do not surface in Flutter.

## Scope Boundaries

- No backend (Lambda/API) changes required — the new fields are stored as-is in DynamoDB via the existing `updateCustomer` endpoint.
- No changes to the Android or iOS build targets — AdSense is web-only; the sponsor banner uses `Image.network` which works on all platforms.
- AdSense account registration and domain verification are out of scope — the UI is built ready to receive a valid publisher ID.

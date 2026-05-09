# Fotogalerie-Umbau

**Date:** 2026-05-09  
**Priority areas:** Loading performance (D) → Grid layout (B) → Photo viewer (A)

## Problem

The current gallery has three pain points:

1. **Loading:** All thumbnails are fetched as base64 in a single blocking API call. As the gallery grows this becomes slow. A global spinner hides the entire grid during any load operation.
2. **Grid:** Fixed 3-column layout regardless of screen size. Thumbnails are square-cropped at 200px client-side.
3. **Viewer:** Full-size photo opens in a plain `Dialog` with no swipe navigation, no zoom, and no close button.

Additionally, thumbnail generation currently happens client-side in Flutter, meaning thumbnail size/quality can only be changed via an app update.

## Design

### Backend changes (AWS Lambda + S3)

**Upload (`POST /photos`):**
- Accept only the original image (base64 JSON, same format as today but without the `thumbnails/` upload)
- Generate a square-cropped thumbnail server-side using Pillow (400px wide, center-crop to 1:1)
- Store both `img/<filename>` and `thumbnails/<filename>` atomically in S3
- Add Pillow to `requirements.txt`

**List thumbnails (`GET /photos/thumbnails`):**
- Return presigned S3 URLs instead of base64 image data
- Response shape: `[{"name": "thumbnails/foo.jpg", "url": "https://..."}]`
- URL TTL: 1 hour

**Fetch full photo (`GET /photos/img/{name}`):**
- Return a presigned S3 URL as JSON: `{"url": "https://..."}`
- Flutter follows the URL with `Image.network()`

**Delete (`DELETE /photos/{name}`):**
- Client sends the base filename only (e.g. `foo.jpg`, not `thumbnails/foo.jpg`)
- Lambda deletes both `img/foo.jpg` and `thumbnails/foo.jpg` from S3 in one call

### Flutter: `gallery_api.dart`

- `fetchThumbnails()` → `List<Map<String, String>>` with `name` and `url` keys
- `fetchPhoto(name)` → `String` (presigned URL)
- `uploadPhoto()` → sends only the original JPEG (remove thumbnail generation and second POST call)
- Remove `image` package dependency if no longer needed elsewhere

### Flutter: `galerie_screen.dart`

**Grid:**
- Replace `SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3)` with `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130)` — automatically 3 columns on phone, more on wider screens
- Replace `Image.memory(base64Decode(thumbnail))` with `Image.network(url, fit: BoxFit.cover)`
- Show shimmer skeleton tiles while the thumbnail list is loading (replace the global `CircularProgressIndicator`)

**Skeleton loading:**
- Pre-render a fixed number of grey placeholder tiles (e.g. 12) while `isLoading == true`
- Each tile is a `Container` with a shimmer animation (animated gradient)
- Once data arrives, replace with real `Image.network` tiles

**Viewer (Fullscreen Lightbox):**
- On thumbnail tap: open a fullscreen overlay via `showGeneralDialog`
- Use `PageView.builder` to swipe between photos (the full-size presigned URL is loaded on demand per page)
- Wrap each page in `InteractiveViewer` for pinch-to-zoom
- X-button top-right to close
- Photo counter bottom-center (`3 / 12`)
- Swipe-down gesture closes the lightbox (via `GestureDetector` + `Navigator.pop`)
- Admin delete button remains accessible in the lightbox (top-left, only for admins)

## Out of scope

- Upload of multiple photos at once
- Camera capture
- Upload progress indicator
- Photo metadata (date, uploader)
- Albums / tags
- Masonry layout

## Open questions

None — all decisions made during brainstorming.

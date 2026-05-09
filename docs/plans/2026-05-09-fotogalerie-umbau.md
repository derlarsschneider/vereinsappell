# Fotogalerie-Umbau Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace base64-blob gallery with presigned S3 URLs, server-side thumbnail generation, a responsive grid with shimmer loading, and a fullscreen swipe/zoom lightbox.

**Architecture:** The Lambda backend gains Pillow to generate thumbnails on upload; thumbnail listing returns presigned URLs (both sizes per photo) instead of inline base64. The Flutter app drops client-side resizing and uses `Image.network` for lazy loading. A new `PhotoLightbox` widget wraps `PageView` + `InteractiveViewer` for fullscreen browsing.

**Tech Stack:** Python/boto3/Pillow (Lambda), Dart/Flutter, `image_picker`, no new Flutter packages.

---

## File Map

| File | Change |
|------|--------|
| `aws_backend/lambda/requirements.txt` | Add `pillow` |
| `aws_backend/lambda/lambda_handler.py` | Rewrite `add_photo`, `get_photos`; add `delete_photo`, dispatch route |
| `aws_backend/lambda/tests/test_photos.py` | New — backend unit tests |
| `lib/api/gallery_api.dart` | Update all three public methods |
| `test/api/gallery_api_test.dart` | Update all tests to match new API contract |
| `lib/widgets/photo_lightbox.dart` | New — fullscreen viewer widget |
| `lib/screens/galerie_screen.dart` | Responsive grid, shimmer, open lightbox |

---

## Task 1: Backend — Pillow + server-side thumbnail generation

**Files:**
- Modify: `aws_backend/lambda/requirements.txt`
- Modify: `aws_backend/lambda/lambda_handler.py`
- Create: `aws_backend/lambda/tests/test_photos.py`

- [ ] **Step 1: Write the failing test**

Create `aws_backend/lambda/tests/test_photos.py`:

```python
import base64
import io
import json
import sys
import unittest
from unittest.mock import MagicMock, patch, call

_boto3_mock = MagicMock()
sys.modules.setdefault('boto3', _boto3_mock)
sys.modules.setdefault('boto3.dynamodb', MagicMock())
sys.modules.setdefault('boto3.dynamodb.conditions', MagicMock())
sys.modules['push_notifications'] = MagicMock()
sys.modules['error_handler'] = MagicMock()
sys.modules['api_members'] = MagicMock()
sys.modules['api_docs'] = MagicMock()

sys.path.insert(0, '.')
import lambda_handler

APP_ID = 'app-123'


def _upload_event(filename, file_bytes):
    body = json.dumps({'name': filename, 'file': base64.b64encode(file_bytes).decode()})
    return {
        'requestContext': {'http': {'method': 'POST', 'path': '/photos'}},
        'headers': {'applicationid': APP_ID},
        'body': body,
    }


class TestAddPhoto(unittest.TestCase):
    def setUp(self):
        self.mock_s3 = MagicMock()
        _boto3_mock.client.return_value = self.mock_s3
        self.mock_s3.exceptions.ClientError = Exception
        # Simulate file not existing yet
        self.mock_s3.head_object.side_effect = Exception('404')

    @patch('lambda_handler._generate_thumbnail', return_value=b'thumb')
    def test_stores_both_img_and_thumbnail(self, _mock_thumb):
        image_bytes = b'fake-image'
        event = _upload_event('photo.jpg', image_bytes)
        response = lambda_handler.add_photo(event, APP_ID)
        self.assertEqual(response['statusCode'], 200)
        put_calls = self.mock_s3.put_object.call_args_list
        keys = [c.kwargs['Key'] for c in put_calls]
        self.assertIn(f'{APP_ID}/photos/img/photo.jpg', keys)
        self.assertIn(f'{APP_ID}/photos/thumbnails/photo.jpg', keys)

    @patch('lambda_handler._generate_thumbnail', return_value=b'thumb')
    def test_converts_non_jpg_extension_to_jpg(self, _mock_thumb):
        image_bytes = b'fake-image'
        event = _upload_event('photo.png', image_bytes)
        response = lambda_handler.add_photo(event, APP_ID)
        self.assertEqual(response['statusCode'], 200)
        put_calls = self.mock_s3.put_object.call_args_list
        keys = [c.kwargs['Key'] for c in put_calls]
        self.assertIn(f'{APP_ID}/photos/img/photo.jpg', keys)

    def test_returns_409_for_duplicate(self):
        self.mock_s3.head_object.side_effect = None  # file exists
        event = _upload_event('photo.jpg', b'img')
        response = lambda_handler.add_photo(event, APP_ID)
        self.assertEqual(response['statusCode'], 409)
        self.mock_s3.put_object.assert_not_called()


if __name__ == '__main__':
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd aws_backend/lambda && python3 -m pytest tests/test_photos.py -v
```

Expected: FAIL — `_generate_thumbnail` not found, old `add_photo` doesn't store two separate keys.

- [ ] **Step 3: Add `pillow` to requirements.txt**

Append to `aws_backend/lambda/requirements.txt`:
```
pillow
```

- [ ] **Step 4: Add `_generate_thumbnail` helper and rewrite `add_photo` in `lambda_handler.py`**

Replace the existing `_generate_thumbnail` placeholder (there is none — add after the `_get_s3_content` function) and rewrite `add_photo`:

```python
def _generate_thumbnail(image_bytes, size=400):
    from PIL import Image
    import io as _io
    img = Image.open(_io.BytesIO(image_bytes)).convert('RGB')
    w, h = img.size
    min_dim = min(w, h)
    left = (w - min_dim) // 2
    top = (h - min_dim) // 2
    img = img.crop((left, top, left + min_dim, top + min_dim))
    img = img.resize((size, size), Image.LANCZOS)
    buf = _io.BytesIO()
    img.save(buf, format='JPEG', quality=70)
    return buf.getvalue()


def add_photo(event, application_id):
    body = base64.b64decode(event['body']) if event.get('isBase64Encoded') else event['body'].encode('utf-8')
    data = json.loads(body)
    raw_name = data['name']
    basename = raw_name.split('/')[-1]
    if not basename.lower().endswith('.jpg'):
        basename = basename.rsplit('.', 1)[0] + '.jpg' if '.' in basename else basename + '.jpg'

    img_key = f'{application_id}/photos/img/{basename}'
    thumb_key = f'{application_id}/photos/thumbnails/{basename}'

    s3 = boto3.client('s3')
    try:
        s3.head_object(Bucket=s3_bucket_name, Key=img_key)
        return {'statusCode': 409, 'body': json.dumps({'error': 'Datei existiert bereits'})}
    except Exception as e:
        if hasattr(e, 'response') and e.response.get('Error', {}).get('Code') != '404':
            raise

    image_bytes = base64.b64decode(data['file'])
    thumbnail_bytes = _generate_thumbnail(image_bytes)

    s3.put_object(Bucket=s3_bucket_name, Key=img_key, Body=image_bytes, ContentType='image/jpeg')
    s3.put_object(Bucket=s3_bucket_name, Key=thumb_key, Body=thumbnail_bytes, ContentType='image/jpeg')

    return {'statusCode': 200, 'body': json.dumps({'message': f'{basename} hochgeladen'})}
```

Also remove the old `_get_s3_content` function (it's no longer used).

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd aws_backend/lambda && python3 -m pytest tests/test_photos.py::TestAddPhoto -v
```

Expected: all 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add aws_backend/lambda/requirements.txt aws_backend/lambda/lambda_handler.py aws_backend/lambda/tests/test_photos.py
git commit -m "feat(backend): server-side thumbnail generation via Pillow"
```

---

## Task 2: Backend — presigned URLs for photo listing and fetch

**Files:**
- Modify: `aws_backend/lambda/lambda_handler.py`
- Modify: `aws_backend/lambda/tests/test_photos.py`

- [ ] **Step 1: Write the failing tests**

Add this class to `aws_backend/lambda/tests/test_photos.py` (after `TestAddPhoto`):

```python
class TestGetPhotos(unittest.TestCase):
    def setUp(self):
        self.mock_s3 = MagicMock()
        _boto3_mock.client.return_value = self.mock_s3

    def _list_event(self, proxy=None):
        event = {
            'requestContext': {'http': {'method': 'GET', 'path': f'/photos/{proxy}' if proxy else '/photos/thumbnails'}},
            'headers': {'applicationid': APP_ID},
            'pathParameters': {'proxy': proxy} if proxy else {'proxy': 'thumbnails'},
        }
        return event

    def test_thumbnail_list_returns_presigned_urls(self):
        self.mock_s3.list_objects_v2.return_value = {
            'Contents': [{'Key': f'{APP_ID}/photos/thumbnails/foo.jpg'}]
        }
        self.mock_s3.generate_presigned_url.side_effect = [
            'https://s3.example.com/thumb/foo.jpg',
            'https://s3.example.com/img/foo.jpg',
        ]
        event = self._list_event()
        response = lambda_handler.get_photos(event, APP_ID)
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(len(body), 1)
        self.assertEqual(body[0]['name'], 'foo.jpg')
        self.assertIn('thumbnail_url', body[0])
        self.assertIn('photo_url', body[0])

    def test_thumbnail_list_returns_empty_list_when_no_photos(self):
        self.mock_s3.list_objects_v2.return_value = {}
        event = self._list_event()
        response = lambda_handler.get_photos(event, APP_ID)
        self.assertEqual(response['statusCode'], 200)
        self.assertEqual(json.loads(response['body']), [])
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd aws_backend/lambda && python3 -m pytest tests/test_photos.py::TestGetPhotos -v
```

Expected: FAIL — old `get_photos` returns `file` (base64) not `thumbnail_url`/`photo_url`.

- [ ] **Step 3: Rewrite `get_photos` in `lambda_handler.py`**

Replace the entire `get_photos` function:

```python
def get_photos(event, application_id):
    import urllib.parse
    s3 = boto3.client('s3')
    proxy = (event.get('pathParameters') or {}).get('proxy')

    if proxy and proxy != 'thumbnails':
        # Single file fetch — return presigned URL
        key = f'{application_id}/photos/{urllib.parse.unquote(proxy)}'
        url = s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': s3_bucket_name, 'Key': key},
            ExpiresIn=3600,
        )
        return {'statusCode': 200, 'body': json.dumps({'url': url})}

    # List thumbnails — return presigned URLs for both sizes
    thumb_prefix = f'{application_id}/photos/thumbnails/'
    img_prefix = f'{application_id}/photos/img/'
    response = s3.list_objects_v2(Bucket=s3_bucket_name, Prefix=thumb_prefix)
    files = []
    for obj in response.get('Contents', []):
        basename = obj['Key'].removeprefix(thumb_prefix)
        thumbnail_url = s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': s3_bucket_name, 'Key': obj['Key']},
            ExpiresIn=3600,
        )
        photo_url = s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': s3_bucket_name, 'Key': f'{img_prefix}{basename}'},
            ExpiresIn=3600,
        )
        files.append({'name': basename, 'thumbnail_url': thumbnail_url, 'photo_url': photo_url})
    return {'statusCode': 200, 'body': json.dumps(files)}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd aws_backend/lambda && python3 -m pytest tests/test_photos.py::TestGetPhotos -v
```

Expected: both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add aws_backend/lambda/lambda_handler.py aws_backend/lambda/tests/test_photos.py
git commit -m "feat(backend): return presigned S3 URLs for photo listing"
```

---

## Task 3: Backend — atomic delete route

**Files:**
- Modify: `aws_backend/lambda/lambda_handler.py`
- Modify: `aws_backend/lambda/tests/test_photos.py`

- [ ] **Step 1: Write the failing test**

Add to `aws_backend/lambda/tests/test_photos.py`:

```python
class TestDeletePhoto(unittest.TestCase):
    def setUp(self):
        self.mock_s3 = MagicMock()
        _boto3_mock.client.return_value = self.mock_s3

    def _delete_event(self, basename):
        return {
            'requestContext': {'http': {'method': 'DELETE', 'path': f'/photos/{basename}'}},
            'headers': {'applicationid': APP_ID},
            'pathParameters': {'proxy': basename},
        }

    def test_deletes_both_img_and_thumbnail(self):
        event = self._delete_event('foo.jpg')
        response = lambda_handler.delete_photo(event, APP_ID)
        self.assertEqual(response['statusCode'], 200)
        delete_calls = self.mock_s3.delete_object.call_args_list
        keys = [c.kwargs['Key'] for c in delete_calls]
        self.assertIn(f'{APP_ID}/photos/img/foo.jpg', keys)
        self.assertIn(f'{APP_ID}/photos/thumbnails/foo.jpg', keys)

    def test_returns_400_when_basename_missing(self):
        event = {
            'requestContext': {'http': {'method': 'DELETE', 'path': '/photos/'}},
            'headers': {'applicationid': APP_ID},
            'pathParameters': {},
        }
        response = lambda_handler.delete_photo(event, APP_ID)
        self.assertEqual(response['statusCode'], 400)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd aws_backend/lambda && python3 -m pytest tests/test_photos.py::TestDeletePhoto -v
```

Expected: FAIL — `delete_photo` not defined.

- [ ] **Step 3: Add `delete_photo` function and dispatch route**

Add after `add_photo` in `lambda_handler.py`:

```python
def delete_photo(event, application_id):
    import urllib.parse
    proxy = (event.get('pathParameters') or {}).get('proxy')
    if not proxy:
        return {'statusCode': 400, 'body': json.dumps({'error': 'Dateiname fehlt'})}
    basename = urllib.parse.unquote(proxy)
    s3 = boto3.client('s3')
    s3.delete_object(Bucket=s3_bucket_name, Key=f'{application_id}/photos/img/{basename}')
    s3.delete_object(Bucket=s3_bucket_name, Key=f'{application_id}/photos/thumbnails/{basename}')
    return {'statusCode': 200, 'body': json.dumps({'message': f'{basename} gelöscht'})}
```

Add to `_dispatch` (after the existing POST /photos line):

```python
elif method == 'DELETE' and path.startswith('/photos/'):
    return {**headers, **delete_photo(event, application_id)}
```

- [ ] **Step 4: Run all photo tests**

```bash
cd aws_backend/lambda && python3 -m pytest tests/test_photos.py -v
```

Expected: all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add aws_backend/lambda/lambda_handler.py aws_backend/lambda/tests/test_photos.py
git commit -m "feat(backend): add atomic delete for photo + thumbnail"
```

---

## Task 4: Flutter API — update `gallery_api.dart`

**Files:**
- Modify: `lib/api/gallery_api.dart`
- Modify: `test/api/gallery_api_test.dart`

- [ ] **Step 1: Rewrite the tests first**

Replace the entire content of `test/api/gallery_api_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vereinsappell/api/gallery_api.dart';

import 'api_test_helpers.dart';

void main() {
  group('fetchThumbnails', () {
    test('200 → returns list with thumbnail_url and photo_url', () async {
      final payload = [
        {
          'name': 'photo.jpg',
          'thumbnail_url': 'https://s3.example.com/thumb/photo.jpg',
          'photo_url': 'https://s3.example.com/img/photo.jpg',
        }
      ];
      final result = await withStubConfig(
        body: (config, client) =>
            GalleryApi(config, client: client).fetchThumbnails(),
        apiHandler: (_) async => http.Response(jsonEncode(payload), 200),
      );
      expect(result.length, 1);
      expect(result[0]['thumbnail_url'], 'https://s3.example.com/thumb/photo.jpg');
      expect(result[0]['photo_url'], 'https://s3.example.com/img/photo.jpg');
    });

    test('non-200 → throws', () async {
      expect(
        () => withStubConfig(
          body: (config, client) =>
              GalleryApi(config, client: client).fetchThumbnails(),
          apiHandler: (_) async => http.Response('Error', 500),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('uploadPhoto', () {
    test('makes exactly 1 POST request', () async {
      int postCount = 0;
      await withStubConfig(
        body: (config, client) => GalleryApi(config, client: client).uploadPhoto(
          original: Uint8List.fromList([1, 2, 3]),
          filename: 'photo.jpg',
        ),
        apiHandler: (request) async {
          if (request.method == 'POST') postCount++;
          return http.Response('{}', 200);
        },
      );
      expect(postCount, 1);
    });

    test('POST body contains name without prefix', () async {
      Map<String, dynamic>? sentBody;
      await withStubConfig(
        body: (config, client) => GalleryApi(config, client: client).uploadPhoto(
          original: Uint8List.fromList([1]),
          filename: 'photo.png',
        ),
        apiHandler: (request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        },
      );
      expect(sentBody!['name'], 'photo.jpg'); // extension normalized to .jpg
      expect(sentBody!.containsKey('file'), isTrue);
    });

    test('non-200 → throws', () async {
      expect(
        () => withStubConfig(
          body: (config, client) => GalleryApi(config, client: client).uploadPhoto(
            original: Uint8List.fromList([1]),
            filename: 'photo.jpg',
          ),
          apiHandler: (_) async => http.Response('Error', 500),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('deletePhoto', () {
    test('DELETE to /photos/{basename}', () async {
      await withStubConfig(
        body: (config, client) =>
            GalleryApi(config, client: client).deletePhoto('photo.jpg'),
        apiHandler: (request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/photos/photo.jpg');
          return http.Response('{}', 200);
        },
      );
    });

    test('non-200 → throws', () async {
      expect(
        () => withStubConfig(
          body: (config, client) =>
              GalleryApi(config, client: client).deletePhoto('photo.jpg'),
          apiHandler: (_) async => http.Response('Error', 500),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /home/lars/tzg/vereinsappell && flutter test test/api/gallery_api_test.dart
```

Expected: multiple failures — old API signatures don't match.

- [ ] **Step 3: Rewrite `lib/api/gallery_api.dart`**

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config_loader.dart';
import 'headers.dart';

class GalleryApi {
  final AppConfig config;
  final http.Client _client;

  GalleryApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Future<List<Map<String, String>>> fetchThumbnails() async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/photos/thumbnails'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((e) => {
        'name': e['name'] as String,
        'thumbnail_url': e['thumbnail_url'] as String,
        'photo_url': e['photo_url'] as String,
      }).toList();
    } else {
      throw Exception('Fehler beim Laden der Fotos: ${response.statusCode}');
    }
  }

  Future<void> uploadPhoto({
    required Uint8List original,
    required String filename,
  }) async {
    final basename = filename.contains('.')
        ? '${filename.substring(0, filename.lastIndexOf('.'))}.jpg'
        : '$filename.jpg';
    final response = await _client.post(
      Uri.parse('${config.apiBaseUrl}/photos'),
      headers: headers(config),
      body: json.encode({'file': base64Encode(original), 'name': basename}),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Hochladen: ${response.statusCode}');
    }
  }

  Future<void> deletePhoto(String basename) async {
    final response = await _client.delete(
      Uri.parse('${config.apiBaseUrl}/photos/$basename'),
      headers: headers(config),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Löschen: ${response.statusCode}');
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /home/lars/tzg/vereinsappell && flutter test test/api/gallery_api_test.dart
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/api/gallery_api.dart test/api/gallery_api_test.dart
git commit -m "feat(flutter): update GalleryApi to use presigned URLs"
```

---

## Task 5: Flutter UI — `PhotoLightbox` widget

**Files:**
- Create: `lib/widgets/photo_lightbox.dart`

- [ ] **Step 1: Create `lib/widgets/photo_lightbox.dart`**

```dart
import 'package:flutter/material.dart';

class PhotoLightbox extends StatefulWidget {
  final List<Map<String, String>> photos;
  final int initialIndex;
  final bool isAdmin;
  final Future<void> Function(String basename) onDelete;

  const PhotoLightbox({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.isAdmin,
    required this.onDelete,
  });

  @override
  State<PhotoLightbox> createState() => _PhotoLightboxState();
}

class _PhotoLightboxState extends State<PhotoLightbox> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Foto löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.onDelete(widget.photos[_currentIndex]['name']!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0).abs() > 300) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.network(
                  widget.photos[i]['photo_url']!,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 48)),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
            if (widget.isAdmin)
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.white),
                      onPressed: _confirmDelete,
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Text(
                '${_currentIndex + 1} / ${widget.photos.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /home/lars/tzg/vereinsappell && flutter build web --no-pub 2>&1 | head -30
```

Expected: only errors from `galerie_screen.dart` which still imports the old API (fixed in next task).

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/photo_lightbox.dart
git commit -m "feat(flutter): add PhotoLightbox widget with swipe and zoom"
```

---

## Task 6: Flutter UI — rewrite `galerie_screen.dart`

**Files:**
- Modify: `lib/screens/galerie_screen.dart`

- [ ] **Step 1: Replace `galerie_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vereinsappell/screens/default_screen.dart';
import 'package:vereinsappell/widgets/photo_lightbox.dart';

import '../api/gallery_api.dart';

class GalleryScreen extends DefaultScreen {
  const GalleryScreen({
    super.key,
    required super.config,
  }) : super(title: 'Fotogalerie');

  @override
  DefaultScreenState createState() => _GalleryScreenState();
}

class _GalleryScreenState extends DefaultScreenState<GalleryScreen> {
  late final GalleryApi api;
  List<Map<String, String>> photos = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    api = GalleryApi(widget.config);
    fetchThumbnails();
  }

  Future<void> fetchThumbnails() async {
    setState(() => isLoading = true);
    try {
      final data = await api.fetchThumbnails();
      setState(() => photos = data);
    } catch (e) {
      showError('Fehler: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> uploadPhoto() async {
    final XFile? pickedFile =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (pickedFile == null) return;
    final originalBytes = await pickedFile.readAsBytes();
    setState(() => isLoading = true);
    try {
      await api.uploadPhoto(original: originalBytes, filename: pickedFile.name);
      showInfo('Foto hochgeladen');
      await fetchThumbnails();
    } catch (e) {
      showError('Fehler: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> deletePhoto(String basename) async {
    setState(() => isLoading = true);
    try {
      await api.deletePhoto(basename);
      showInfo('Foto gelöscht');
      await fetchThumbnails();
    } catch (e) {
      showError('Fehler: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _openLightbox(int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PhotoLightbox(
        photos: photos,
        initialIndex: index,
        isAdmin: widget.config.member.isAdmin,
        onDelete: deletePhoto,
      ),
      fullscreenDialog: true,
    ));
  }

  static const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 130,
    crossAxisSpacing: 4,
    mainAxisSpacing: 4,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📸 Fotogalerie'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_a_photo),
            onPressed: uploadPhoto,
            tooltip: 'Foto hochladen',
          ),
        ],
      ),
      body: isLoading && photos.isEmpty
          ? GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: _gridDelegate,
              itemCount: 12,
              itemBuilder: (_, __) => const _ShimmerTile(),
            )
          : photos.isEmpty
              ? const Center(child: Text('Keine Fotos vorhanden'))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: _gridDelegate,
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    final photo = photos[index];
                    return GestureDetector(
                      onTap: () => _openLightbox(index),
                      child: Image.network(
                        photo['thumbnail_url']!,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) =>
                            progress == null ? child : const _ShimmerTile(),
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                      ),
                    );
                  },
                ),
    );
  }
}

class _ShimmerTile extends StatefulWidget {
  const _ShimmerTile();

  @override
  State<_ShimmerTile> createState() => _ShimmerTileState();
}

class _ShimmerTileState extends State<_ShimmerTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _anim = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value, 0),
            colors: const [
              Color(0xFF2a2a2a),
              Color(0xFF3d3d3d),
              Color(0xFF2a2a2a),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run the full test suite**

```bash
cd /home/lars/tzg/vereinsappell && flutter test
```

Expected: all tests pass (gallery_api_test.dart and others).

- [ ] **Step 3: Build to verify no compile errors**

```bash
cd /home/lars/tzg/vereinsappell && flutter build web --no-pub 2>&1 | tail -10
```

Expected: `✓ Built build/web` with no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/galerie_screen.dart
git commit -m "feat(flutter): responsive grid, shimmer loading, lightbox viewer"
```

---

## Task 7: Deploy backend

**Files:**
- Run: `aws_backend/lambda/build.sh` or `update.sh`

- [ ] **Step 1: Check how deployment works**

```bash
cat aws_backend/lambda/update.sh
```

- [ ] **Step 2: Install Pillow into the Lambda package dir**

```bash
cd aws_backend/lambda && pip install pillow --target . --upgrade
```

- [ ] **Step 3: Run all backend tests to confirm nothing is broken**

```bash
cd aws_backend/lambda && python3 -m pytest tests/ -v
```

Expected: all tests pass.

- [ ] **Step 4: Deploy**

```bash
cd aws_backend/lambda && bash update.sh
```

This zips the Lambda directory and calls `aws lambda update-function-code` on `vereins-app-beta-lambda_backend`.

- [ ] **Step 5: Smoke-test against live API**

With the app running (`flutter run -d chrome`), open the Galerie screen and verify:
- Shimmer tiles appear immediately on load
- Thumbnails replace shimmer tiles as they load
- Tapping a thumbnail opens the fullscreen lightbox
- Swipe left/right navigates between photos
- Pinch zooms
- X button and swipe-down close the lightbox
- Admin: delete button appears in lightbox, confirm dialog works

- [ ] **Step 6: Commit**

```bash
git add aws_backend/lambda/
git commit -m "chore(backend): install Pillow for Lambda package"
```

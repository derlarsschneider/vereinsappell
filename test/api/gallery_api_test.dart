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

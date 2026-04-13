import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vereinsappell/api/gallery_api.dart';

import 'api_test_helpers.dart';

void main() {
  group('fetchThumbnails', () {
    test('200 → returns list', () async {
      final payload = [
        {'name': 'thumbnails/photo.jpg', 'file': 'abc'}
      ];
      final result = await withStubConfig(
        body: (config, client) =>
            GalleryApi(config, client: client).fetchThumbnails(),
        apiHandler: (_) async => http.Response(jsonEncode(payload), 200),
      );
      expect(result.length, 1);
    });
  });

  group('uploadPhoto', () {
    test('makes exactly 2 POST requests', () async {
      int postCount = 0;
      await withStubConfig(
        body: (config, client) => GalleryApi(config, client: client).uploadPhoto(
          original: Uint8List.fromList([1, 2, 3]),
          thumbnail: Uint8List.fromList([4, 5, 6]),
          filename: 'photo.jpg',
        ),
        apiHandler: (request) async {
          if (request.method == 'POST') postCount++;
          return http.Response('{}', 200);
        },
      );
      expect(postCount, 2);
    });

    test('first POST fails → throws, second POST is not made', () async {
      int postCount = 0;
      expect(
        () => withStubConfig(
          body: (config, client) => GalleryApi(config, client: client).uploadPhoto(
            original: Uint8List.fromList([1]),
            thumbnail: Uint8List.fromList([2]),
            filename: 'photo.jpg',
          ),
          apiHandler: (request) async {
            postCount++;
            if (postCount == 1) return http.Response('Error', 500);
            return http.Response('{}', 200);
          },
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('deletePhoto', () {
    test('DELETE to correct URL', () async {
      await withStubConfig(
        body: (config, client) =>
            GalleryApi(config, client: client).deletePhoto('thumbnails/photo.jpg'),
        apiHandler: (request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/photos/thumbnails/photo.jpg');
          return http.Response('{}', 200);
        },
      );
    });
  });
}

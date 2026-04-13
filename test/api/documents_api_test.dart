import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vereinsappell/api/documents_api.dart';

import 'api_test_helpers.dart';

void main() {
  group('fetchDocuments', () {
    test('200 → returns list', () async {
      final payload = [
        {'name': 'Protokolle/p.pdf'},
        {'name': 'info.pdf'},
      ];
      final result = await withStubConfig(
        sessionPassword: 'geheim',
        body: (config, client) =>
            DocumentApi(config, client: client).fetchDocuments(),
        apiHandler: (_) async => http.Response(jsonEncode(payload), 200),
      );
      expect(result.length, 2);
    });

    test('401 → throws Exception with "Falsches Passwort"', () async {
      expect(
        () => withStubConfig(
          sessionPassword: 'geheim',
          body: (config, client) =>
              DocumentApi(config, client: client).fetchDocuments(),
          apiHandler: (_) async => http.Response('Unauthorized', 401),
        ),
        throwsA(predicate<Exception>(
            (e) => e.toString().contains('Falsches Passwort'))),
      );
    });
  });

  group('uploadDocument', () {
    test('POST body contains name and base64 file', () async {
      await withStubConfig(
        sessionPassword: 'geheim',
        body: (config, client) => DocumentApi(config, client: client)
            .uploadDocument(name: 'test.pdf', fileBytes: [1, 2, 3]),
        apiHandler: (request) async {
          expect(request.method, 'POST');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['name'], 'test.pdf');
          expect(body.containsKey('file'), isTrue);
          return http.Response('{}', 200);
        },
      );
    });
  });

  group('URL encoding', () {
    test('simple filename → /docs/file.pdf', () async {
      await withStubConfig(
        sessionPassword: 'geheim',
        body: (config, client) =>
            DocumentApi(config, client: client).deleteDocument('file.pdf'),
        apiHandler: (request) async {
          expect(request.url.path, '/docs/file.pdf');
          return http.Response('{}', 200);
        },
      );
    });

    test('category/filename → /docs/Protokolle/file.pdf', () async {
      await withStubConfig(
        sessionPassword: 'geheim',
        body: (config, client) => DocumentApi(config, client: client)
            .deleteDocument('Protokolle/file.pdf'),
        apiHandler: (request) async {
          expect(request.url.path, '/docs/Protokolle/file.pdf');
          return http.Response('{}', 200);
        },
      );
    });

    test('Umlauts and spaces percent-encoded per segment', () async {
      await withStubConfig(
        sessionPassword: 'geheim',
        body: (config, client) =>
            DocumentApi(config, client: client).deleteDocument('Ä B/üml.pdf'),
        apiHandler: (request) async {
          expect(request.url.toString(), contains('%C3%84%20B'));
          return http.Response('{}', 200);
        },
      );
    });
  });
}

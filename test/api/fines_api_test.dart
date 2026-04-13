import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vereinsappell/api/fines_api.dart';

import 'api_test_helpers.dart';

void main() {
  group('fetchFines', () {
    test('200 → returns map with name and fines', () async {
      final payload = {
        'name': 'Max Muster',
        'fines': [
          {'fineId': 'f1', 'reason': 'Zu spät', 'amount': '5'}
        ],
      };
      final result = await withStubConfig(
        body: (config, client) =>
            FinesApi(config, client: client).fetchFines('u1'),
        apiHandler: (_) async => http.Response(jsonEncode(payload), 200),
      );
      expect(result['name'], 'Max Muster');
      expect((result['fines'] as List).length, 1);
    });

    test('500 → throws Exception', () async {
      expect(
        () => withStubConfig(
          body: (config, client) =>
              FinesApi(config, client: client).fetchFines('u1'),
          apiHandler: (_) async => http.Response('Error', 500),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('addFine', () {
    test('POST body contains fineId, memberId, reason, amount', () async {
      await withStubConfig(
        body: (config, client) =>
            FinesApi(config, client: client).addFine('u1', 'Zu spät', 5.0),
        apiHandler: (request) async {
          expect(request.method, 'POST');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body.containsKey('fineId'), isTrue);
          expect(body['memberId'], 'u1');
          expect(body['reason'], 'Zu spät');
          expect(body.containsKey('amount'), isTrue);
          return http.Response('{}', 200);
        },
      );
    });
  });

  group('deleteFine', () {
    test('DELETE to /fines/{id}?memberId={id}', () async {
      await withStubConfig(
        body: (config, client) =>
            FinesApi(config, client: client).deleteFine('f1', 'u1'),
        apiHandler: (request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/fines/f1');
          expect(request.url.queryParameters['memberId'], 'u1');
          return http.Response('{}', 200);
        },
      );
    });
  });
}

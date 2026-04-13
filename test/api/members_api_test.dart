import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vereinsappell/api/members_api.dart';

import 'api_test_helpers.dart';

void main() {
  group('fetchMembers', () {
    test('200 → returns list', () async {
      final payload = [
        {'memberId': 'u1', 'name': 'Alice'},
        {'memberId': 'u2', 'name': 'Bob'},
      ];
      final result = await withStubConfig(
        body: (config, client) =>
            MembersApi(config, client: client).fetchMembers(),
        apiHandler: (request) async {
          expect(request.url.path, '/members');
          return http.Response(jsonEncode(payload), 200);
        },
      );
      expect(result.length, 2);
    });

    test('403 → throws Exception with statusCode', () async {
      expect(
        () => withStubConfig(
          body: (config, client) =>
              MembersApi(config, client: client).fetchMembers(),
          apiHandler: (_) async => http.Response('Forbidden', 403),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Auth headers: applicationId and memberId present', () async {
      await withStubConfig(
        body: (config, client) =>
            MembersApi(config, client: client).fetchMembers(),
        apiHandler: (request) async {
          expect(request.headers['applicationId'], 'test-app');
          expect(request.headers['memberId'], 'user-1');
          return http.Response('[]', 200);
        },
      );
    });
  });

  group('createMember', () {
    test('POST to /members, body contains applicationId-prefixed memberId',
        () async {
      await withStubConfig(
        body: (config, client) =>
            MembersApi(config, client: client).createMember('Alice', 'test-app'),
        apiHandler: (request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/members');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect((body['memberId'] as String).startsWith('test-app'), isTrue);
          return http.Response(jsonEncode(body), 200);
        },
      );
    });
  });

  group('saveMember', () {
    test('POST with correct JSON body', () async {
      final member = {'memberId': 'u1', 'name': 'Alice', 'isAdmin': false};
      await withStubConfig(
        body: (config, client) =>
            MembersApi(config, client: client).saveMember(member),
        apiHandler: (request) async {
          expect(request.method, 'POST');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['name'], 'Alice');
          return http.Response('{}', 200);
        },
      );
    });
  });

  group('deleteMember', () {
    test('DELETE to /members/{id}', () async {
      await withStubConfig(
        body: (config, client) =>
            MembersApi(config, client: client).deleteMember('u1'),
        apiHandler: (request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/members/u1');
          return http.Response('{}', 200);
        },
      );
    });
  });
}

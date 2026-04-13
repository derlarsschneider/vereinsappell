import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vereinsappell/api/headers.dart';
import 'package:vereinsappell/config_loader.dart';

// Wraps the test body in a zone where Member.fetchMember() does not throw.
Future<void> withStubHttp(Future<void> Function() body) {
  final client = MockClient((_) async => http.Response('{}', 200));
  return http.runWithClient(body, () => client);
}

void main() {
  group('headers()', () {
    late AppConfig config;

    setUp(() async {
      await withStubHttp(() async {
        config = AppConfig(
          apiBaseUrl: 'https://api.example.com',
          applicationId: 'test-app',
          memberId: 'user-42',
        );
      });
    });

    test('enthält Content-Type, applicationId, memberId, password', () {
      final h = headers(config);
      expect(h, containsPair('Content-Type', 'application/json'));
      expect(h, containsPair('applicationId', 'test-app'));
      expect(h, containsPair('memberId', 'user-42'));
      expect(h.containsKey('password'), isTrue);
    });

    test("password ist '' wenn sessionPassword == null", () {
      final h = headers(config);
      expect(h['password'], '');
    });

    test('applicationId und memberId werden korrekt übernommen', () {
      final h = headers(config);
      expect(h['applicationId'], 'test-app');
      expect(h['memberId'], 'user-42');
    });
  });
}

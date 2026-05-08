import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/utils/invite_link.dart';

void main() {
  group('parseInviteLink', () {
    test('parses all four params from a full URL', () {
      final result = parseInviteLink(
        'https://app.example.com/?apiBaseUrl=https%3A%2F%2Fapi.example.com&applicationId=app-1&memberId=mem-1&password=secret',
      );
      expect(result['apiBaseUrl'], 'https://api.example.com');
      expect(result['applicationId'], 'app-1');
      expect(result['memberId'], 'mem-1');
      expect(result['password'], 'secret');
    });

    test('returns only present params — no password key when absent', () {
      final result = parseInviteLink(
        'https://app.example.com/?apiBaseUrl=https%3A%2F%2Fapi.example.com&applicationId=app-1&memberId=mem-1',
      );
      expect(result['apiBaseUrl'], 'https://api.example.com');
      expect(result['applicationId'], 'app-1');
      expect(result['memberId'], 'mem-1');
      expect(result.containsKey('password'), false);
    });

    test('returns empty map for non-URL input', () {
      expect(parseInviteLink('not a url'), isEmpty);
    });

    test('returns empty map for URL missing required params', () {
      expect(parseInviteLink('https://app.example.com/'), isEmpty);
    });

    test('returns empty map for empty string', () {
      expect(parseInviteLink(''), isEmpty);
    });
  });
}

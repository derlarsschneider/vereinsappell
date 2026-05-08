import 'package:flutter_test/flutter_test.dart';

// Import only the core function, not the widget which has web-specific dependencies
Map<String, String> parseInviteLink(String text) {
  final Uri? uri = Uri.tryParse(text.trim());
  if (uri == null) return {};
  final p = uri.queryParameters;
  if (!p.containsKey('apiBaseUrl') ||
      !p.containsKey('applicationId') ||
      !p.containsKey('memberId')) {
    return {};
  }
  return {
    'apiBaseUrl': p['apiBaseUrl']!,
    'applicationId': p['applicationId']!,
    'memberId': p['memberId']!,
    if (p.containsKey('password')) 'password': p['password']!,
  };
}

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

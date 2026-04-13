// Shared test helpers for API layer tests.
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vereinsappell/config_loader.dart';

/// Runs [body] inside an http zone where Member.fetchMember() is silently
/// answered with `{}` (200), while all other requests are forwarded to
/// [apiHandler]. Returns a [MockClient] that intercepts the zone's http calls.
Future<T> withStubConfig<T>({
  required Future<T> Function(AppConfig config, http.Client apiClient) body,
  required Future<http.Response> Function(http.Request) apiHandler,
  String sessionPassword = '',
}) {
  late http.Client zoneClient;

  zoneClient = MockClient((request) async {
    // Silently answer fetchMember() calls from the Member constructor
    if (request.method == 'GET' &&
        request.url.path.startsWith('/members/') &&
        !request.url.path.contains('/members/\u0000')) {
      // heuristic: these are Member.fetchMember() background calls
      final pathSegments = request.url.pathSegments;
      if (pathSegments.length == 2 && pathSegments[0] == 'members') {
        return http.Response('{}', 200);
      }
    }
    return apiHandler(request);
  });

  return http.runWithClient(() async {
    final config = AppConfig(
      apiBaseUrl: 'https://api.example.com',
      applicationId: 'test-app',
      memberId: 'user-1',
      sessionPassword: sessionPassword.isEmpty ? null : sessionPassword,
    );
    return body(config, zoneClient);
  }, () => zoneClient);
}

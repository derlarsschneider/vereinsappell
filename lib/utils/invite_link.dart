/// Production API endpoint, used when an invite link has no apiBaseUrl.
/// Same default as the landing page login (web/index.html).
const String kDefaultApiBaseUrl =
    'https://v49kyt4758.execute-api.eu-central-1.amazonaws.com';

Map<String, String> parseInviteLink(String text) {
  final Uri? uri = Uri.tryParse(text.trim());
  if (uri == null) return {};
  final p = uri.queryParameters;
  if (!p.containsKey('applicationId') || !p.containsKey('memberId')) {
    return {};
  }
  return {
    'apiBaseUrl': p['apiBaseUrl'] ?? kDefaultApiBaseUrl,
    'applicationId': p['applicationId']!,
    'memberId': p['memberId']!,
    if (p.containsKey('password')) 'password': p['password']!,
  };
}

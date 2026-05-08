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

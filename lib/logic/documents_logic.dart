// lib/logic/documents_logic.dart
// Pure document grouping logic – no Flutter dependencies.

/// Groups a flat document list into a sorted category map.
///
/// Documents with a `/` in the name are split into category and short name.
/// Named categories come first (alphabetically), then the uncategorised `''` key.
/// Files within each category are also sorted alphabetically.
Map<String, List<String>> groupDocuments(List<Map<String, dynamic>> docs) {
  final Map<String, List<String>> result = {};
  for (final doc in docs) {
    final name = doc['name'] as String? ?? '';
    final slash = name.indexOf('/');
    final category = slash >= 0 ? name.substring(0, slash) : '';
    final shortName = slash >= 0 ? name.substring(slash + 1) : name;
    (result[category] ??= []).add(shortName);
  }
  final sorted = <String, List<String>>{};
  final named = result.keys.where((k) => k.isNotEmpty).toList()..sort();
  for (final k in named) { sorted[k] = result[k]!..sort(); }
  if (result.containsKey('')) sorted[''] = result['']!..sort();
  return sorted;
}

/// Reconstructs the full document name (with optional category prefix).
String fullDocumentName(String category, String shortName) =>
    category.isEmpty ? shortName : '$category/$shortName';

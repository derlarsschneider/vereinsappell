class TallyEntry {
  final String id;
  final String drinkId;
  final String memberId;
  final String type; // 'strich' | 'flasche'
  final int timestamp;

  TallyEntry({
    required this.id,
    required this.drinkId,
    required this.memberId,
    required this.type,
    required this.timestamp,
  });

  factory TallyEntry.fromMap(String drinkId, String id, Map<dynamic, dynamic> map) {
    return TallyEntry(
      id: id,
      drinkId: drinkId,
      memberId: map['memberId'] as String,
      type: map['type'] as String,
      timestamp: map['timestamp'] as int? ?? 0,
    );
  }
}

List<TallyEntry> parseTallies(Object? data) {
  if (data == null || data is! Map) return [];
  final entries = <TallyEntry>[];
  for (final drinkEntry in Map<dynamic, dynamic>.from(data).entries) {
    final drinkId = drinkEntry.key as String;
    if (drinkEntry.value is! Map) continue;
    final marksMap = Map<dynamic, dynamic>.from(drinkEntry.value as Map);
    for (final markEntry in marksMap.entries) {
      final id = markEntry.key as String;
      if (markEntry.value is! Map) continue;
      entries.add(TallyEntry.fromMap(drinkId, id, Map<dynamic, dynamic>.from(markEntry.value)));
    }
  }
  return entries;
}

import 'package:firebase_database/firebase_database.dart';
import '../config_loader.dart';

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

class GetraenkeApi {
  final AppConfig config;

  GetraenkeApi(this.config);

  DatabaseReference get _ref =>
      FirebaseDatabase.instance.ref('tallies/${config.applicationId}');

  Stream<List<TallyEntry>> watchTallies() {
    return _ref.onValue.map((event) => parseTallies(event.snapshot.value));
  }

  Future<void> addMark(String drinkId, String type) async {
    await _ref.child(drinkId).push().set({
      'memberId': config.memberId,
      'type': type,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> clearAll() async {
    await _ref.remove();
  }

  Future<void> deleteMark(String drinkId, String entryId) async {
    final ref = _ref.child(drinkId).child(entryId);
    await ref.remove();
  }
}

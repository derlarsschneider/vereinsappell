import 'package:firebase_database/firebase_database.dart';
import '../config_loader.dart';

class TallyEntry {
  final String drinkId;
  final String memberId;
  final String type; // 'strich' | 'flasche'

  TallyEntry({
    required this.drinkId,
    required this.memberId,
    required this.type,
  });

  factory TallyEntry.fromMap(String drinkId, Map<dynamic, dynamic> map) {
    return TallyEntry(
      drinkId: drinkId,
      memberId: map['memberId'] as String,
      type: map['type'] as String,
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
    for (final mark in marksMap.values) {
      if (mark is! Map) continue;
      entries.add(TallyEntry.fromMap(drinkId, Map<dynamic, dynamic>.from(mark)));
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

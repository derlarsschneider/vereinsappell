import 'package:firebase_database/firebase_database.dart';
import '../config_loader.dart';
import '../models/tally_entry.dart';

export '../models/tally_entry.dart';

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

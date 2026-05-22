import 'package:firebase_database/firebase_database.dart';
import '../config_loader.dart';
import '../models/umlage.dart';
import 'umlagen_api_interface.dart';

class UmlagenApi implements IUmlagenApi {
  final AppConfig config;

  UmlagenApi(this.config);

  DatabaseReference get _activeRef =>
      FirebaseDatabase.instance.ref('umlagen/${config.applicationId}/active');

  DatabaseReference get _historyRef =>
      FirebaseDatabase.instance.ref('umlagen/${config.applicationId}/history');

  DatabaseReference _statsRef(String memberId) =>
      FirebaseDatabase.instance.ref('umlagen/${config.applicationId}/stats/$memberId');

  @override
  Stream<UmlageSession?> watchActiveSession(String collectorId) {
    return _activeRef.child(collectorId).onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return null;
      return UmlageSession.fromSnapshot(collectorId, data);
    });
  }

  @override
  Stream<List<UmlageSession>> watchAllActive() {
    return _activeRef.onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return [];
      return data.entries
          .where((e) => e.value is Map)
          .map((e) => UmlageSession.fromSnapshot(
                e.key as String,
                e.value as Map<dynamic, dynamic>,
              ))
          .toList();
    });
  }

  @override
  Future<void> startSession({
    required String collectorId,
    required int amount,
    required String name,
    required List<String> memberIds,
  }) async {
    final participants = {for (final id in memberIds) id: 'pending'};
    await _activeRef.child(collectorId).set({
      'amount': amount,
      'name': name,
      'startedAt': DateTime.now().millisecondsSinceEpoch,
      'participants': participants,
    });
  }

  @override
  Future<void> updateParticipant({
    required String collectorId,
    required String memberId,
    required String status,
  }) async {
    await _activeRef
        .child(collectorId)
        .child('participants')
        .child(memberId)
        .set(status);
  }

  @override
  Future<void> closeSession({
    required String collectorId,
    required UmlageSession session,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final historyRef = _historyRef.push();
    final statsRef = _statsRef(collectorId);

    final participantsMap = {
      for (final e in session.participants.entries)
        if (e.value != 'pending') e.key: e.value
    };

    // Write history first
    await historyRef.set({
      'collectorId': collectorId,
      'amount': session.amount,
      'name': session.name,
      'startedAt': session.startedAt,
      'closedAt': now,
      'totalPaid': session.totalCollected,
      'participants': participantsMap,
    });

    // Update stats via transaction
    await statsRef.runTransaction((currentData) {
      final current = currentData as Map<dynamic, dynamic>? ?? {};
      return Transaction.success({
        'totalCollected': ((current['totalCollected'] as num?) ?? 0) + session.totalCollected,
        'collectionsCount': ((current['collectionsCount'] as num?) ?? 0) + 1,
      });
    });

    // Remove from active
    await _activeRef.child(collectorId).remove();
  }

  @override
  Future<List<HistoryEntry>> fetchHistory({int limit = 20, int? beforeClosedAt}) async {
    Query query = _historyRef.orderByChild('closedAt').limitToLast(limit);
    if (beforeClosedAt != null) {
      query = query.endBefore(beforeClosedAt);
    }
    final snapshot = await query.get();
    if (!snapshot.exists || snapshot.value is! Map) return [];

    final entries = (snapshot.value as Map<dynamic, dynamic>)
        .entries
        .where((e) => e.value is Map)
        .map((e) => HistoryEntry.fromSnapshot(
              e.key as String,
              e.value as Map<dynamic, dynamic>,
            ))
        .toList()
      ..sort((a, b) => b.closedAt.compareTo(a.closedAt));

    return entries;
  }
}

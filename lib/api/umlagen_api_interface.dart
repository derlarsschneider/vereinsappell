import '../models/umlage.dart';

abstract class IUmlagenApi {
  Stream<UmlageSession?> watchActiveSession(String collectorId);
  Stream<List<UmlageSession>> watchAllActive();
  Future<void> startSession({
    required String collectorId,
    required int amount,
    required String name,
    required List<String> memberIds,
  });
  Future<void> updateParticipant({
    required String collectorId,
    required String memberId,
    required String status,
  });
  Future<void> closeSession({
    required String collectorId,
    required UmlageSession session,
  });
  Future<List<HistoryEntry>> fetchHistory({int limit = 20, String? startAfterKey});
}

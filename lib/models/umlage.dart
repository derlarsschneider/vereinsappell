import 'package:intl/intl.dart';

class UmlageSession {
  final String collectorId;
  final int amount;
  final String name;
  final int startedAt;
  final Map<String, String> participants;

  UmlageSession({
    required this.collectorId,
    required this.amount,
    required this.name,
    required this.startedAt,
    required this.participants,
  });

  factory UmlageSession.fromSnapshot(String collectorId, Map<dynamic, dynamic> data) {
    final rawParticipants = data['participants'];
    final participants = <String, String>{};
    if (rawParticipants is Map) {
      for (final e in rawParticipants.entries) {
        participants[e.key as String] = e.value as String;
      }
    }
    return UmlageSession(
      collectorId: collectorId,
      amount: (data['amount'] as num?)?.toInt() ?? 0,
      name: (data['name'] as String?) ?? '',
      startedAt: (data['startedAt'] as num?)?.toInt() ?? 0,
      participants: participants,
    );
  }

  String get displayName {
    if (name.isNotEmpty) return name;
    final dt = DateTime.fromMillisecondsSinceEpoch(startedAt);
    return 'Umlage ${DateFormat('dd.MM.yyyy HH:mm').format(dt)}';
  }

  int get paidCount =>
      participants.values.where((s) => s == 'paid').length;

  int get activeCount =>
      participants.values.where((s) => s != 'excluded').length;

  int get totalCollected => paidCount * amount;
}

class HistoryEntry {
  final String id;
  final String collectorId;
  final int amount;
  final String name;
  final int startedAt;
  final int closedAt;
  final int totalPaid;
  final Map<String, String> participants;

  HistoryEntry({
    required this.id,
    required this.collectorId,
    required this.amount,
    required this.name,
    required this.startedAt,
    required this.closedAt,
    required this.totalPaid,
    required this.participants,
  });

  factory HistoryEntry.fromSnapshot(String id, Map<dynamic, dynamic> data) {
    final rawParticipants = data['participants'];
    final participants = <String, String>{};
    if (rawParticipants is Map) {
      for (final e in rawParticipants.entries) {
        participants[e.key as String] = e.value as String;
      }
    }
    return HistoryEntry(
      id: id,
      collectorId: (data['collectorId'] as String?) ?? '',
      amount: (data['amount'] as num?)?.toInt() ?? 0,
      name: (data['name'] as String?) ?? '',
      startedAt: (data['startedAt'] as num?)?.toInt() ?? 0,
      closedAt: (data['closedAt'] as num?)?.toInt() ?? 0,
      totalPaid: (data['totalPaid'] as num?)?.toInt() ?? 0,
      participants: participants,
    );
  }

  String get displayName {
    if (name.isNotEmpty) return name;
    final dt = DateTime.fromMillisecondsSinceEpoch(startedAt);
    return 'Umlage ${DateFormat('dd.MM.yyyy HH:mm').format(dt)}';
  }

  bool memberPaid(String memberId) => participants[memberId] == 'paid';

  int get paidCount =>
      participants.values.where((s) => s == 'paid').length;
}

import 'package:firebase_database/firebase_database.dart';
import '../config_loader.dart';
import '../models/poll.dart';

export '../models/poll.dart';

class PollsApi {
  final AppConfig config;

  PollsApi(this.config);

  DatabaseReference get _ref =>
      FirebaseDatabase.instance.ref('polls/${config.applicationId}');

  Stream<List<Poll>> watchPolls() {
    return _ref.onValue.map((event) => _parsePolls(event.snapshot.value));
  }

  List<Poll> _parsePolls(Object? data) {
    if (data is! Map<dynamic, dynamic>) return [];
    return data
        .entries
        .where((e) => e.value is Map<dynamic, dynamic>)
        .map((e) {
          final value = e.value as Map<dynamic, dynamic>;
          return Poll.fromSnapshot(e.key as String, value);
        })
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> createPoll({
    required String title,
    required String description,
    required List<String> optionTexts,
    required bool allowMultiple,
    required bool isActive,
    required bool isVisible,
    required bool isSecretBallot,
    required String authorId,
  }) async {
    final pollRef = _ref.push();
    final optionEntries = {
      for (var i = 0; i < optionTexts.length; i++)
        'opt$i': {'text': optionTexts[i]}
    };
    await pollRef.set({
      'title': title,
      'description': description,
      'allowMultiple': allowMultiple,
      'isActive': isActive,
      'isVisible': isVisible,
      'isSecretBallot': isSecretBallot,
      'authorId': authorId,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'options': optionEntries,
    });
  }

  Future<void> updatePoll(
    String pollId, {
    required String title,
    required String description,
    required List<PollOption> options,
    required bool allowMultiple,
    required bool isActive,
    required bool isVisible,
    required bool isSecretBallot,
  }) async {
    final optionEntries = {
      for (final opt in options) opt.id: opt.toMap()
    };
    await _ref.child(pollId).update({
      'title': title,
      'description': description,
      'allowMultiple': allowMultiple,
      'isActive': isActive,
      'isVisible': isVisible,
      'isSecretBallot': isSecretBallot,
      'options': optionEntries,
    });
  }

  Future<void> vote(
    String pollId,
    String memberId,
    List<String> selectedOptionIds,
  ) async {
    final selections = {for (final id in selectedOptionIds) id: true};
    await _ref.child(pollId).child('votes').child(memberId).set({
      'selections': selections,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deletePoll(String pollId) async {
    await _ref.child(pollId).remove();
  }
}

import '../models/poll.dart';

export '../models/poll.dart';

abstract class IPollsApi {
  Stream<List<Poll>> watchPolls();

  Future<void> createPoll({
    required String title,
    required String description,
    required List<String> optionTexts,
    required bool allowMultiple,
    required bool isActive,
    required bool isVisible,
    required bool isSecretBallot,
    required String authorId,
  });

  Future<void> updatePoll(
    String pollId, {
    required String title,
    required String description,
    required List<PollOption> options,
    required bool allowMultiple,
    required bool isActive,
    required bool isVisible,
    required bool isSecretBallot,
  });

  Future<void> vote(
    String pollId,
    String memberId,
    List<String> selectedOptionIds,
  );

  Future<void> deletePoll(String pollId);
}

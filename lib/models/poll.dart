class PollOption {
  final String id;
  final String text;

  PollOption({required this.id, required this.text});

  factory PollOption.fromMap(String id, Map<dynamic, dynamic> map) {
    return PollOption(id: id, text: map['text'] as String? ?? '');
  }

  Map<String, dynamic> toMap() => {'text': text};
}

class PollVote {
  final String memberId;
  final List<String> selectedOptionIds;
  final int updatedAt;

  PollVote({
    required this.memberId,
    required this.selectedOptionIds,
    required this.updatedAt,
  });

  factory PollVote.fromMap(String memberId, Map<dynamic, dynamic> map) {
    final sel = map['selections'];
    final ids = sel is Map<dynamic, dynamic>
        ? sel.keys.map((k) => k as String).toList()
        : <String>[];
    return PollVote(
      memberId: memberId,
      selectedOptionIds: ids,
      updatedAt: map['updatedAt'] as int? ?? 0,
    );
  }
}

class Poll {
  final String id;
  final String title;
  final String description;
  final List<PollOption> options;
  final bool allowMultiple;
  final bool isActive;
  final bool isVisible;
  final bool isSecretBallot;
  final String authorId;
  final int createdAt;
  final Map<String, PollVote> votes;

  Poll({
    required this.id,
    required this.title,
    required this.description,
    required this.options,
    required this.allowMultiple,
    required this.isActive,
    required this.isVisible,
    required this.isSecretBallot,
    required this.authorId,
    required this.createdAt,
    required this.votes,
  });

  factory Poll.fromSnapshot(String id, Map<dynamic, dynamic> map) {
    final rawOptions = map['options'];
    final options = rawOptions is Map<dynamic, dynamic>
        ? rawOptions
            .entries
            .map((e) => PollOption.fromMap(e.key as String,
                Map<dynamic, dynamic>.from(e.value as Map)))
            .toList()
        : <PollOption>[];

    final rawVotes = map['votes'];
    final votes = rawVotes is Map<dynamic, dynamic>
        ? {
            for (final e in rawVotes.entries)
              e.key as String: PollVote.fromMap(
                e.key as String,
                Map<dynamic, dynamic>.from(e.value as Map),
              )
          }
        : <String, PollVote>{};

    return Poll(
      id: id,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      allowMultiple: map['allowMultiple'] as bool? ?? false,
      isActive: map['isActive'] as bool? ?? false,
      isVisible: map['isVisible'] as bool? ?? true,
      isSecretBallot: map['isSecretBallot'] as bool? ?? false,
      authorId: map['authorId'] as String? ?? '',
      createdAt: map['createdAt'] as int? ?? 0,
      options: options,
      votes: votes,
    );
  }

  int countForOption(String optionId) =>
      votes.values.where((v) => v.selectedOptionIds.contains(optionId)).length;

  bool get showResults => !isSecretBallot || !isActive;
}

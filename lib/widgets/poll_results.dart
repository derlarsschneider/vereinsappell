import 'package:flutter/material.dart';
import '../models/poll.dart';

class PollResults extends StatelessWidget {
  final Poll poll;
  final int? totalMembers;

  const PollResults({super.key, required this.poll, this.totalMembers});

  @override
  Widget build(BuildContext context) {
    final voterCount = poll.votes.length;
    final total = totalMembers ?? voterCount;
    final maxVotes = poll.options
        .map((o) => poll.countForOption(o.id))
        .fold(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '$voterCount von $total haben abgestimmt',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        for (final option in poll.options) ...[
          Text(option.text, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 3),
          _Bar(
            count: poll.countForOption(option.id),
            maxVotes: maxVotes,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final int count;
  final int maxVotes;

  const _Bar({required this.count, required this.maxVotes});

  @override
  Widget build(BuildContext context) {
    final fraction = maxVotes == 0 ? 0.0 : count / maxVotes;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 12,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation(Colors.green[400]!),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 24,
          child: Text(
            '$count',
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

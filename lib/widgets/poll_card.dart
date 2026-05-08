import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/poll.dart';
import 'poll_results.dart';

class PollCard extends StatefulWidget {
  final Poll poll;
  final String currentMemberId;
  final bool isAdmin;
  final bool isSuperAdmin;
  final Future<void> Function(String pollId, List<String> selectedIds) onVote;
  final VoidCallback? onEdit;
  final int? totalMembers;
  final Map<String, String>? memberNames;

  const PollCard({
    super.key,
    required this.poll,
    required this.currentMemberId,
    required this.isAdmin,
    required this.isSuperAdmin,
    required this.onVote,
    this.onEdit,
    this.totalMembers,
    this.memberNames,
  });

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  late Set<String> _pendingSelection;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _pendingSelection = Set.from(
      widget.poll.votes[widget.currentMemberId]?.selectedOptionIds ?? [],
    );
  }

  @override
  void didUpdateWidget(PollCard old) {
    super.didUpdateWidget(old);
    final oldIds = old.poll.votes[widget.currentMemberId]?.selectedOptionIds;
    final newIds = widget.poll.votes[widget.currentMemberId]?.selectedOptionIds;
    if (old.poll.id != widget.poll.id || !listEquals(oldIds, newIds)) {
      _pendingSelection = Set.from(newIds ?? []);
    }
  }

  void _toggleOption(String optionId) {
    if (!widget.poll.isActive || _submitting) return;
    setState(() {
      if (widget.poll.allowMultiple) {
        if (_pendingSelection.contains(optionId)) {
          _pendingSelection.remove(optionId);
        } else {
          _pendingSelection.add(optionId);
        }
      } else {
        _pendingSelection = {optionId};
      }
    });
    _submit();
  }

  Future<void> _submit() async {
    if (_pendingSelection.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onVote(widget.poll.id, _pendingSelection.toList());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Color get _borderColor {
    if (!widget.poll.isActive) return Colors.grey[300]!;
    if (widget.poll.isSecretBallot) return Colors.blue[300]!;
    return Colors.green[400]!;
  }

  @override
  Widget build(BuildContext context) {
    final poll = widget.poll;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: _borderColor, width: poll.isActive ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            if (poll.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(poll.description,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            if (poll.isActive) ...[
              const SizedBox(height: 12),
              _buildOptions(),
              if (_submitting)
                const LinearProgressIndicator(),
            ],
            if (poll.showResults) ...[
              const Divider(height: 20),
              PollResults(poll: poll, totalMembers: widget.totalMembers),
              if (!poll.isSecretBallot && poll.votes.isNotEmpty)
                _buildVoterListButton(context),
            ],
            if (poll.isSecretBallot && poll.isActive) ...[
              const SizedBox(height: 8),
              const Text(
                'Ergebnisse erst nach Ende sichtbar',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            widget.poll.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),
        if (widget.isAdmin && widget.onEdit != null)
          GestureDetector(
            onTap: widget.onEdit,
            child: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
          ),
        const SizedBox(width: 4),
        if (widget.poll.isSecretBallot) ...[
          const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
        ],
        Text(
          widget.poll.isActive ? '● Aktiv' : '⏹ Beendet',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: widget.poll.isActive ? Colors.green : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildOptions() {
    return Column(
      children: [
        for (final option in widget.poll.options)
          _OptionTile(
            option: option,
            selected: _pendingSelection.contains(option.id),
            onTap: () => _toggleOption(option.id),
            accentColor:
                widget.poll.isSecretBallot ? Colors.blue : Colors.green,
          ),
      ],
    );
  }

  Widget _buildVoterListButton(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.people_outline, size: 16),
        label: const Text('Wer hat wie abgestimmt?'),
        style: TextButton.styleFrom(
          foregroundColor: Colors.grey[600],
          textStyle: const TextStyle(fontSize: 12),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        onPressed: () => _showVoterList(context),
      ),
    );
  }

  void _showVoterList(BuildContext context) {
    final poll = widget.poll;
    final names = widget.memberNames ?? {};

    final byOption = <String, List<String>>{};
    for (final option in poll.options) {
      byOption[option.id] = [];
    }
    for (final entry in poll.votes.entries) {
      final memberId = entry.key;
      final displayName = names[memberId] ?? memberId;
      for (final optId in entry.value.selectedOptionIds) {
        byOption[optId]?.add(displayName);
      }
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shrinkWrap: true,
        children: [
          Text(
            poll.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 12),
          for (final option in poll.options) ...[
            Text(
              option.text,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 4),
            if ((byOption[option.id] ?? []).isEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 8),
                child: Text('–', style: TextStyle(color: Colors.grey)),
              )
            else
              for (final name in byOption[option.id]!)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text(name, style: const TextStyle(fontSize: 13)),
                ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final PollOption option;
  final bool selected;
  final VoidCallback onTap;
  final Color accentColor;

  const _OptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? accentColor : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
          color: selected ? accentColor.withAlpha(25) : null,
        ),
        child: Row(
          children: [
            if (selected) Icon(Icons.check, size: 16, color: accentColor),
            if (selected) const SizedBox(width: 6),
            Text(option.text, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

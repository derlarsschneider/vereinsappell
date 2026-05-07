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

  const PollCard({
    super.key,
    required this.poll,
    required this.currentMemberId,
    required this.isAdmin,
    required this.isSuperAdmin,
    required this.onVote,
    this.onEdit,
    this.totalMembers,
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
    if (old.poll.id != widget.poll.id) {
      _pendingSelection = Set.from(
        widget.poll.votes[widget.currentMemberId]?.selectedOptionIds ?? [],
      );
    }
  }

  void _toggleOption(String optionId) {
    if (!widget.poll.isActive) return;
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

  bool get _hasVoted => widget.poll.votes.containsKey(widget.currentMemberId);

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
              const SizedBox(height: 8),
              _buildSubmitButton(),
            ],
            if (poll.showResults && !poll.isActive) ...[
              const Divider(height: 20),
              PollResults(poll: poll, totalMembers: widget.totalMembers),
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
        Text(
          widget.poll.isActive ? 'Aktiv' : 'Beendet',
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

  Widget _buildSubmitButton() {
    final canSubmit = _pendingSelection.isNotEmpty && !_submitting;
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton(
        onPressed: canSubmit ? _submit : null,
        child: _submitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(_hasVoted ? 'Stimme ändern' : 'Stimme abgeben'),
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

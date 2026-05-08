import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/members_api.dart';
import '../api/polls_api.dart';
import '../config_loader.dart';
import '../widgets/poll_card.dart';
import '../widgets/poll_form_dialog.dart';
import 'default_screen.dart';

class AbstimmungenScreen extends DefaultScreen {
  final IPollsApi? pollsApi;

  const AbstimmungenScreen({super.key, required super.config, this.pollsApi})
      : super(title: 'Abstimmungen');

  @override
  DefaultScreenState createState() => _AbstimmungenScreenState();
}

class _AbstimmungenScreenState extends DefaultScreenState<AbstimmungenScreen> {
  late final IPollsApi _api;
  late final StreamSubscription<List<Poll>> _sub;
  List<Poll>? _polls;
  Map<String, String> _memberNames = {};

  @override
  void initState() {
    super.initState();
    _api = widget.pollsApi ?? PollsApi(widget.config);
    _sub = _api.watchPolls().listen(
      (polls) {
        if (mounted) setState(() => _polls = polls);
      },
      onError: (e) {
        if (mounted) showError('Firebase-Fehler: $e');
      },
    );
    _loadMemberNames();
  }

  Future<void> _loadMemberNames() async {
    try {
      final members = await MembersApi(widget.config).fetchMembers();
      final map = <String, String>{};
      for (final m in members) {
        final id = m['memberId'] as String?;
        final name = m['name'] as String?;
        if (id != null && name != null) map[id] = name;
      }
      if (mounted) setState(() => _memberNames = map);
    } catch (_) {
      // member names are best-effort; silently ignore errors
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _onVote(String pollId, List<String> selectedIds) async {
    try {
      await _api.vote(pollId, widget.config.memberId, selectedIds);
    } catch (e) {
      if (mounted) showError('Fehler beim Abstimmen: $e');
    }
  }

  void _openCreate(BuildContext context) {
    showPollFormDialog(
      context,
      onSave: (data) async {
        try {
          await _api.createPoll(
            title: data.title,
            description: data.description,
            optionTexts: data.optionTexts,
            allowMultiple: data.allowMultiple,
            isActive: data.isActive,
            isVisible: data.isVisible,
            isSecretBallot: data.isSecretBallot,
            authorId: widget.config.memberId,
          );
        } catch (e) {
          if (mounted) showError('Fehler beim Erstellen: $e');
        }
      },
    );
  }

  void _openEdit(BuildContext context, Poll poll, bool isSuperAdmin) {
    showPollFormDialog(
      context,
      poll: poll,
      onSave: (data) async {
        final updatedOptions = data.optionTexts.asMap().entries.map((e) {
          final existingId = e.key < poll.options.length
              ? poll.options[e.key].id
              : 'opt${poll.options.length + e.key}';
          return PollOption(id: existingId, text: e.value);
        }).toList();
        try {
          await _api.updatePoll(
            poll.id,
            title: data.title,
            description: data.description,
            options: updatedOptions,
            allowMultiple: data.allowMultiple,
            isActive: data.isActive,
            isVisible: data.isVisible,
            isSecretBallot: data.isSecretBallot,
          );
        } catch (e) {
          if (mounted) showError('Fehler beim Speichern: $e');
        }
      },
      onDelete: isSuperAdmin
          ? () async {
              Navigator.pop(context);
              try {
                await _api.deletePoll(poll.id);
              } catch (e) {
                if (mounted) showError('Fehler beim Löschen: $e');
              }
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);
    final polls = _polls;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Abstimmungen'),
        actions: [
          if (member.isAdmin || member.isSuperAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _openCreate(context),
            ),
        ],
      ),
      body: polls == null
          ? const Center(child: CircularProgressIndicator())
          : _buildList(context, polls, member),
    );
  }

  Widget _buildList(BuildContext context, List<Poll> polls, Member member) {
    final visible = (member.isAdmin || member.isSuperAdmin)
        ? polls
        : polls.where((p) => p.isVisible).toList();

    if (visible.isEmpty) {
      return const Center(child: Text('Keine Abstimmungen vorhanden'));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: visible.length,
      itemBuilder: (_, i) {
        final poll = visible[i];
        return PollCard(
          poll: poll,
          currentMemberId: widget.config.memberId,
          isAdmin: member.isAdmin || member.isSuperAdmin,
          isSuperAdmin: member.isSuperAdmin,
          onVote: _onVote,
          onEdit: (member.isAdmin || member.isSuperAdmin)
              ? () => _openEdit(context, poll, member.isSuperAdmin)
              : null,
          memberNames: _memberNames,
        );
      },
    );
  }
}

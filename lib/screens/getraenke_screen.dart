import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/getraenke_api.dart';
import '../api/members_api.dart';
import '../config_loader.dart';
import '../widgets/bierdeckel_card.dart';
import 'default_screen.dart';

export '../widgets/bierdeckel_card.dart' show BierdeckelCard, DrinkDef, kDrinks;

// ── GetraenkeScreen ───────────────────────────────────────────────────────────

class GetraenkeScreen extends DefaultScreen {
  const GetraenkeScreen({super.key, required super.config})
      : super(title: 'Getränke');

  @override
  DefaultScreenState createState() => _GetraenkeScreenState();
}

class _GetraenkeScreenState extends DefaultScreenState<GetraenkeScreen> {
  late final GetraenkeApi _api;
  late final MembersApi _membersApi;
  late final StreamSubscription<List<TallyEntry>> _sub;
  List<TallyEntry> _entries = [];
  Map<String, String> _memberNames = {};

  @override
  void initState() {
    super.initState();
    _api = GetraenkeApi(widget.config);
    _membersApi = MembersApi(widget.config);
    _sub = _api.watchTallies().listen(
      (entries) { if (mounted) setState(() => _entries = entries); },
      onError: (e) { if (mounted) showError('Firebase-Fehler: $e'); },
    );
    _fetchMembers();
  }

  Future<void> _fetchMembers() async {
    try {
      final members = await _membersApi.fetchMembers();
      if (mounted) {
        setState(() {
          _memberNames = {
            for (final m in members)
              (m['memberId'] as String): (m['name'] as String? ?? ''),
          };
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _deleteMark(String drinkId, String entryId) async {
    try {
      await _api.deleteMark(drinkId, entryId);
    } catch (e) {
      if (mounted) showError('Fehler beim Löschen: $e');
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alle Striche löschen?'),
        content: const Text('Alle Striche und Flaschen für alle Getränke werden gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _api.clearAll();
      } catch (e) {
        if (mounted) showError('Fehler beim Löschen: $e');
      }
    }
  }

  List<_MemberDrinkSummary> _buildMemberSummaries() {
    final byMember = <String, Map<String, int>>{};
    for (final e in _entries) {
      byMember.putIfAbsent(e.memberId, () => {});
      byMember[e.memberId]![e.drinkId] = (byMember[e.memberId]![e.drinkId] ?? 0) + 1;
    }
    final summaries = byMember.entries.map((entry) {
      final name = _memberNames[entry.key] ?? entry.key;
      final drinks = entry.value.entries
          .map((d) {
            final drinkName = kDrinks.firstWhere((k) => k.id == d.key, orElse: () => DrinkDef(id: d.key, name: d.key, headerEmoji: '', buttonEmoji: '', hasBottle: false)).name;
            return '${d.value}x $drinkName';
          })
          .join(', ');
      return _MemberDrinkSummary(name: name, drinks: drinks);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return summaries;
  }

  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);
    final summaries = member.isSaftschubse ? _buildMemberSummaries() : <_MemberDrinkSummary>[];

    return Scaffold(
      appBar: AppBar(title: const Text('🍻 Getränke')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          ...kDrinks.map((drink) {
            final drinkEntries = _entries.where((e) => e.drinkId == drink.id).toList();
            return Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 2),
              child: BierdeckelCard(
                drink: drink,
                entries: drinkEntries,
                myMemberId: widget.config.memberId,
                onStrich: () => _api.addMark(drink.id, 'strich').catchError(
                  (e) { if (mounted) showError('Fehler: $e'); },
                ),
                onFlasche: drink.hasBottle
                    ? () => _api.addMark(drink.id, 'flasche').catchError(
                          (e) { if (mounted) showError('Fehler: $e'); },
                        )
                    : null,
                onDeleteMark: (entryId) => _deleteMark(drink.id, entryId),
              ),
            );
          }),
          if (member.isSaftschubse) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _confirmReset,
              icon: const Icon(Icons.delete_sweep, color: Colors.white),
              label: const Text('Alle Striche löschen', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
          if (member.isSaftschubse && summaries.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Wer hat was?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF4A2C00))),
            ),
            ...summaries.map((s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(s.drinks, style: const TextStyle(color: Color(0xFF7A4F00))),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }
}

class _MemberDrinkSummary {
  final String name;
  final String drinks;
  const _MemberDrinkSummary({required this.name, required this.drinks});
}

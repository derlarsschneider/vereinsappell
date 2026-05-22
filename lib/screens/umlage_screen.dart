import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/umlagen_api.dart';
import '../api/umlagen_api_interface.dart';
import '../config_loader.dart';
import '../models/umlage.dart';
import 'default_screen.dart';

class UmlagenScreen extends DefaultScreen {
  final IUmlagenApi? api;

  const UmlagenScreen({super.key, required super.config, this.api})
      : super(title: 'Umlagen');

  @override
  DefaultScreenState<UmlagenScreen> createState() => _UmlagenScreenState();
}

class _UmlagenScreenState extends DefaultScreenState<UmlagenScreen>
    with SingleTickerProviderStateMixin {
  late final IUmlagenApi _api;
  late final TabController _tabController;

  List<HistoryEntry> _history = [];
  bool _historyLoading = false;
  bool _hasMoreHistory = true;
  int? _lastClosedAt;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? UmlagenApi(widget.config);
    final isCollector = widget.config.member.isUmlageneinsammler;
    _tabController = TabController(
      length: isCollector ? 3 : 2,
      vsync: this,
      initialIndex: 0,
    );
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory({bool loadMore = false}) async {
    if (_historyLoading) return;
    setState(() => _historyLoading = true);
    try {
      final entries = await _api.fetchHistory(
        limit: 20,
        beforeClosedAt: loadMore ? _lastClosedAt : null,
      );
      setState(() {
        if (loadMore) {
          _history.addAll(entries);
        } else {
          _history = entries;
        }
        _hasMoreHistory = entries.length == 20;
        if (entries.isNotEmpty) _lastClosedAt = entries.last.closedAt;
      });
    } catch (e) {
      showError('$e');
    } finally {
      setState(() => _historyLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);
    final isCollector = member.isUmlageneinsammler;

    final tabs = [
      if (isCollector) const Tab(text: 'Meine Sammlung'),
      const Tab(text: 'Alle aktiven'),
      const Tab(text: 'Abgeschlossen'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Umlagen'),
        bottom: TabBar(controller: _tabController, tabs: tabs),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          if (isCollector) _MeineSammlungTab(api: _api, config: widget.config),
          _AlleAktivenTab(api: _api, currentMemberId: widget.config.memberId),
          _AbgeschlossenTab(
            history: _history,
            loading: _historyLoading,
            hasMore: _hasMoreHistory,
            currentMemberId: widget.config.memberId,
            onLoadMore: () => _loadHistory(loadMore: true),
          ),
        ],
      ),
    );
  }
}

// -- Tab 1: Meine Sammlung ---------------------------------------------------

class _MeineSammlungTab extends StatefulWidget {
  final IUmlagenApi api;
  final AppConfig config;

  const _MeineSammlungTab({required this.api, required this.config});

  @override
  State<_MeineSammlungTab> createState() => _MeineSammlungTabState();
}

class _MeineSammlungTabState extends State<_MeineSammlungTab> {
  int _selectedAmount = 20;
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _startSession() async {
    final name = _nameController.text.trim();
    try {
      await widget.api.startSession(
        collectorId: widget.config.memberId,
        amount: _selectedAmount,
        name: name,
        memberIds: [],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmClose(UmlageSession session) async {
    final unpaid = session.participants.values.where((s) => s == 'pending').length;
    final confirmed = unpaid == 0 ||
        (await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Umlage abschließen?'),
            content: Text('$unpaid Mitglied${unpaid == 1 ? '' : 'er'} noch nicht bezahlt.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Trotzdem abschließen'),
              ),
            ],
          ),
        ) == true);
    if (confirmed) {
      await widget.api.closeSession(
        collectorId: widget.config.memberId,
        session: session,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UmlageSession?>(
      stream: widget.api.watchActiveSession(widget.config.memberId),
      builder: (context, snapshot) {
        final session = snapshot.data;
        if (session == null) {
          return _buildStartView();
        }
        return _buildCollectView(session);
      },
    );
  }

  Widget _buildStartView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Betrag wählen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          _BanknotePicker(
            selected: _selectedAmount,
            onChanged: (v) => setState(() => _selectedAmount = v),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name (optional)',
              hintText: 'z.B. Vereinsfest Mai',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _startSession,
            icon: const Icon(Icons.play_arrow),
            label: Text('Umlage starten (€$_selectedAmount)'),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectView(UmlageSession session) {
    final paidFraction = session.activeCount == 0
        ? 0.0
        : session.paidCount / session.activeCount;
    final allPaid = session.activeCount > 0 && session.paidCount == session.activeCount;
    final bgColor = Color.lerp(Colors.red[200], Colors.green[200], paidFraction)!;
    final memberIds = session.participants.entries
        .where((e) => e.value != 'excluded')
        .map((e) => e.key)
        .toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: bgColor,
        border: allPaid ? Border.all(color: Colors.green, width: 4) : null,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _BanknotePicker(
                  selected: session.amount,
                  onChanged: session.paidCount > 0 ? null : (_) {},
                ),
                const SizedBox(height: 8),
                Text(session.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: paidFraction,
                  backgroundColor: Colors.white38,
                  color: Colors.green,
                ),
                const SizedBox(height: 4),
                Text(
                  '${session.paidCount} von ${session.activeCount} bezahlt · €${session.totalCollected} gesammelt',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: memberIds.length,
              itemBuilder: (context, index) {
                final memberId = memberIds[index];
                final status = session.participants[memberId] ?? 'pending';
                return _MemberListTile(
                  memberId: memberId,
                  memberName: memberId,
                  status: status,
                  onTap: () => widget.api.updateParticipant(
                    collectorId: widget.config.memberId,
                    memberId: memberId,
                    status: status == 'paid' ? 'pending' : 'paid',
                  ),
                  onSwipe: () => widget.api.updateParticipant(
                    collectorId: widget.config.memberId,
                    memberId: memberId,
                    status: 'excluded',
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _confirmClose(session),
                icon: const Icon(Icons.check),
                label: const Text('Umlage abschließen'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Tab 2: Alle aktiven -----------------------------------------------------

class _AlleAktivenTab extends StatelessWidget {
  final IUmlagenApi api;
  final String currentMemberId;

  const _AlleAktivenTab({required this.api, required this.currentMemberId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UmlageSession>>(
      stream: api.watchAllActive(),
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const [];
        if (sessions.isEmpty) {
          return const Center(child: Text('Aktuell läuft keine Umlage.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: sessions.length,
          itemBuilder: (context, i) {
            final s = sessions[i];
            final myStatus = s.participants[currentMemberId];
            final paidFraction = s.activeCount == 0 ? 0.0 : s.paidCount / s.activeCount;
            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            s.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                        Text(
                          '€${s.amount}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: paidFraction,
                      backgroundColor: Colors.grey[200],
                      color: Colors.green,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      myStatus == 'paid'
                          ? 'Du hast bezahlt · ${s.paidCount}/${s.activeCount} gesamt'
                          : 'Du hast noch nicht bezahlt · ${s.paidCount}/${s.activeCount} gesamt',
                      style: TextStyle(
                        fontSize: 11,
                        color: myStatus == 'paid' ? Colors.green[700] : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// -- Tab 3: Abgeschlossen ----------------------------------------------------

class _AbgeschlossenTab extends StatelessWidget {
  final List<HistoryEntry> history;
  final bool loading;
  final bool hasMore;
  final String currentMemberId;
  final VoidCallback onLoadMore;

  const _AbgeschlossenTab({
    required this.history,
    required this.loading,
    required this.hasMore,
    required this.currentMemberId,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && history.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: history.isEmpty ? 1 : history.length + (hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (history.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Noch keine abgeschlossenen Umlagen.'),
            ),
          );
        }
        if (i == history.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: loading
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: onLoadMore,
                      child: const Text('Mehr anzeigen'),
                    ),
            ),
          );
        }
        final entry = history[i];
        final paid = entry.memberPaid(currentMemberId);
        final dt = DateTime.fromMillisecondsSinceEpoch(entry.closedAt);
        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: Icon(
              Icons.circle,
              color: paid ? Colors.green : Colors.red,
              size: 12,
            ),
            title: Text(entry.displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Text(
              '${DateFormat('dd.MM.yyyy').format(dt)} · ${entry.paidCount}/${entry.participants.length} Mitglieder',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Text(
              '€${entry.totalPaid}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        );
      },
    );
  }
}

// -- Shared Widgets ----------------------------------------------------------

class _BanknotePicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int>? onChanged;

  const _BanknotePicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const amounts = [5, 10, 20, 50];
    const colors = {
      5: Color(0xFF43a047),
      10: Color(0xFFe53935),
      20: Color(0xFF1e88e5),
      50: Color(0xFFfb8c00),
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: amounts.map((amount) {
        final isSelected = amount == selected;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: onChanged == null ? null : () => onChanged!(amount),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 64,
              height: 36,
              decoration: BoxDecoration(
                color: colors[amount],
                borderRadius: BorderRadius.circular(6),
                border: isSelected ? Border.all(color: Colors.white, width: 2.5) : null,
                boxShadow: isSelected
                    ? [const BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))]
                    : [const BoxShadow(color: Colors.black12, blurRadius: 2)],
              ),
              child: Center(
                child: Text(
                  '€$amount',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MemberListTile extends StatelessWidget {
  final String memberId;
  final String memberName;
  final String status;
  final VoidCallback onTap;
  final VoidCallback onSwipe;

  const _MemberListTile({
    required this.memberId,
    required this.memberName,
    required this.status,
    required this.onTap,
    required this.onSwipe,
  });

  @override
  Widget build(BuildContext context) {
    final isPaid = status == 'paid';
    return Dismissible(
      key: Key(memberId),
      background: Container(
        color: Colors.red[100],
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.cancel, color: Colors.red),
      ),
      secondaryBackground: Container(
        color: Colors.red[100],
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.cancel, color: Colors.red),
      ),
      onDismissed: (_) => onSwipe(),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isPaid ? Colors.green[50] : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: isPaid ? Border.all(color: Colors.green, width: 1.5) : null,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)],
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isPaid ? Colors.green[200] : Colors.blue[100],
              child: Text(
                memberName.isNotEmpty ? memberName[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isPaid ? Colors.green[900] : Colors.blue[900],
                ),
              ),
            ),
            title: Text(memberName, style: const TextStyle(fontSize: 13)),
            trailing: Icon(
              isPaid ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isPaid ? Colors.green : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}

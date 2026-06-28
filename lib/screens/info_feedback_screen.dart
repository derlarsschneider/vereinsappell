// lib/screens/info_feedback_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feedback_api.dart';
import '../api/legal_api.dart';
import '../api/news_api.dart';
import '../config_loader.dart';
import 'default_screen.dart';

class InfoFeedbackScreen extends DefaultScreen {
  const InfoFeedbackScreen({super.key, required super.config})
      : super(title: 'Info & Feedback');

  @override
  DefaultScreenState createState() => _InfoFeedbackScreenState();
}

class _InfoFeedbackScreenState extends DefaultScreenState<InfoFeedbackScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ℹ️ Info & Feedback'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '📰 News'),
              Tab(text: '💬 Feedback'),
              Tab(text: '📋 Rechtliches'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _NewsTab(config: widget.config),
            _FeedbackTab(config: widget.config),
            _LegalTab(config: widget.config),
          ],
        ),
      ),
    );
  }
}

// ─── Tab 3: Rechtliches ──────────────────────────────────────────────────────

class _LegalTab extends StatefulWidget {
  final AppConfig config;
  const _LegalTab({required this.config});

  @override
  State<_LegalTab> createState() => _LegalTabState();
}

class _LegalTabState extends State<_LegalTab> {
  bool _loading = true;
  String _datenschutz = '';
  String _impressum = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final texts = await LegalApi(widget.config).getLegal();
      if (!mounted) return;
      setState(() {
        _datenschutz = texts['datenschutz'] ?? '';
        _impressum = texts['impressum'] ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _edit(BuildContext context, Member member) async {
    final dsController = TextEditingController(text: _datenschutz);
    final imController = TextEditingController(text: _impressum);
    final messenger = ScaffoldMessenger.of(context);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechtstexte bearbeiten'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Datenschutzerklärung',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                TextField(
                  controller: dsController,
                  maxLines: 6,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                const Text('Impressum',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                TextField(
                  controller: imController,
                  maxLines: 6,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;
    try {
      await LegalApi(widget.config).putLegal(
        datenschutz: dsController.text,
        impressum: imController.text,
      );
      if (!mounted) return;
      setState(() {
        _datenschutz = dsController.text;
        _impressum = imController.text;
      });
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (member.isSuperAdmin)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: () => _edit(context, member),
              icon: const Icon(Icons.edit),
              label: const Text('Texte bearbeiten'),
            ),
          ),
        _ExpandableSection(
          title: '🔒 Datenschutzerklärung',
          content: _datenschutz.isEmpty
              ? 'Noch kein Text hinterlegt.'
              : _datenschutz,
        ),
        const SizedBox(height: 8),
        _ExpandableSection(
          title: '📄 Impressum',
          content: _impressum.isEmpty ? 'Noch kein Text hinterlegt.' : _impressum,
        ),
      ],
    );
  }
}

class _ExpandableSection extends StatefulWidget {
  final String title;
  final String content;
  const _ExpandableSection({required this.title, required this.content});

  @override
  State<_ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<_ExpandableSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(widget.title,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(widget.content,
                  style: const TextStyle(fontSize: 13, height: 1.5)),
            ),
        ],
      ),
    );
  }
}

// ─── Tab 1: Neuigkeiten ───────────────────────────────────────────────────────

class _NewsTab extends StatefulWidget {
  final AppConfig config;
  const _NewsTab({required this.config});

  @override
  State<_NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<_NewsTab> {
  bool _loading = true;
  List<NewsItem> _items = [];
  // newsId -> true if this member already answered
  final Map<String, bool> _answered = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await NewsApi(widget.config).getNews();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _delete(String newsId) async {
    try {
      await NewsApi(widget.config).deleteNews(newsId);
      if (!mounted) return;
      setState(() => _items.removeWhere((i) => i.newsId == newsId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _submitAnswer(NewsItem item, String answer) async {
    try {
      await FeedbackApi(widget.config).postFeedback(
        message: answer,
        newsId: item.newsId,
        newsTitle: item.title,
        newsQuestion: item.question,
      );
      if (!mounted) return;
      setState(() => _answered[item.newsId] = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final questionCtrl = TextEditingController();
    final optionCtrl = TextEditingController();
    String? expiresAt;
    String? selectedExpiryLabel; // 'week', 'month', 'date', null (unlimited)
    bool useOptions = false;
    List<String> options = [];

    try {
      await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Neuigkeit verfassen'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Titel', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bodyCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Text', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  const Text('Sichtbar bis (optional)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      _ExpiryChip(
                        label: '1 Woche',
                        selected: selectedExpiryLabel == 'week',
                        onTap: () {
                          final d = DateTime.now().add(const Duration(days: 7));
                          setDlgState(() {
                            expiresAt = d.toIso8601String();
                            selectedExpiryLabel = 'week';
                          });
                        },
                      ),
                      _ExpiryChip(
                        label: '1 Monat',
                        selected: selectedExpiryLabel == 'month',
                        onTap: () {
                          final d = DateTime.now().add(const Duration(days: 30));
                          setDlgState(() {
                            expiresAt = d.toIso8601String();
                            selectedExpiryLabel = 'month';
                          });
                        },
                      ),
                      _ExpiryChip(
                        label: '📅 Datum',
                        selected: selectedExpiryLabel == 'date',
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now().add(const Duration(days: 7)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setDlgState(() {
                              expiresAt = picked.toIso8601String();
                              selectedExpiryLabel = 'date';
                            });
                          }
                        },
                      ),
                      _ExpiryChip(
                        label: '∞ Unbegrenzt',
                        selected: selectedExpiryLabel == null,
                        onTap: () => setDlgState(() {
                          expiresAt = null;
                          selectedExpiryLabel = null;
                        }),
                      ),
                    ],
                  ),
                  if (expiresAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Bis: ${expiresAt!.substring(0, 10)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text('Frage (optional)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: questionCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Fragetext', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Antworttyp: '),
                      ChoiceChip(
                        label: const Text('Freitext'),
                        selected: !useOptions,
                        onSelected: (_) => setDlgState(() => useOptions = false),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Auswahloptionen'),
                        selected: useOptions,
                        onSelected: (_) => setDlgState(() => useOptions = true),
                      ),
                    ],
                  ),
                  if (useOptions) ...[
                    const SizedBox(height: 8),
                    ...options.asMap().entries.map((e) => ListTile(
                          dense: true,
                          title: Text(e.value),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () =>
                                setDlgState(() => options.removeAt(e.key)),
                          ),
                        )),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: optionCtrl,
                            decoration: const InputDecoration(
                                hintText: 'Option hinzufügen',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            if (optionCtrl.text.trim().isNotEmpty) {
                              setDlgState(() {
                                options.add(optionCtrl.text.trim());
                                optionCtrl.clear();
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                try {
                  await NewsApi(widget.config).createNews(
                    title: titleCtrl.text.trim(),
                    body: bodyCtrl.text.trim(),
                    expiresAt: expiresAt,
                    question: questionCtrl.text.trim().isEmpty
                        ? null
                        : questionCtrl.text.trim(),
                    questionOptions:
                        useOptions && options.isNotEmpty ? options : null,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                        content: Text('Fehler: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Veröffentlichen'),
            ),
          ],
        ),
      ),
    );
    } finally {
      titleCtrl.dispose();
      bodyCtrl.dispose();
      questionCtrl.dispose();
      optionCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (member.isSuperAdmin)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: () => _showCreateDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Neuigkeit verfassen'),
            ),
          ),
        if (_items.isEmpty)
          const Center(child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Keine Neuigkeiten'),
          )),
        ..._items.map((item) => _NewsCard(
              item: item,
              isSuperAdmin: member.isSuperAdmin,
              answered: _answered[item.newsId] ?? false,
              onDelete: () => _delete(item.newsId),
              onAnswer: (answer) => _submitAnswer(item, answer),
            )),
      ],
    );
  }
}

class _ExpiryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ExpiryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ActionChip(
        label: Text(label),
        backgroundColor: selected ? Theme.of(context).colorScheme.primary : null,
        labelStyle: TextStyle(color: selected ? Colors.white : null),
        onPressed: onTap,
      );
}

class _NewsCard extends StatefulWidget {
  final NewsItem item;
  final bool isSuperAdmin;
  final bool answered;
  final VoidCallback onDelete;
  final void Function(String answer) onAnswer;

  const _NewsCard({
    required this.item,
    required this.isSuperAdmin,
    required this.answered,
    required this.onDelete,
    required this.onAnswer,
  });

  @override
  State<_NewsCard> createState() => _NewsCardState();
}

class _NewsCardState extends State<_NewsCard> {
  final _answerCtrl = TextEditingController();
  String? _selectedOption;
  bool _submitted = false;
  String _submittedAnswer = '';

  bool get _hasQuestion => widget.item.question != null;
  bool get _hasOptions => widget.item.questionOptions?.isNotEmpty == true;
  bool get _alreadyAnswered => widget.answered || _submitted;

  void _submit() {
    final answer = _hasOptions ? _selectedOption : _answerCtrl.text.trim();
    if (answer == null || answer.isEmpty) return;
    setState(() {
      _submittedAnswer = answer;
      _submitted = true;
    });
    widget.onAnswer(answer);
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = widget.item.date.length >= 10
        ? widget.item.date.substring(0, 10)
        : widget.item.date;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: _hasQuestion && !_alreadyAnswered
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item.title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(widget.item.body,
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
            if (_hasQuestion) ...[
              const SizedBox(height: 10),
              if (_alreadyAnswered)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          size: 16, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        'Deine Antwort gesendet: $_submittedAnswer',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '❓ ${widget.item.question}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.purple),
                      ),
                      const SizedBox(height: 8),
                      if (_hasOptions)
                        ...widget.item.questionOptions!.map((opt) => GestureDetector(
                              onTap: () => setState(() => _selectedOption = opt),
                              child: Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: _selectedOption == opt
                                      ? Colors.purple.shade100
                                      : Colors.white,
                                  border: Border.all(
                                    color: _selectedOption == opt
                                        ? Colors.purple
                                        : Colors.purple.shade200,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(opt,
                                    style: TextStyle(
                                      fontWeight: _selectedOption == opt
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    )),
                              ),
                            ))
                      else
                        TextField(
                          controller: _answerCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Deine Antwort...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submit,
                          child: const Text('Antwort senden'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(dateStr,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                if (widget.isSuperAdmin)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Löschen', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab 2: Feedback ─────────────────────────────────────────────────────────

class _FeedbackTab extends StatefulWidget {
  final AppConfig config;
  const _FeedbackTab({required this.config});

  @override
  State<_FeedbackTab> createState() => _FeedbackTabState();
}

class _FeedbackTabState extends State<_FeedbackTab> {
  bool _loading = true;
  List<FeedbackItem> _items = [];
  final _messageCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await FeedbackApi(widget.config).getFeedback();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _send() async {
    final msg = _messageCtrl.text.trim();
    if (msg.isEmpty) return;
    setState(() => _sending = true);
    try {
      await FeedbackApi(widget.config).postFeedback(message: msg);
      if (!mounted) return;
      _messageCtrl.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reply(FeedbackItem item, String replyText) async {
    try {
      await FeedbackApi(widget.config).postReply(
        feedbackId: item.feedbackId,
        reply: replyText,
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (member.isSuperAdmin) return _buildSuperAdminView(context);
    return _buildMemberView(context);
  }

  Widget _buildMemberView(BuildContext context) {
    final own = _items
        .where((i) => i.memberId == widget.config.memberId)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          controller: _messageCtrl,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Deine Nachricht an den Admin...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send),
            label: const Text('📤 Feedback senden'),
          ),
        ),
        if (own.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Deine bisherigen Nachrichten',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...own.map((item) => _MemberFeedbackCard(item: item)),
        ],
      ],
    );
  }

  Widget _buildSuperAdminView(BuildContext context) {
    final open = _items.where((i) => !i.hasReply).toList();
    final answered = _items.where((i) => i.hasReply).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            _StatusChip(label: '${open.length} offen', color: Colors.red),
            const SizedBox(width: 8),
            _StatusChip(label: '${answered.length} beantwortet', color: Colors.green),
          ],
        ),
        const SizedBox(height: 12),
        ...open.map((item) => _AdminFeedbackCard(
              item: item,
              isOpen: true,
              onReply: (text) => _reply(item, text),
            )),
        ...answered.map((item) => _AdminFeedbackCard(
              item: item,
              isOpen: false,
              onReply: (text) => _reply(item, text),
            )),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text('● $label',
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.bold)),
      );
}

class _MemberFeedbackCard extends StatelessWidget {
  final FeedbackItem item;
  const _MemberFeedbackCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final dateStr = item.date.length >= 10 ? item.date.substring(0, 10) : item.date;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: item.isFromNews ? Colors.purple.shade50 : Colors.indigo.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.isFromNews)
                  Text(
                    '❓ Antwort auf: "${item.newsQuestion ?? item.newsTitle}"',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.purple.shade700,
                        fontWeight: FontWeight.w500),
                  ),
                if (item.isFromNews) const SizedBox(height: 4),
                Text('Du · $dateStr',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(item.message),
              ],
            ),
          ),
          if (item.hasReply)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '↩️ Antwort vom Admin · ${item.repliedAt?.substring(0, 10) ?? ''}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(item.reply ?? ''),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminFeedbackCard extends StatefulWidget {
  final FeedbackItem item;
  final bool isOpen;
  final void Function(String reply) onReply;

  const _AdminFeedbackCard({
    required this.item,
    required this.isOpen,
    required this.onReply,
  });

  @override
  State<_AdminFeedbackCard> createState() => _AdminFeedbackCardState();
}

class _AdminFeedbackCardState extends State<_AdminFeedbackCard> {
  final _replyCtrl = TextEditingController();

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final dateStr = item.date.length >= 10 ? item.date.substring(0, 10) : item.date;
    final borderColor = widget.isOpen ? Colors.red.shade200 : Colors.green.shade200;
    final bgColor = widget.isOpen ? const Color(0xFFFFF8F8) : const Color(0xFFF9FFF9);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      color: bgColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.isOpen ? "⚠️" : "✅"} ${item.memberName} · ${item.applicationId} · $dateStr',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: widget.isOpen ? Colors.red.shade800 : Colors.green.shade800,
                  ),
                ),
                if (item.isFromNews) ...[
                  const SizedBox(height: 2),
                  Text(
                    '❓ "${item.newsQuestion ?? item.newsTitle}"',
                    style: TextStyle(
                        fontSize: 11, color: Colors.purple.shade700),
                  ),
                ],
                const SizedBox(height: 4),
                Text(item.message),
              ],
            ),
          ),
          if (item.hasReply)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '↩️ Deine Antwort · ${item.repliedAt?.substring(0, 10) ?? ''}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(item.reply ?? ''),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: [
                  TextField(
                    controller: _replyCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Antwort schreiben...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_replyCtrl.text.trim().isEmpty) return;
                        widget.onReply(_replyCtrl.text.trim());
                        _replyCtrl.clear();
                      },
                      child: const Text('↩️ Antworten'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

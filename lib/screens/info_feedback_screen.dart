// lib/screens/info_feedback_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ignore: unused_import
import '../api/feedback_api.dart';
import '../api/legal_api.dart';
// ignore: unused_import
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
      setState(() {
        _datenschutz = dsController.text;
        _impressum = imController.text;
      });
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

// ─── Tab 1 + 2 stubs (implemented in later tasks) ────────────────────────────

class _NewsTab extends StatelessWidget {
  final AppConfig config;
  const _NewsTab({required this.config});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('News — kommt gleich'));
}

class _FeedbackTab extends StatelessWidget {
  final AppConfig config;
  const _FeedbackTab({required this.config});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Feedback — kommt gleich'));
}

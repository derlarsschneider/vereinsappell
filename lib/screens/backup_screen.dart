// lib/screens/backup_screen.dart
import 'package:flutter/material.dart';
import '../api/backup_api.dart';
import 'default_screen.dart';

const _clearableTables = ['marschbefehl', 'fines'];

class BackupScreen extends DefaultScreen {
  const BackupScreen({super.key, required super.config})
      : super(title: 'Backup & Restore');

  @override
  DefaultScreenState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends DefaultScreenState<BackupScreen> {
  late final BackupApi _api;
  List<String> _backups = [];
  bool _actionInProgress = false;

  @override
  void initState() {
    super.initState();
    _api = BackupApi(widget.config);
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => isLoading = true);
    try {
      final backups = await _api.listBackups();
      if (!mounted) return;
      setState(() {
        _backups = backups;
        isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        showNotification('Fehler beim Laden: $e');
      }
    }
  }

  void _showInfoDialog(String title, String details) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(details)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String details) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(details)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _createBackup() async {
    setState(() => _actionInProgress = true);
    try {
      final result = await _api.createBackup();
      if (!mounted) return;
      final counts = result['counts'] as Map<String, dynamic>? ?? {};
      final summary = counts.entries.map((e) => '${e.key}: ${e.value}').join('\n');
      _showInfoDialog('Backup erstellt', '${result['s3_path']}\n\n$summary');
      await _loadBackups();
    } catch (e) {
      if (mounted) showNotification('Fehler: $e');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _restoreBackup(String timestamp) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup einspielen?'),
        content: Text(
          'Achtung: Alle aktuellen Daten werden mit dem Stand vom $timestamp überschrieben. Wirklich wiederherstellen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Wiederherstellen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionInProgress = true);
    try {
      final result = await _api.restoreBackup(timestamp);
      if (!mounted) return;
      final counts = result['counts'] as Map<String, dynamic>? ?? {};
      final failed = result['failed'] as List;
      final summary = counts.entries.map((e) => '${e.key}: ${e.value}').join('\n');
      if (failed.isEmpty) {
        _showInfoDialog('Restore abgeschlossen', summary);
      } else {
        final errors = failed.map((f) => '${f['table']}: ${f['error']}').join('\n');
        _showErrorDialog('Restore-Fehler', '$summary\n\nFehler:\n$errors');
      }
    } catch (e) {
      if (mounted) showNotification('Fehler: $e');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _clearTable(String tableName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tabelle "$tableName" leeren?'),
        content: Text(
          'Achtung: Alle Einträge in "$tableName" werden unwiderruflich gelöscht!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leeren', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionInProgress = true);
    try {
      await _api.clearTable(tableName);
      if (mounted) showNotification('"$tableName" wurde geleert.');
    } catch (e) {
      if (mounted) showNotification('Fehler: $e');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: _actionInProgress ? null : _createBackup,
                    icon: _actionInProgress
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.backup),
                    label: const Text('Backup jetzt erstellen'),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Vorhandene Backups',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_backups.isEmpty)
                    const Text('Keine Backups vorhanden.', style: TextStyle(color: Colors.grey))
                  else
                    ..._backups.map((ts) => Card(
                          child: ListTile(
                            title: Text(ts, style: const TextStyle(fontFamily: 'monospace')),
                            trailing: TextButton(
                              onPressed: _actionInProgress ? null : () => _restoreBackup(ts),
                              child: const Text('Einspielen', style: TextStyle(color: Colors.orange)),
                            ),
                          ),
                        )),
                  const SizedBox(height: 24),
                  const Text(
                    'Tabellen leeren',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._clearableTables.map((table) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton(
                          onPressed: _actionInProgress ? null : () => _clearTable(table),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                          child: Text('$table leeren'),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}

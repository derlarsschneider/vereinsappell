import 'package:flutter/material.dart';
import '../models/poll.dart';

class PollFormData {
  final String title;
  final String description;
  final List<String> optionTexts;
  final bool allowMultiple;
  final bool isActive;
  final bool isVisible;
  final bool isSecretBallot;

  PollFormData({
    required this.title,
    required this.description,
    required this.optionTexts,
    required this.allowMultiple,
    required this.isActive,
    required this.isVisible,
    required this.isSecretBallot,
  });
}

Future<void> showPollFormDialog(
  BuildContext context, {
  Poll? poll,
  required void Function(PollFormData) onSave,
  VoidCallback? onDelete,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _PollFormSheet(poll: poll, onSave: onSave, onDelete: onDelete),
  );
}

class _PollFormSheet extends StatefulWidget {
  final Poll? poll;
  final void Function(PollFormData) onSave;
  final VoidCallback? onDelete;

  const _PollFormSheet({this.poll, required this.onSave, this.onDelete});

  @override
  State<_PollFormSheet> createState() => _PollFormSheetState();
}

class _PollFormSheetState extends State<_PollFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late List<TextEditingController> _optionCtrls;
  late bool _allowMultiple;
  late bool _isActive;
  late bool _isVisible;
  late bool _isSecretBallot;

  @override
  void initState() {
    super.initState();
    final p = widget.poll;
    _titleCtrl = TextEditingController(text: p?.title ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _optionCtrls = p != null && p.options.isNotEmpty
        ? p.options.map((o) => TextEditingController(text: o.text)).toList()
        : [TextEditingController(), TextEditingController()];
    _allowMultiple = p?.allowMultiple ?? false;
    _isActive = p?.isActive ?? true;
    _isVisible = p?.isVisible ?? true;
    _isSecretBallot = p?.isSecretBallot ?? false;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_optionCtrls.length <= 2) return;
    setState(() {
      _optionCtrls[i].dispose();
      _optionCtrls.removeAt(i);
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final texts = _optionCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (texts.length < 2) return;
    widget.onSave(PollFormData(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      optionTexts: texts,
      allowMultiple: _allowMultiple,
      isActive: _isActive,
      isVisible: _isVisible,
      isSecretBallot: _isSecretBallot,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.poll != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? 'Abstimmung bearbeiten' : 'Neue Abstimmung',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Titel *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Titel erforderlich' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Beschreibung (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              const Text('Antwortmöglichkeiten', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (var i = 0; i < _optionCtrls.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _optionCtrls[i],
                          decoration: InputDecoration(
                            labelText: 'Option ${i + 1}',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Erforderlich' : null,
                        ),
                      ),
                      if (_optionCtrls.length > 2)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _removeOption(i),
                        ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add),
                label: const Text('Option hinzufügen'),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('Mehrfachauswahl erlauben'),
                value: _allowMultiple,
                onChanged: (v) => setState(() => _allowMultiple = v),
              ),
              SwitchListTile(
                title: const Text('Geheime Wahl'),
                value: _isSecretBallot,
                onChanged: (v) => setState(() => _isSecretBallot = v),
              ),
              SwitchListTile(
                title: Text(widget.poll != null ? 'Aktiv' : 'Sofort aktivieren'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              SwitchListTile(
                title: const Text('Sichtbar'),
                value: _isVisible,
                onChanged: (v) => setState(() => _isVisible = v),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _submit,
                child: Text(isEdit ? 'Speichern' : 'Erstellen'),
              ),
              if (widget.onDelete != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: widget.onDelete,
                  child: const Text(
                    'Abstimmung löschen',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

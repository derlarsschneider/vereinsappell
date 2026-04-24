import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/getraenke_api.dart';
import '../config_loader.dart';
import 'default_screen.dart';

class DrinkDef {
  final String id;
  final String name;
  final String headerEmoji;
  final String buttonEmoji;
  final bool hasBottle;

  const DrinkDef({
    required this.id,
    required this.name,
    required this.headerEmoji,
    required this.buttonEmoji,
    required this.hasBottle,
  });
}

const kDrinks = [
  DrinkDef(id: 'alt',       name: 'Alt',       headerEmoji: '🍺', buttonEmoji: '🍺', hasBottle: false),
  DrinkDef(id: 'pils',      name: 'Pils',      headerEmoji: '🍻', buttonEmoji: '🍻', hasBottle: false),
  DrinkDef(id: 'cola',      name: 'Cola',      headerEmoji: '🥤', buttonEmoji: '🥤', hasBottle: true),
  DrinkDef(id: 'fanta',     name: 'Fanta',     headerEmoji: '🥤', buttonEmoji: '🥤', hasBottle: true),
  DrinkDef(id: 'sprite',    name: 'Sprite',    headerEmoji: '🥤', buttonEmoji: '🥤', hasBottle: true),
  DrinkDef(id: 'cola_zero', name: 'Cola Zero', headerEmoji: '🥤', buttonEmoji: '🥤', hasBottle: true),
  DrinkDef(id: 'wasser',    name: 'Wasser',    headerEmoji: '💧', buttonEmoji: '💧', hasBottle: true),
];

// ── BierdeckelCard ────────────────────────────────────────────────────────────

class BierdeckelCard extends StatelessWidget {
  final DrinkDef drink;
  final List<TallyEntry> entries;
  final String myMemberId;
  final VoidCallback onStrich;
  final VoidCallback? onFlasche;
  final Function(String) onDeleteMark;

  const BierdeckelCard({
    super.key,
    required this.drink,
    required this.entries,
    required this.myMemberId,
    required this.onStrich,
    required this.onFlasche,
    required this.onDeleteMark,
  });

  void _decrementStrich() {
    final own = entries
        .where((e) => e.memberId == myMemberId && e.type == 'strich')
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (own.isNotEmpty) onDeleteMark(own.first.id);
  }

  void _decrementFlasche() {
    final own = entries
        .where((e) => e.memberId == myMemberId && e.type == 'flasche')
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (own.isNotEmpty) onDeleteMark(own.first.id);
  }

  Widget _buildBadge(int myStriche, int myFlaschen) {
    final String label;
    if (!drink.hasBottle || myFlaschen == 0) {
      label = '$myStriche';
    } else if (myStriche == 0) {
      label = '$myFlaschen🍾';
    } else {
      label = '$myStriche🥤  $myFlaschen🍾';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildButtons(int myStriche, int myFlaschen) {
    final hasBottleButton = drink.hasBottle && onFlasche != null;
    if (hasBottleButton) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CounterRow(
            emoji: drink.buttonEmoji,
            onDecrement: myStriche > 0 ? _decrementStrich : null,
            onIncrement: onStrich,
            small: true,
          ),
          const SizedBox(height: 6),
          _CounterRow(
            emoji: '🍾',
            onDecrement: myFlaschen > 0 ? _decrementFlasche : null,
            onIncrement: onFlasche!,
            small: true,
          ),
        ],
      );
    }
    return _CounterRow(
      emoji: drink.buttonEmoji,
      onDecrement: myStriche > 0 ? _decrementStrich : null,
      onIncrement: onStrich,
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalStriche = entries.where((e) => e.type == 'strich').length;
    final totalFlaschen = entries.where((e) => e.type == 'flasche').length;
    final myStriche = entries.where((e) => e.memberId == myMemberId && e.type == 'strich').length;
    final myFlaschen = entries.where((e) => e.memberId == myMemberId && e.type == 'flasche').length;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFDF8EE), Color(0xFFF0E8D0)],
            ),
            border: Border.all(color: const Color(0xFFC8A96E), width: 2),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(2, 3))],
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(drink.headerEmoji, style: const TextStyle(fontSize: 20)),
                    Text(
                      drink.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF4A2C00)),
                    ),
                    _TallyRow(totalStriche: totalStriche, totalFlaschen: totalFlaschen),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildButtons(myStriche, myFlaschen),
            ],
          ),
        ),
        if (myStriche > 0 || myFlaschen > 0)
          Positioned(
            top: -10,
            right: 14,
            child: _buildBadge(myStriche, myFlaschen),
          ),
      ],
    );
  }
}

class _TallyRow extends StatelessWidget {
  final int totalStriche;
  final int totalFlaschen;

  const _TallyRow({required this.totalStriche, required this.totalFlaschen});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ..._strichWidgets(),
        ..._flascheWidgets(),
      ],
    );
  }

  List<Widget> _strichWidgets() {
    final widgets = <Widget>[];
    final groups = totalStriche ~/ 5;
    final remainder = totalStriche % 5;

    for (int i = 0; i < groups; i++) {
      widgets.add(const _TallyGroup());
      widgets.add(const SizedBox(width: 6));
    }
    for (int i = 0; i < remainder; i++) {
      widgets.add(const _Stick());
    }
    return widgets;
  }

  List<Widget> _flascheWidgets() {
    return List.generate(
      totalFlaschen,
      (_) => const Text('🍾', style: TextStyle(fontSize: 14)),
    );
  }
}

class _TallyGroup extends StatelessWidget {
  const _TallyGroup();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(4, (_) => const Padding(
              padding: EdgeInsets.only(right: 2),
              child: _Stick(),
            )),
          ),
          Positioned(
            top: 3,
            left: -4,
            child: Transform.rotate(
              angle: -0.31,
              child: Container(
                width: 38,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2C),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stick extends StatelessWidget {
  const _Stick();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 24,
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _CounterRow extends StatelessWidget {
  final String emoji;
  final VoidCallback? onDecrement;
  final VoidCallback onIncrement;
  final bool small;

  const _CounterRow({
    required this.emoji,
    required this.onDecrement,
    required this.onIncrement,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = small ? 24.0 : 28.0;
    final emojiSize = small ? 15.0 : 18.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PmButton(size: size, filled: false, enabled: onDecrement != null, onTap: onDecrement ?? () {}),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(emoji, style: TextStyle(fontSize: emojiSize)),
        ),
        _PmButton(size: size, filled: true, enabled: true, onTap: onIncrement),
      ],
    );
  }
}

class _PmButton extends StatelessWidget {
  final double size;
  final bool filled;
  final bool enabled;
  final VoidCallback onTap;

  const _PmButton({
    required this.size,
    required this.filled,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: filled ? const Color(0xFF7A4F00) : Colors.white,
          border: Border.all(
            color: enabled ? const Color(0xFF7A4F00) : const Color(0xFFCCCCCC),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(size / 2),
        ),
        child: Center(
          child: Text(
            filled ? '+' : '−',
            style: TextStyle(
              fontSize: size * 0.57,
              fontWeight: FontWeight.w700,
              color: filled
                  ? Colors.white
                  : (enabled ? const Color(0xFF7A4F00) : const Color(0xFFCCCCCC)),
            ),
          ),
        ),
      ),
    );
  }
}

// ── GetraenkeScreen ───────────────────────────────────────────────────────────

class GetraenkeScreen extends DefaultScreen {
  const GetraenkeScreen({super.key, required super.config})
      : super(title: 'Getränke');

  @override
  DefaultScreenState createState() => _GetraenkeScreenState();
}

class _GetraenkeScreenState extends DefaultScreenState<GetraenkeScreen> {
  late final GetraenkeApi _api;
  late final StreamSubscription<List<TallyEntry>> _sub;
  List<TallyEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _api = GetraenkeApi(widget.config);
    _sub = _api.watchTallies().listen(
      (entries) { if (mounted) setState(() => _entries = entries); },
      onError: (e) { if (mounted) showError('Firebase-Fehler: $e'); },
    );
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

  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('🍻 Getränke')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          if (member.isSaftschubse) ...[
            ElevatedButton.icon(
              onPressed: _confirmReset,
              icon: const Icon(Icons.delete_sweep, color: Colors.white),
              label: const Text('Alle Striche löschen', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
            const SizedBox(height: 12),
          ],
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
        ],
      ),
    );
  }
}

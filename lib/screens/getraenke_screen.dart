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
  DrinkDef(id: 'pils',      name: 'Pils',      headerEmoji: '🍻', buttonEmoji: '🍺', hasBottle: false),
  DrinkDef(id: 'cola',      name: 'Cola',      headerEmoji: '🥤', buttonEmoji: '🥤', hasBottle: true),
  DrinkDef(id: 'fanta',     name: 'Fanta',     headerEmoji: '🥤', buttonEmoji: '🥤', hasBottle: true),
  DrinkDef(id: 'sprite',    name: 'Sprite',    headerEmoji: '🥤', buttonEmoji: '🥤', hasBottle: true),
  DrinkDef(id: 'cola_zero', name: 'Cola Zero', headerEmoji: '🥤', buttonEmoji: '🥤', hasBottle: true),
  DrinkDef(id: 'wasser',    name: 'Wasser',    headerEmoji: '💧', buttonEmoji: '🫗', hasBottle: true),
];

// ── BierdeckelCard ────────────────────────────────────────────────────────────

class BierdeckelCard extends StatelessWidget {
  final DrinkDef drink;
  final List<TallyEntry> entries;
  final String myMemberId;
  final VoidCallback onStrich;
  final VoidCallback? onFlasche;

  const BierdeckelCard({
    super.key,
    required this.drink,
    required this.entries,
    required this.myMemberId,
    required this.onStrich,
    required this.onFlasche,
  });

  @override
  Widget build(BuildContext context) {
    final myStriche      = entries.where((e) => e.memberId == myMemberId && e.type == 'strich').length;
    final othersStriche  = entries.where((e) => e.memberId != myMemberId && e.type == 'strich').length;
    final myFlaschen     = entries.where((e) => e.memberId == myMemberId && e.type == 'flasche').length;
    final othersFlaschen = entries.where((e) => e.memberId != myMemberId && e.type == 'flasche').length;

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(drink.headerEmoji, style: const TextStyle(fontSize: 20)),
              Text(
                drink.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF4A2C00)),
              ),
              _TallyRow(
                myStriche: myStriche,
                othersStriche: othersStriche,
                myFlaschen: myFlaschen,
                othersFlaschen: othersFlaschen,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _TallyButton(emoji: drink.buttonEmoji, filled: true, onTap: onStrich)),
              if (drink.hasBottle && onFlasche != null) ...[
                const SizedBox(width: 8),
                Expanded(child: _TallyButton(emoji: '🍾', filled: false, onTap: onFlasche!)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TallyRow extends StatelessWidget {
  final int myStriche;
  final int othersStriche;
  final int myFlaschen;
  final int othersFlaschen;

  const _TallyRow({
    required this.myStriche,
    required this.othersStriche,
    required this.myFlaschen,
    required this.othersFlaschen,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ..._strichWidgets(myStriche, const Color(0xFFE53935)),
        ..._flascheWidgets(myFlaschen),
        ..._strichWidgets(othersStriche, const Color(0xFF2C2C2C)),
        ..._flascheWidgets(othersFlaschen),
      ],
    );
  }

  List<Widget> _strichWidgets(int count, Color color) {
    final widgets = <Widget>[];
    final groups = count ~/ 5;
    final remainder = count % 5;
    for (int i = 0; i < groups; i++) {
      widgets.add(_TallyGroup(color: color));
      widgets.add(const SizedBox(width: 6));
    }
    for (int i = 0; i < remainder; i++) {
      widgets.add(_Stick(color: color));
    }
    return widgets;
  }

  List<Widget> _flascheWidgets(int count) {
    return List.generate(
      count,
      (_) => const Text('🍾', style: TextStyle(fontSize: 14)),
    );
  }
}

class _TallyGroup extends StatelessWidget {
  final Color color;
  const _TallyGroup({required this.color});

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
            children: List.generate(4, (_) => Padding(
              padding: const EdgeInsets.only(right: 2),
              child: _Stick(color: color),
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
                  color: color,
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
  final Color color;
  const _Stick({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _TallyButton extends StatelessWidget {
  final String emoji;
  final bool filled;
  final VoidCallback onTap;

  const _TallyButton({required this.emoji, required this.filled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: filled ? const Color(0xFF7A4F00) : Colors.white,
          border: Border.all(color: const Color(0xFF7A4F00), width: 2),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(1, 2))],
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
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
        padding: const EdgeInsets.all(12),
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
              padding: const EdgeInsets.only(bottom: 10),
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
              ),
            );
          }),
        ],
      ),
    );
  }
}

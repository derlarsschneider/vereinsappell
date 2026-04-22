import 'package:flutter/material.dart';
import '../api/monitoring_api.dart';
import '../config_loader.dart';
import 'default_screen.dart';

class MonitoringScreen extends DefaultScreen {
  final MonitoringApi? monitoringApi;

  const MonitoringScreen({
    super.key,
    required super.config,
    this.monitoringApi,
  }) : super(title: 'Monitoring');

  @override
  DefaultScreenState<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends DefaultScreenState<MonitoringScreen> {
  late final MonitoringApi _api;
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _startupStats;
  Map<String, dynamic>? _perfStats;
  String _timeframe = 'day';
  String? _selectedClub;

  @override
  void initState() {
    super.initState();
    _api = widget.monitoringApi ?? MonitoringApi(widget.config);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final data = await _api.getStats(_timeframe);
      final startupData = await _api.getStartupStats(_timeframe);
      Map<String, dynamic>? perfData;
      try {
        perfData = await _api.getPerfStats(_timeframe);
      } catch (_) {}
      setState(() {
        _stats = data;
        _startupStats = startupData;
        _perfStats = perfData;
        isLoading = false;
      });
    } catch (e) {
      showError('Fehler beim Laden: $e');
      setState(() => isLoading = false);
    }
  }

  String _clubName(String appId) {
    final clubs = _stats?['calls_per_club'] as List? ?? [];
    final match = clubs.cast<Map>().where((c) => c['applicationId'] == appId).firstOrNull;
    return match?['clubName'] as String? ?? appId;
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return double.tryParse(value)?.toInt() ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Monitoring'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTimeframeSelector(),
                  const SizedBox(height: 16),
                  if (_stats != null) ...[
                    _buildClubFilter(),
                    const SizedBox(height: 16),
                    _buildSummaryTiles(),
                    const SizedBox(height: 16),
                    _buildClubChart(),
                    const SizedBox(height: 16),
                    _buildEndpointChart(),
                    const SizedBox(height: 16),
                    _buildMemberChart(),
                    const SizedBox(height: 16),
                  ],
                  _buildPerfTable(),
                  const SizedBox(height: 16),
                  _buildPhaseBreakdown(),
                  const SizedBox(height: 16),
                  _buildStartupTable(),
                ],
              ),
            ),
    );
  }

  Widget _buildTimeframeSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: '15minutes', label: Text('15 Min')),
        ButtonSegment(value: 'hour', label: Text('Std')),
        ButtonSegment(value: 'day', label: Text('Tag')),
        ButtonSegment(value: 'week', label: Text('Woche')),
      ],
      selected: {_timeframe},
      onSelectionChanged: (newSelection) {
        setState(() => _timeframe = newSelection.first);
        _loadData();
      },
    );
  }

  Widget _buildClubFilter() {
    final clubs = (_stats?['calls_per_club'] as List? ?? []).cast<Map>().toList()
      ..sort((a, b) => (a['applicationId'] as String).compareTo(b['applicationId'] as String));

    return DropdownButtonFormField<String?>(
      value: _selectedClub,
      decoration: const InputDecoration(
        labelText: 'Vereins-Filter',
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Alle Vereine')),
        ...clubs.map((c) => DropdownMenuItem<String?>(
              value: c['applicationId'] as String,
              child: Text(c['clubName'] as String? ?? c['applicationId'] as String),
            )),
      ],
      onChanged: (value) => setState(() => _selectedClub = value),
    );
  }

  Widget _buildEndpointChart() {
    final all = _stats?['calls_per_endpoint'] as List? ?? [];
    final filtered = _selectedClub == null
        ? all
        : all.where((e) => (e as Map)['applicationId'] == _selectedClub).toList();

    final counts = <String, int>{};
    for (final item in filtered) {
      final path = (item as Map)['path'] as String? ?? 'unknown';
      final count = _toInt(item['count']);
      counts[path] = (counts[path] ?? 0) + count;
    }

    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return _buildHorizontalBarChart(
      title: 'API Calls pro Endpunkt',
      subtitle: _selectedClub == null ? '(Alle Vereine)' : '(${_clubName(_selectedClub!)})',
      entries: entries,
      barColor: Colors.purple,
    );
  }

  Widget _buildMemberChart() {
    final all = _stats?['calls_per_member'] as List? ?? [];
    final filtered = _selectedClub == null
        ? all
        : all.where((e) => (e as Map)['applicationId'] == _selectedClub).toList();

    final counts = <String, int>{};
    for (final item in filtered) {
      final name = (item as Map)['memberName'] as String? ?? item['memberId'] as String? ?? 'unknown';
      final count = _toInt(item['count']);
      counts[name] = (counts[name] ?? 0) + count;
    }

    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topEntries = entries.take(15).toList();

    return _buildHorizontalBarChart(
      title: 'Top Mitglieder (Requests)',
      subtitle: _selectedClub == null ? '(Alle Vereine)' : '(${_clubName(_selectedClub!)})',
      entries: topEntries,
      barColor: Colors.orange,
    );
  }

  Widget _buildSummaryTiles() {
    final clubs = _stats?['calls_per_club'] as List? ?? [];
    final totalCalls = clubs.fold<int>(0, (sum, e) => sum + _toInt((e as Map)['count']));
    final activeClubs = clubs.length;

    final startupList = _startupStats?['startup_stats'] as List? ?? [];
    final avgP50 = startupList.isEmpty
        ? null
        : startupList.fold<int>(0, (sum, e) => sum + _toInt((e as Map)['p50'])) ~/
            startupList.length;

    return Row(
      children: [
        Expanded(child: _summaryTile('$totalCalls', 'API Calls gesamt', Colors.green)),
        const SizedBox(width: 8),
        Expanded(child: _summaryTile('$activeClubs', 'Aktive Vereine', Colors.blue)),
        const SizedBox(width: 8),
        Expanded(
          child: _summaryTile(
            avgP50 != null ? '${avgP50}ms' : '—',
            'Ø Startup p50',
            Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _summaryTile(String value, String label, Color valueColor) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: valueColor)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildClubChart() {
    final clubs = _stats?['calls_per_club'] as List? ?? [];
    final entries = clubs
        .map((e) => MapEntry(
              (e as Map)['clubName'] as String? ?? e['applicationId'] as String,
              _toInt(e['count']),
            ))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _buildHorizontalBarChart(
      title: 'API Calls pro Verein',
      entries: entries,
      barColor: Colors.blue,
    );
  }

  Widget _buildHorizontalBarChart({
    required String title,
    String? subtitle,
    required List<MapEntry<String, int>> entries,
    required Color barColor,
  }) {
    if (entries.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Keine Daten für diesen Zeitraum'),
        ),
      );
    }

    final maxCount = entries.first.value;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const SizedBox(height: 16),
            ...entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: Text(
                          e.key,
                          style: const TextStyle(fontSize: 10),
                          textAlign: TextAlign.left,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: LinearProgressIndicator(
                          value: maxCount > 0 ? e.value / maxCount : 0,
                          backgroundColor: Colors.grey.withOpacity(0.2),
                          color: barColor,
                          minHeight: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 40,
                        child: Text('${e.value}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 4),
            const Center(
              child: Text(
                '← Anzahl Aufrufe →',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerfTable() {
    final stats = _perfStats?['perf_stats'] as List? ?? [];
    final filtered = _selectedClub == null
        ? stats
        : stats.where((e) => (e as Map)['applicationId'] == _selectedClub).toList();

    if (filtered.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _perfStats == null
                ? 'Performance-Logging nicht aktiviert (PERF_LOGGING_ENABLED=true setzen)'
                : 'Keine Performance-Daten für diesen Zeitraum',
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final rows = filtered.cast<Map>().toList()
      ..sort((a, b) => _toInt(b['p50']).compareTo(_toInt(a['p50'])));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('API Response-Zeiten (ms)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (_selectedClub != null) ...[
              const SizedBox(height: 4),
              Text('(${_clubName(_selectedClub!)})',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(4),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1),
                4: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                  children: ['Endpoint', 'p50', 'p95', 'p99', 'Calls']
                      .map((h) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(h,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: Colors.grey)),
                          ))
                      .toList(),
                ),
                ...rows.map((row) => TableRow(children: [
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            row['path'] as String? ?? '—',
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          )),
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text('${row['p50'] ?? '—'}',
                              style: const TextStyle(fontSize: 11, color: Colors.green))),
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text('${row['p95'] ?? '—'}',
                              style: const TextStyle(fontSize: 11, color: Colors.orange))),
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text('${row['p99'] ?? '—'}',
                              style: const TextStyle(fontSize: 11, color: Colors.red))),
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text('${row['count'] ?? '—'}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey))),
                    ])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseBreakdown() {
    final ps = _startupStats?['phase_stats'] as Map?;
    if (ps == null || ps.isEmpty) {
      return const SizedBox.shrink();
    }

    final phases = [
      ('Firebase Init', 'firebase'),
      ('Config Load', 'config'),
      ('First Frame', 'first_frame'),
      ('Fetch Member', 'fetch_member'),
      ('Get Customer', 'get_customer'),
      ('Total', 'total'),
    ];

    int? maxP50 = phases
        .map((p) => _toInt(ps['${p.$2}_p50']))
        .reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Startup-Phasen (ms)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Kumulativ ab App-Start', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                  children: ['Phase', 'p50', 'p95', 'p99']
                      .map((h) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(h,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: Colors.grey)),
                          ))
                      .toList(),
                ),
                ...phases.map((phase) {
                  final p50 = _toInt(ps['${phase.$2}_p50']);
                  final p95 = _toInt(ps['${phase.$2}_p95']);
                  final p99 = _toInt(ps['${phase.$2}_p99']);
                  final isSlowest = phase.$2 != 'total' && p50 == maxP50;
                  return TableRow(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        phase.$1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSlowest ? FontWeight.bold : FontWeight.normal,
                          color: isSlowest ? Colors.red : null,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('$p50',
                          style: TextStyle(
                              fontSize: 11,
                              color: isSlowest ? Colors.red : Colors.green,
                              fontWeight: isSlowest ? FontWeight.bold : FontWeight.normal)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('$p95', style: const TextStyle(fontSize: 11, color: Colors.orange)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('$p99', style: const TextStyle(fontSize: 11, color: Colors.red)),
                    ),
                  ]);
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartupTable() {
    final stats = _startupStats?['startup_stats'] as List? ?? [];
    if (stats.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Keine Startup-Daten für diesen Zeitraum'),
        ),
      );
    }

    final rows = (stats as List<dynamic>)
      ..sort((a, b) => _toInt((a as Map)['p50']).compareTo(_toInt((b as Map)['p50'])));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('App Startup-Zeiten (ms)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(4),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1),
                4: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                  children: ['Member', 'p50', 'p95', 'p99', 'Starts']
                      .map((h) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(h,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                          ))
                      .toList(),
                ),
                ...rows.map((row) {
                  final r = row as Map;
                  final name = r['memberName'] as String? ?? r['memberId'] as String? ?? '';
                  return TableRow(children: [
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(name, style: const TextStyle(fontSize: 11))),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('${r['p50'] ?? '—'}',
                            style: const TextStyle(fontSize: 11, color: Colors.green))),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('${r['p95'] ?? '—'}',
                            style: const TextStyle(fontSize: 11, color: Colors.orange))),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('${r['p99'] ?? '—'}',
                            style: const TextStyle(fontSize: 11, color: Colors.red))),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('${r['count'] ?? '—'}',
                            style: const TextStyle(fontSize: 11, color: Colors.grey))),
                  ]);
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

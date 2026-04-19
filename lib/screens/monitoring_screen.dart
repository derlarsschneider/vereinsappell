import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../api/monitoring_api.dart';
import 'default_screen.dart';

class MonitoringScreen extends DefaultScreen {
  const MonitoringScreen({super.key, required super.config}) : super(title: 'Monitoring');

  @override
  DefaultScreenState<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends DefaultScreenState<MonitoringScreen> {
  late final MonitoringApi _api;
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _startupStats;
  String _timeframe = 'day';

  @override
  void initState() {
    super.initState();
    _api = MonitoringApi(widget.config);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final data = await _api.getStats(_timeframe);
      setState(() {
        _stats = data;
        _startupStats = data;
        isLoading = false;
      });
    } catch (e) {
      showError('Fehler beim Laden: $e');
      setState(() => isLoading = false);
    }
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
                  const SizedBox(height: 24),
                  if (_stats != null) ...[
                    _buildCallsChart(),
                    const SizedBox(height: 32),
                    _buildActiveMembersSection(),
                    if (_startupStats != null) ...[
                      const SizedBox(height: 32),
                      _buildStartupStats(),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildTimeframeSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'minute', label: Text('Min')),
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

  Widget _buildCallsChart() {
    final calls = _stats?['calls_per_club'] as List? ?? [];
    if (calls.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Keine Daten für diesen Zeitraum')));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('API Aufrufe pro Verein', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(
          height: 250,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              barGroups: calls.asMap().entries.map((e) {
                final data = e.value as Map;
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: (data['count'] as int).toDouble(),
                      color: Colors.green,
                      width: 20,
                    ),
                  ],
                );
              }).toList(),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i >= 0 && i < calls.length) {
                        final appId = calls[i]['applicationId'] as String;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(appId.length > 5 ? appId.substring(0, 5) : appId, style: const TextStyle(fontSize: 10)),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveMembersSection() {
    final clubs = _stats?['active_members'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Aktive Mitglieder & Aktivitätslevel', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        if (clubs.isEmpty) const Text('Keine aktiven Mitglieder gefunden.'),
        ...clubs.map((clubData) {
          final appId = clubData['applicationId'] as String;
          final members = clubData['members'] as List? ?? [];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              title: Text('Verein: $appId'),
              subtitle: Text('${members.length} aktive Mitglieder'),
              children: members.map((m) {
                final memberId = m['memberId'] as String;
                final activity = m['activity'] as int;
                return ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(memberId),
                  trailing: Chip(
                    label: Text('$activity Requests'),
                    backgroundColor: Colors.green.withValues(alpha: 0.1),
                  ),
                );
              }).toList(),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStartupStats() {
    final stats = _startupStats?['startup_stats'] as List? ?? [];
    if (stats.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Keine Startup-Daten für diesen Zeitraum'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Startup-Zeiten pro Mitglied',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Mitglied')),
              DataColumn(label: Text('Verein')),
              DataColumn(label: Text('p50 (ms)')),
              DataColumn(label: Text('p95 (ms)')),
              DataColumn(label: Text('p99 (ms)')),
              DataColumn(label: Text('Messungen')),
            ],
            rows: stats.map((stat) {
              return DataRow(
                cells: [
                  DataCell(Text(stat['memberId'] ?? '-')),
                  DataCell(Text(stat['applicationId'] ?? '-')),
                  DataCell(Text((stat['p50'] ?? 0).toString())),
                  DataCell(Text((stat['p95'] ?? 0).toString())),
                  DataCell(Text((stat['p99'] ?? 0).toString())),
                  DataCell(Text((stat['count'] ?? 0).toString())),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

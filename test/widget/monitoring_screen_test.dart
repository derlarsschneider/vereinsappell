import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vereinsappell/api/monitoring_api.dart';
import 'package:vereinsappell/screens/monitoring_screen.dart';

import 'test_helpers.dart';

Map<String, dynamic> _statsPayload({
  List<Map<String, dynamic>>? callsPerClub,
  List<Map<String, dynamic>>? callsPerEndpoint,
  List<Map<String, dynamic>>? callsPerMember,
}) =>
    {
      'calls_per_club': callsPerClub ?? [
        {'applicationId': 'TZG', 'count': 100},
        {'applicationId': 'BSV', 'count': 50},
      ],
      'calls_per_endpoint': callsPerEndpoint ?? [
        {'applicationId': 'TZG', 'path': '/members', 'count': 60},
        {'applicationId': 'BSV', 'path': '/members', 'count': 20},
      ],
      'calls_per_member': callsPerMember ?? [
        {'applicationId': 'TZG', 'memberId': 'm1', 'count': 80},
        {'applicationId': 'BSV', 'memberId': 'm2', 'count': 30},
      ],
      'active_members': [],
      'timeframe': 'day',
    };

Map<String, dynamic> _startupPayload() => {
      'startup_stats': [
        {'applicationId': 'TZG', 'memberId': 'm1', 'p50': 312, 'p95': 580, 'p99': 920, 'count': 14},
      ],
      'timeframe': 'day',
    };

Future<MonitoringApi> _makeApi(WidgetTester tester) async {
  final client = MockClient((request) async {
    if (request.url.path.contains('/monitoring/startup')) {
      return http.Response(jsonEncode(_startupPayload()), 200);
    }
    return http.Response(jsonEncode(_statsPayload()), 200);
  });
  final config = await makeConfig(tester);
  return MonitoringApi(config, client: client);
}

void main() {
  group('MonitoringScreen', () {
    testWidgets('renders without error after data loads', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('summary tiles show total calls, active clubs, avg p50', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();

      // Total calls: 100 + 50 = 150
      expect(find.text('150'), findsOneWidget);
      // Active clubs: 2
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('startup table shows p50, p95, p99 values', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();

      expect(find.text('312'), findsOneWidget);
      expect(find.text('580'), findsOneWidget);
      expect(find.text('920'), findsOneWidget);
    });

    testWidgets('calls per club chart shows club labels', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();

      expect(find.text('TZG'), findsWidgets);
      expect(find.text('BSV'), findsWidgets);
    });

    testWidgets('endpoint chart shows path labels', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();

      expect(find.text('/members'), findsWidgets);
    });

    testWidgets('member chart shows member labels', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();

      expect(find.text('m1'), findsWidgets);
      expect(find.text('m2'), findsWidgets);
    });

    testWidgets('club filter dropdown contains all club options', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();

      // Open the dropdown
      await tester.tap(find.text('Alle Vereine').first);
      await tester.pumpAndSettle();

      expect(find.text('TZG'), findsWidgets);
      expect(find.text('BSV'), findsWidgets);
    });

    testWidgets('old active members expansion tiles are gone', (tester) async {
      final api = await _makeApi(tester);
      final config = await makeConfig(tester);
      await tester.pumpWidget(
        wrapScreen(MonitoringScreen(config: config, monitoringApi: api), config),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ExpansionTile), findsNothing);
    });
  });
}

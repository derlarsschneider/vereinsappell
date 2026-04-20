import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vereinsappell/api/fines_api.dart';
import 'package:vereinsappell/screens/strafen_screen.dart';

import 'test_helpers.dart';

void main() {
  group('StrafenScreen', () {
    testWidgets('zeigt Lade-Spinner während API-Call läuft', (tester) async {
      final completer = Completer<http.Response>();
      final client = MockClient((_) => completer.future);
      final config = await makeConfig(tester);
      final api = FinesApi(config, client: client);

      await tester.pumpWidget(
        wrapScreen(StrafenScreen(config: config, finesApi: api), config),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      completer.complete(http.Response('{"name":"","fines":[]}', 200));
    });

    testWidgets('zeigt "Keine Strafen vorhanden" bei leerer Liste', (tester) async {
      final payload = {'name': 'Max', 'fines': []};
      final client = MockClient((_) async => http.Response(jsonEncode(payload), 200));
      final config = await makeConfig(tester);
      final api = FinesApi(config, client: client);

      await tester.pumpWidget(
        wrapScreen(StrafenScreen(config: config, finesApi: api), config),
      );
      await tester.pumpAndSettle();
      expect(find.text('Keine Strafen vorhanden'), findsOneWidget);
    });

    testWidgets('zeigt Strafen-Items mit Grund und Betrag', (tester) async {
      final payload = {
        'name': 'Max',
        'fines': [
          {'fineId': 'f1', 'reason': 'Zu spät', 'amount': '5.00'},
          {'fineId': 'f2', 'reason': 'Handy', 'amount': '10.00' , 'date': '2026-04-19 10:00:00'},
        ],
      };
      final client = MockClient((_) async => http.Response(jsonEncode(payload), 200));
      final config = await makeConfig(tester);
      final api = FinesApi(config, client: client);

      await tester.pumpWidget(
        wrapScreen(StrafenScreen(config: config, finesApi: api), config),
      );
      await tester.pumpAndSettle();
      expect(find.text('Zu spät ()'), findsOneWidget);
      expect(find.text('Handy (2026-04-19 10:00:00)'), findsOneWidget);
      expect(find.textContaining('5.00'), findsWidgets);
    });

    testWidgets('zeigt korrekten Gesamtbetrag', (tester) async {
      final payload = {
        'name': 'Max',
        'fines': [
          {'fineId': 'f1', 'reason': 'A', 'amount': '5.00'},
          {'fineId': 'f2', 'reason': 'B', 'amount': '10.50'},
        ],
      };
      final client = MockClient((_) async => http.Response(jsonEncode(payload), 200));
      final config = await makeConfig(tester);
      final api = FinesApi(config, client: client);

      await tester.pumpWidget(
        wrapScreen(StrafenScreen(config: config, finesApi: api), config),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('15.50'), findsOneWidget);
    });

    testWidgets('Fehler beim Laden → SnackBar', (tester) async {
      final client = MockClient((_) async => http.Response('Server Error', 500));
      final config = await makeConfig(tester);
      final api = FinesApi(config, client: client);

      await tester.pumpWidget(
        wrapScreen(StrafenScreen(config: config, finesApi: api), config),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}

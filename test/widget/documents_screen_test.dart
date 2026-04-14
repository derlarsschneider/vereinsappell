import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vereinsappell/api/documents_api.dart';
import 'package:vereinsappell/config_loader.dart';
import 'package:vereinsappell/screens/documents_screen.dart';

import 'test_helpers.dart';

DocumentApi _stubApi(AppConfig config, List<Map<String, dynamic>> docs) {
  final client = MockClient((_) async => http.Response(jsonEncode(docs), 200));
  return DocumentApi(config, client: client);
}

void main() {
  group('DocumentScreen', () {
    testWidgets('zeigt Kategorien als ExpansionTile', (tester) async {
      final config = await makeConfig(tester, sessionPassword: 'testpw');
      final api = _stubApi(config, [
        {'name': 'Protokolle/p.pdf'},
        {'name': 'Protokolle/q.pdf'},
      ]);

      await tester.pumpWidget(wrapScreen(DocumentScreen(config: config, documentApi: api), config));
      await tester.pumpAndSettle();

      expect(find.byType(ExpansionTile), findsOneWidget);
      expect(find.text('Protokolle'), findsOneWidget);
    });

    testWidgets("''-Kategorie erscheint als 'Allgemein'", (tester) async {
      final config = await makeConfig(tester, sessionPassword: 'testpw');
      final api = _stubApi(config, [
        {'name': 'allgemein.pdf'},
      ]);

      await tester.pumpWidget(wrapScreen(DocumentScreen(config: config, documentApi: api), config));
      await tester.pumpAndSettle();

      expect(find.text('Allgemein'), findsOneWidget);
    });

    testWidgets('PDF-Datei hat Icons.picture_as_pdf', (tester) async {
      final config = await makeConfig(tester, sessionPassword: 'testpw');
      final api = _stubApi(config, [
        {'name': 'test.pdf'},
      ]);

      await tester.pumpWidget(wrapScreen(DocumentScreen(config: config, documentApi: api), config));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
    });

    testWidgets('Nicht-Admin sieht keinen Upload-Button', (tester) async {
      final config = await makeConfig(tester, sessionPassword: 'testpw', isAdmin: false);
      final api = _stubApi(config, [{'name': 'test.pdf'}]);

      await tester.pumpWidget(wrapScreen(DocumentScreen(config: config, documentApi: api), config));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.upload_file), findsNothing);
    });

    testWidgets('Admin sieht Upload-Button', (tester) async {
      final config = await makeConfig(tester, sessionPassword: 'testpw', isAdmin: true);
      final api = _stubApi(config, [{'name': 'test.pdf'}]);

      await tester.pumpWidget(wrapScreen(DocumentScreen(config: config, documentApi: api), config));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.upload_file), findsOneWidget);
    });
  });
}

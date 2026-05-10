import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vereinsappell/api/gallery_api.dart';
import 'package:vereinsappell/config_loader.dart';
import 'package:vereinsappell/screens/galerie_screen.dart';

import 'test_helpers.dart';

GalleryApi _stubApi(AppConfig config, List<Map<String, dynamic>> photos) {
  final client = MockClient(
    (_) async => http.Response(jsonEncode(photos), 200),
  );
  return GalleryApi(config, client: client);
}

void main() {
  group('GalleryScreen', () {
    testWidgets('zeigt Foto-Grid wenn Fotos vorhanden', (tester) async {
      final config = await makeConfig(tester);
      final api = _stubApi(config, [
        {
          'name': 'photo.jpg',
          'thumbnail_url': 'https://s3.example.com/thumb/photo.jpg',
          'photo_url': 'https://s3.example.com/img/photo.jpg',
        },
      ]);

      await tester.pumpWidget(
        wrapScreen(GalleryScreen(config: config, galleryApi: api), config),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('zeigt Text wenn keine Fotos vorhanden', (tester) async {
      final config = await makeConfig(tester);
      final api = _stubApi(config, []);

      await tester.pumpWidget(
        wrapScreen(GalleryScreen(config: config, galleryApi: api), config),
      );
      await tester.pumpAndSettle();

      expect(find.text('Keine Fotos vorhanden'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('Upload-Overlay nicht sichtbar beim Start', (tester) async {
      final config = await makeConfig(tester);
      final api = _stubApi(config, []);

      await tester.pumpWidget(
        wrapScreen(GalleryScreen(config: config, galleryApi: api), config),
      );
      await tester.pump();

      expect(find.text('Foto wird hochgeladen…'), findsNothing);
    });
  });
}

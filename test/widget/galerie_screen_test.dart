import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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

GalleryApi _slowUploadApi(AppConfig config, Completer<void> uploadCompleter) {
  final client = MockClient((request) async {
    if (request.method == 'POST') {
      await uploadCompleter.future;
      return http.Response('{}', 200);
    }
    return http.Response('[]', 200);
  });
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

    testWidgets('Upload-Overlay sichtbar während des Uploads', (tester) async {
      final config = await makeConfig(tester);
      final completer = Completer<void>();
      final api = _slowUploadApi(config, completer);

      await tester.pumpWidget(
        wrapScreen(GalleryScreen(config: config, galleryApi: api), config),
      );
      await tester.pumpAndSettle();

      // Trigger upload directly without image_picker — do not await so upload stays in flight
      final state = tester.state<State<GalleryScreen>>(find.byType(GalleryScreen));
      // ignore: avoid_dynamic_calls
      unawaited((state as dynamic).doUpload(
        Uint8List.fromList([1, 2, 3]),
        'test.jpg',
      ));
      await tester.pump();

      expect(find.text('Foto wird hochgeladen…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();

      expect(find.text('Foto wird hochgeladen…'), findsNothing);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/logic/documents_logic.dart';

void main() {
  group('groupDocuments', () {
    test('leere Liste → leere Map', () {
      expect(groupDocuments([]), isEmpty);
    });

    test('Datei ohne "/" → Kategorie leer, Name unverändert', () {
      final result = groupDocuments([
        {'name': 'datei.pdf'}
      ]);
      expect(result.keys, contains(''));
      expect(result['']!, contains('datei.pdf'));
    });

    test("'Protokolle/file.pdf' → Kategorie 'Protokolle', Name 'file.pdf'", () {
      final result = groupDocuments([
        {'name': 'Protokolle/file.pdf'}
      ]);
      expect(result.keys, contains('Protokolle'));
      expect(result['Protokolle']!, contains('file.pdf'));
    });

    test('benannte Kategorien alphabetisch sortiert', () {
      final result = groupDocuments([
        {'name': 'Zeugnisse/z.pdf'},
        {'name': 'Anträge/a.pdf'},
        {'name': 'Protokolle/p.pdf'},
      ]);
      final keys = result.keys.toList();
      expect(keys, ['Anträge', 'Protokolle', 'Zeugnisse']);
    });

    test("'' kommt nach benannten Kategorien", () {
      final result = groupDocuments([
        {'name': 'allgemein.pdf'},
        {'name': 'Protokolle/p.pdf'},
      ]);
      final keys = result.keys.toList();
      expect(keys.last, '');
      expect(keys.first, 'Protokolle');
    });

    test('Dateien innerhalb einer Kategorie alphabetisch sortiert', () {
      final result = groupDocuments([
        {'name': 'Protokolle/z.pdf'},
        {'name': 'Protokolle/a.pdf'},
        {'name': 'Protokolle/m.pdf'},
      ]);
      expect(result['Protokolle'], ['a.pdf', 'm.pdf', 'z.pdf']);
    });
  });

  group('fullDocumentName', () {
    test("leere Kategorie → nur Name", () {
      expect(fullDocumentName('', 'file.pdf'), 'file.pdf');
    });

    test("mit Kategorie → 'Kategorie/Name'", () {
      expect(fullDocumentName('Protokolle', 'file.pdf'), 'Protokolle/file.pdf');
    });
  });
}

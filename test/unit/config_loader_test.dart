import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vereinsappell/config_loader.dart';

Future<void> withStubHttp(Future<void> Function() body) {
  final client = MockClient((_) async => http.Response('{}', 200));
  return http.runWithClient(body, () => client);
}

AppConfig _makeConfig() => AppConfig(
      apiBaseUrl: 'https://api.example.com',
      applicationId: 'app-1',
      memberId: 'mem-1',
    );

void main() {
  group('AppConfig.fromJson', () {
    test('setzt alle Pflichtfelder', () async {
      await withStubHttp(() async {
        final config = AppConfig.fromJson({
          'apiBaseUrl': 'https://api.example.com',
          'applicationId': 'app-1',
          'memberId': 'mem-1',
          'password': 'geheim',
        });
        expect(config.apiBaseUrl, 'https://api.example.com');
        expect(config.applicationId, 'app-1');
        expect(config.memberId, 'mem-1');
        expect(config.sessionPassword, 'geheim');
      });
    });

    test('ohne password → sessionPassword == null', () async {
      await withStubHttp(() async {
        final config = AppConfig.fromJson({
          'apiBaseUrl': 'https://api.example.com',
          'applicationId': 'app-1',
          'memberId': 'mem-1',
        });
        expect(config.sessionPassword, isNull);
      });
    });
  });

  group('AppConfig.toJson', () {
    test('roundtrip', () async {
      await withStubHttp(() async {
        final config = AppConfig(
          apiBaseUrl: 'https://api.example.com',
          applicationId: 'app-1',
          memberId: 'mem-1',
          sessionPassword: 'pw',
        );
        final json = config.toJson();
        expect(json['apiBaseUrl'], 'https://api.example.com');
        expect(json['applicationId'], 'app-1');
        expect(json['memberId'], 'mem-1');
        expect(json['password'], 'pw');
      });
    });

    test("enthält keinen 'password'-Key wenn sessionPassword == null", () async {
      await withStubHttp(() async {
        final config = AppConfig(
          apiBaseUrl: 'https://api.example.com',
          applicationId: 'app-1',
          memberId: 'mem-1',
        );
        expect(config.toJson().containsKey('password'), isFalse);
      });
    });
  });

  group('Member', () {
    test('updateMember(null) → alle Felder leer/false, keine Exception',
        () async {
      await withStubHttp(() async {
        final config = _makeConfig();
        expect(() => config.member.updateMember(null), returnsNormally);
        expect(config.member.name, '');
        expect(config.member.isAdmin, isFalse);
        expect(config.member.isSpiess, isFalse);
      });
    });

    test('encodeMember() gibt valides JSON mit allen Pflichtfeldern zurück',
        () async {
      await withStubHttp(() async {
        final config = _makeConfig();
        config.member.updateMember({
          'name': 'Max',
          'isAdmin': true,
          'isSpiess': false,
          'token': 'tok',
        });
        final encoded = config.member.encodeMember();
        final decoded = jsonDecode(encoded) as Map<String, dynamic>;
        expect(decoded['name'], 'Max');
        expect(decoded['memberId'], 'mem-1');
        expect(decoded.containsKey('isAdmin'), isTrue);
        expect(decoded.containsKey('isSpiess'), isTrue);
      });
    });
  });
}

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

    test('updateMember sets reminderEnabled from JSON', () async {
      await withStubHttp(() async {
        final config = AppConfig(
          apiBaseUrl: 'http://x', applicationId: 'a', memberId: 'm',
        );
        config.member.updateMember({'reminderEnabled': false, 'reminderHoursBefore': 6});
        expect(config.member.reminderEnabled, false);
        expect(config.member.reminderHoursBefore, 6);
      });
    });

    test('updateMember uses defaults when reminder fields absent', () async {
      await withStubHttp(() async {
        final config = AppConfig(
          apiBaseUrl: 'http://x', applicationId: 'a', memberId: 'm',
        );
        config.member.updateMember({'name': 'X'});
        expect(config.member.reminderEnabled, true);
        expect(config.member.reminderHoursBefore, 24);
      });
    });

    test('encodeMember includes reminderEnabled and reminderHoursBefore', () async {
      await withStubHttp(() async {
        final config = AppConfig(
          apiBaseUrl: 'http://x', applicationId: 'a', memberId: 'm',
        );
        config.member.updateMember({'reminderEnabled': false, 'reminderHoursBefore': 48});
        final json = jsonDecode(config.member.encodeMember());
        expect(json['reminderEnabled'], false);
        expect(json['reminderHoursBefore'], 48);
      });
    });

    test('isSaftschubse defaults to false when absent', () async {
      await withStubHttp(() async {
        final config = _makeConfig();
        config.member.updateMember({'name': 'Max'});
        expect(config.member.isSaftschubse, isFalse);
      });
    });

    test('isSaftschubse is set from JSON', () async {
      await withStubHttp(() async {
        final config = _makeConfig();
        config.member.updateMember({'name': 'Max', 'isSaftschubse': true});
        expect(config.member.isSaftschubse, isTrue);
      });
    });

    test('encodeMember includes isSaftschubse', () async {
      await withStubHttp(() async {
        final config = _makeConfig();
        config.member.updateMember({'name': 'Max', 'isSaftschubse': true});
        final decoded = jsonDecode(config.member.encodeMember()) as Map<String, dynamic>;
        expect(decoded['isSaftschubse'], isTrue);
      });
    });
  });

  group('AppConfig label', () {
    test('fromJson reads label field', () async {
      await withStubHttp(() async {
        final config = AppConfig.fromJson({
          'apiBaseUrl': 'https://api.example.com',
          'applicationId': 'app-1',
          'memberId': 'mem-1',
          'label': 'Schützenlust',
        });
        expect(config.label, 'Schützenlust');
      });
    });

    test('fromJson defaults label to empty string when absent', () async {
      await withStubHttp(() async {
        final config = AppConfig.fromJson({
          'apiBaseUrl': 'https://api.example.com',
          'applicationId': 'app-1',
          'memberId': 'mem-1',
        });
        expect(config.label, '');
      });
    });

    test('toJson includes label', () async {
      await withStubHttp(() async {
        final config = AppConfig(
          apiBaseUrl: 'https://api.example.com',
          applicationId: 'app-1',
          memberId: 'mem-1',
          label: 'Schützenlust',
        );
        expect(config.toJson()['label'], 'Schützenlust');
      });
    });
  });

  group('accountIndexOf', () {
    test('returns index of matching account', () async {
      await withStubHttp(() async {
        final accounts = [
          {'applicationId': 'app-1', 'memberId': 'mem-1'},
          {'applicationId': 'app-2', 'memberId': 'mem-1'},
        ];
        expect(accountIndexOf(accounts, 'app-2', 'mem-1'), 1);
      });
    });

    test('returns -1 when applicationId matches but memberId differs', () async {
      await withStubHttp(() async {
        final accounts = [
          {'applicationId': 'app-1', 'memberId': 'mem-1'},
        ];
        expect(accountIndexOf(accounts, 'app-1', 'mem-999'), -1);
      });
    });

    test('returns -1 when no match', () async {
      await withStubHttp(() async {
        final accounts = <Map<String, dynamic>>[];
        expect(accountIndexOf(accounts, 'app-x', 'mem-x'), -1);
      });
    });
  });
}

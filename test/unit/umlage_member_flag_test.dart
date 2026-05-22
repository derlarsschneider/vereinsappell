import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/config_loader.dart';

void main() {
  test('Member.updateMember parses isGeldeintreiber true', () {
    final config = AppConfig(
      apiBaseUrl: 'https://api.example.com',
      applicationId: 'test-app',
      memberId: 'user-1',
    );
    config.member.updateMember({'isGeldeintreiber': true});
    expect(config.member.isGeldeintreiber, isTrue);
  });

  test('Member.updateMember defaults isGeldeintreiber to false', () {
    final config = AppConfig(
      apiBaseUrl: 'https://api.example.com',
      applicationId: 'test-app',
      memberId: 'user-1',
    );
    config.member.updateMember({});
    expect(config.member.isGeldeintreiber, isFalse);
  });

  test('Member.encodeMember includes isGeldeintreiber', () {
    final config = AppConfig(
      apiBaseUrl: 'https://api.example.com',
      applicationId: 'test-app',
      memberId: 'user-1',
    );
    config.member.updateMember({'isGeldeintreiber': true});
    final encoded = config.member.encodeMember();
    expect(encoded, contains('"isGeldeintreiber":true'));
  });
}

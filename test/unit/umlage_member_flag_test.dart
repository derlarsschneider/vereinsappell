import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/config_loader.dart';

void main() {
  test('Member.updateMember parses isUmlageneinsammler true', () {
    final config = AppConfig(
      apiBaseUrl: 'https://api.example.com',
      applicationId: 'test-app',
      memberId: 'user-1',
    );
    config.member.updateMember({'isUmlageneinsammler': true});
    expect(config.member.isUmlageneinsammler, isTrue);
  });

  test('Member.updateMember defaults isUmlageneinsammler to false', () {
    final config = AppConfig(
      apiBaseUrl: 'https://api.example.com',
      applicationId: 'test-app',
      memberId: 'user-1',
    );
    config.member.updateMember({});
    expect(config.member.isUmlageneinsammler, isFalse);
  });

  test('Member.encodeMember includes isUmlageneinsammler', () {
    final config = AppConfig(
      apiBaseUrl: 'https://api.example.com',
      applicationId: 'test-app',
      memberId: 'user-1',
    );
    config.member.updateMember({'isUmlageneinsammler': true});
    final encoded = config.member.encodeMember();
    expect(encoded, contains('"isUmlageneinsammler":true'));
  });
}

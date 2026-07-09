import 'package:singcast/domain/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClashConfig', () {
    test('defaults factory has mixedPort 7890', () {
      final config = ClashConfig.defaults();
      expect(config.mixedPort, 7890);
      expect(config.allowLan, isNull);
      expect(config.mode, isNull);
      expect(config.logLevel, isNull);
      expect(config.ipv6, isNull);
      expect(config.tun, isNull);
    });

    test('tunEnabled returns false when tun is null', () {
      expect(ClashConfig().tunEnabled, false);
    });

    test('tunEnabled returns false when tun.enable is null', () {
      expect(ClashConfig(tun: TunConfig()).tunEnabled, false);
    });

    test('tunEnabled returns true when tun.enable is true', () {
      expect(ClashConfig(tun: TunConfig(enable: true)).tunEnabled, true);
    });

    test('tunEnabled returns false when tun.enable is false', () {
      expect(ClashConfig(tun: TunConfig(enable: false)).tunEnabled, false);
    });
  });
}

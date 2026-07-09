import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/services/core_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('updateClashConfig', () {
    test('updates single field while preserving others', () {
      clashConfig.value = ClashConfig(
        mixedPort: 7890,
        allowLan: true,
        mode: Mode.rule,
        logLevel: LogLevel.info,
        ipv6: false,
        tun: TunConfig(enable: false),
      );

      updateClashConfig(mixedPort: 9090);

      expect(clashConfig.value.mixedPort, 9090);
      expect(clashConfig.value.allowLan, true);
      expect(clashConfig.value.mode, Mode.rule);
      expect(clashConfig.value.logLevel, LogLevel.info);
      expect(clashConfig.value.ipv6, false);
    });

    test('updates mode', () {
      clashConfig.value = ClashConfig(mixedPort: 7890, mode: Mode.rule);

      updateClashConfig(mode: Mode.global);

      expect(clashConfig.value.mode, Mode.global);
      expect(clashConfig.value.mixedPort, 7890);
    });

    test('updates log level', () {
      clashConfig.value = ClashConfig(logLevel: LogLevel.info);

      updateClashConfig(logLevel: LogLevel.debug);

      expect(clashConfig.value.logLevel, LogLevel.debug);
    });

    test('updates boolean fields', () {
      clashConfig.value = ClashConfig(allowLan: false, ipv6: false);

      updateClashConfig(allowLan: true, ipv6: true);

      expect(clashConfig.value.allowLan, true);
      expect(clashConfig.value.ipv6, true);
    });

    test('updates multiple fields at once', () {
      clashConfig.value = ClashConfig(
        mixedPort: 7890,
        mode: Mode.rule,
        logLevel: LogLevel.info,
      );

      updateClashConfig(
        mixedPort: 8080,
        mode: Mode.direct,
        logLevel: LogLevel.error,
      );

      expect(clashConfig.value.mixedPort, 8080);
      expect(clashConfig.value.mode, Mode.direct);
      expect(clashConfig.value.logLevel, LogLevel.error);
    });

    test('preserves tun config when updating other fields', () {
      clashConfig.value = ClashConfig(
        mixedPort: 7890,
        tun: TunConfig(enable: true),
      );

      updateClashConfig(mixedPort: 9090);

      expect(clashConfig.value.tun?.enable, true);
    });

    test('no arguments preserves all values', () {
      clashConfig.value = ClashConfig(
        mixedPort: 7890,
        mode: Mode.global,
        logLevel: LogLevel.warning,
      );

      updateClashConfig();

      expect(clashConfig.value.mixedPort, 7890);
      expect(clashConfig.value.mode, Mode.global);
      expect(clashConfig.value.logLevel, LogLevel.warning);
    });

    test('tunEnabled reflects tun config changes', () {
      clashConfig.value = ClashConfig(tun: TunConfig(enable: false));
      expect(clashConfig.value.tunEnabled, false);

      clashConfig.value = ClashConfig(tun: TunConfig(enable: true));
      expect(clashConfig.value.tunEnabled, true);
    });

  });
}

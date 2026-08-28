import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/services/core_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('updateCoreConfig', () {
    test('updates single field while preserving others', () {
      coreConfig.value = SingboxConfig(
        mixedPort: 7890,
        allowLan: true,
        mode: Mode.rule,
        logLevel: LogLevel.info,
        ipv6: false,
        tun: TunConfig(enable: false),
      );

      updateCoreConfig(mixedPort: 9090);

      expect(coreConfig.value.mixedPort, 9090);
      expect(coreConfig.value.allowLan, true);
      expect(coreConfig.value.mode, Mode.rule);
      expect(coreConfig.value.logLevel, LogLevel.info);
      expect(coreConfig.value.ipv6, false);
    });

    test('updates mode', () {
      coreConfig.value = SingboxConfig(mixedPort: 7890, mode: Mode.rule);

      updateCoreConfig(mode: Mode.global);

      expect(coreConfig.value.mode, Mode.global);
      expect(coreConfig.value.mixedPort, 7890);
    });

    test('updates log level', () {
      coreConfig.value = SingboxConfig(logLevel: LogLevel.info);

      updateCoreConfig(logLevel: LogLevel.debug);

      expect(coreConfig.value.logLevel, LogLevel.debug);
    });

    test('updates boolean fields', () {
      coreConfig.value = SingboxConfig(allowLan: false, ipv6: false);

      updateCoreConfig(allowLan: true, ipv6: true);

      expect(coreConfig.value.allowLan, true);
      expect(coreConfig.value.ipv6, true);
    });

    test('updates multiple fields at once', () {
      coreConfig.value = SingboxConfig(
        mixedPort: 7890,
        mode: Mode.rule,
        logLevel: LogLevel.info,
      );

      updateCoreConfig(
        mixedPort: 8080,
        mode: Mode.direct,
        logLevel: LogLevel.error,
      );

      expect(coreConfig.value.mixedPort, 8080);
      expect(coreConfig.value.mode, Mode.direct);
      expect(coreConfig.value.logLevel, LogLevel.error);
    });

    test('preserves tun config when updating other fields', () {
      coreConfig.value = SingboxConfig(
        mixedPort: 7890,
        tun: TunConfig(enable: true),
      );

      updateCoreConfig(mixedPort: 9090);

      expect(coreConfig.value.tun?.enable, true);
    });

    test('no arguments preserves all values', () {
      coreConfig.value = SingboxConfig(
        mixedPort: 7890,
        mode: Mode.global,
        logLevel: LogLevel.warning,
      );

      updateCoreConfig();

      expect(coreConfig.value.mixedPort, 7890);
      expect(coreConfig.value.mode, Mode.global);
      expect(coreConfig.value.logLevel, LogLevel.warning);
    });

    test('tunEnabled reflects tun config changes', () {
      coreConfig.value = SingboxConfig(tun: TunConfig(enable: false));
      expect(coreConfig.value.tunEnabled, false);

      coreConfig.value = SingboxConfig(tun: TunConfig(enable: true));
      expect(coreConfig.value.tunEnabled, true);
    });
  });
}

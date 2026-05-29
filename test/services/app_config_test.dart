import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/services/core_config.dart';
import 'package:flutter_test/flutter_test.dart';

const _profileWithTun = '''
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: false
tun:
  enable: true
  stack: system
  auto-route: true
  strict-route: true
  dns-hijack:
    - any:53
external-controller: 127.0.0.1:9090
dns:
  enable: true
''';

const _profileWithoutTun = '''
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: false
external-controller: 127.0.0.1:9090
dns:
  enable: true
''';

void main() {
  group('mergeProfileConfig tun removal', () {
    test('removes tun section when tun.enable is false', () {
      clashConfig.value = ClashConfig(
        mixedPort: 7890,
        mode: Mode.rule,
        logLevel: LogLevel.info,
        tun: TunConfig(enable: false),
        portEnabled: true,
      );

      final result = mergeProfileConfig(_profileWithTun);

      expect(result.contains('tun:'), isFalse);
      expect(result.contains('auto-route'), isFalse);
      expect(result.contains('dns-hijack'), isFalse);
      expect(result.contains('mixed-port'), isTrue);
    });

    test('preserves tun section when tun.enable is true', () {
      clashConfig.value = ClashConfig(
        mixedPort: 7890,
        mode: Mode.rule,
        logLevel: LogLevel.info,
        tun: TunConfig(enable: true),
      );

      final result = mergeProfileConfig(_profileWithTun);

      expect(result.contains('tun:'), isTrue);
      expect(result.contains('enable: true'), isTrue);
    });

    test('adds tun section when source has none and tun.enable is true', () {
      clashConfig.value = ClashConfig(
        mixedPort: 7890,
        mode: Mode.rule,
        logLevel: LogLevel.info,
        tun: TunConfig(enable: true),
      );

      final result = mergeProfileConfig(_profileWithoutTun);

      expect(result.contains('tun:'), isTrue);
      expect(result.contains('enable: true'), isTrue);
    });

    test('removes tun section when config has no tun override', () {
      clashConfig.value = ClashConfig(
        mixedPort: 7890,
        mode: Mode.rule,
        logLevel: LogLevel.info,
      );

      final result = mergeProfileConfig(_profileWithTun);

      // TUN is app-managed — always stripped when not explicitly enabled
      expect(result.contains('tun:'), isFalse);
      expect(result.contains('auto-route'), isFalse);
      expect(result.contains('dns-hijack'), isFalse);
    });
  });
}

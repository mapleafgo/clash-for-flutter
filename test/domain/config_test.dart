import 'dart:convert';

import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

T _roundtrip<T>(T obj, T Function(Map<String, dynamic>) fromJson,
    Map<String, dynamic> Function(T) toJson) {
  return fromJson(jsonDecode(jsonEncode(toJson(obj))) as Map<String, dynamic>);
}

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

    test('port returns mixedPort value', () {
      expect(ClashConfig(mixedPort: 9090).port, 9090);
    });

    test('port returns 0 when mixedPort is null', () {
      expect(ClashConfig().port, 0);
    });

    test('JSON roundtrip with all fields', () {
      final config = ClashConfig(
        mixedPort: 7890,
        allowLan: true,
        mode: Mode.rule,
        logLevel: LogLevel.info,
        ipv6: false,
        tun: TunConfig(enable: true),
      );
      final restored = _roundtrip(config, ClashConfig.fromJson, (c) => c.toJson());

      expect(restored.mixedPort, 7890);
      expect(restored.allowLan, true);
      expect(restored.mode, Mode.rule);
      expect(restored.logLevel, LogLevel.info);
      expect(restored.ipv6, false);
      expect(restored.tun?.enable, true);
    });

    test('JSON roundtrip with null fields', () {
      final config = ClashConfig();
      final restored = _roundtrip(config, ClashConfig.fromJson, (c) => c.toJson());

      expect(restored.mixedPort, isNull);
      expect(restored.mode, isNull);
      expect(restored.tun, isNull);
      expect(restored.tunEnabled, false);
    });

    test('fromJson parses external JSON correctly', () {
      final config = ClashConfig.fromJson({
        'mixed-port': 7890,
        'allow-lan': true,
        'mode': 'global',
        'log-level': 'debug',
        'ipv6': true,
        'tun': {'enable': true},
      });

      expect(config.mixedPort, 7890);
      expect(config.allowLan, true);
      expect(config.mode, Mode.global);
      expect(config.logLevel, LogLevel.debug);
      expect(config.ipv6, true);
      expect(config.tunEnabled, true);
    });
  });

  group('TunConfig', () {
    test('JSON roundtrip', () {
      final restored =
          _roundtrip(TunConfig(enable: true), TunConfig.fromJson, (t) => t.toJson());
      expect(restored.enable, true);
    });

    test('fromJson handles null enable', () {
      expect(TunConfig.fromJson({}).enable, isNull);
    });
  });
}

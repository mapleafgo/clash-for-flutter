import 'package:flutter_test/flutter_test.dart';
import 'package:singcast/data/local/app_settings_storage.dart';
import 'package:singcast/domain/enums.dart';

void main() {
  group('AppStoredConfig autoStart', () {
    test('fromJson 默认值为 false', () {
      final config = AppStoredConfig.fromJson({});
      expect(config.autoStart, false);
    });

    test('fromJson 正确读取 auto-start', () {
      final config = AppStoredConfig.fromJson({'auto-start': true});
      expect(config.autoStart, true);
    });

    test('toJson 在 autoStart=true 时写入 auto-start', () {
      final config = AppStoredConfig.empty().copyWith(autoStart: true);
      final json = config.toJson();
      expect(json['auto-start'], true);
    });

    test('toJson 在 autoStart=false 时省略 auto-start', () {
      final config = AppStoredConfig.empty();
      final json = config.toJson();
      expect(json.containsKey('auto-start'), false);
    });

    test('copyWith 保留原值', () {
      final config = AppStoredConfig.empty().copyWith(autoStart: true);
      final copied = config.copyWith();
      expect(copied.autoStart, true);
    });
  });

  group('AppStoredConfig tunStack', () {
    test('fromJson 默认值为 gvisor', () {
      final config = AppStoredConfig.fromJson({});
      expect(config.tunStack, TunStack.gvisor);
    });

    test('fromJson 正确读取 mixed', () {
      final config = AppStoredConfig.fromJson({'tun-stack': 'mixed'});
      expect(config.tunStack, TunStack.mixed);
    });

    test('fromJson 正确读取 system', () {
      final config = AppStoredConfig.fromJson({'tun-stack': 'system'});
      expect(config.tunStack, TunStack.system);
    });

    test('fromJson 未知值回退到 gvisor', () {
      final config = AppStoredConfig.fromJson({'tun-stack': 'unknown'});
      expect(config.tunStack, TunStack.gvisor);
    });

    test('toJson 在非默认值时写入 tun-stack', () {
      final config = AppStoredConfig.empty().copyWith(tunStack: TunStack.mixed);
      final json = config.toJson();
      expect(json['tun-stack'], 'mixed');
    });

    test('toJson 在默认 gvisor 时省略 tun-stack', () {
      final config = AppStoredConfig.empty();
      final json = config.toJson();
      expect(json.containsKey('tun-stack'), false);
    });

    test('copyWith 保留原值', () {
      final config = AppStoredConfig.empty().copyWith(tunStack: TunStack.system);
      final copied = config.copyWith();
      expect(copied.tunStack, TunStack.system);
    });
  });
}

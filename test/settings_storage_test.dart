import 'package:flutter_test/flutter_test.dart';
import 'package:singcast/data/local/app_settings_storage.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/utils/constants.dart';

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

    test('toJson 在 autoStart=false 时写入 auto-start', () {
      final config = AppStoredConfig.empty();
      final json = config.toJson();
      expect(json['auto-start'], false);
    });

    test('copyWith 保留原值', () {
      final config = AppStoredConfig.empty().copyWith(autoStart: true);
      final copied = config.copyWith();
      expect(copied.autoStart, true);
    });
  });

  group('AppStoredConfig tunStack', () {
    test('fromJson 默认值为 mixed', () {
      final config = AppStoredConfig.fromJson({});
      expect(config.tunStack, TunStack.mixed);
    });

    test('fromJson 正确读取 mixed', () {
      final config = AppStoredConfig.fromJson({'tun-stack': 'mixed'});
      expect(config.tunStack, TunStack.mixed);
    });

    test('fromJson 正确读取 system', () {
      final config = AppStoredConfig.fromJson({'tun-stack': 'system'});
      expect(config.tunStack, TunStack.system);
    });

    test('fromJson 未知值回退到 mixed', () {
      final config = AppStoredConfig.fromJson({'tun-stack': 'unknown'});
      expect(config.tunStack, TunStack.mixed);
    });

    test('toJson 在非默认值时写入 tun-stack', () {
      final config = AppStoredConfig.empty().copyWith(
        tunStack: TunStack.gvisor,
      );
      final json = config.toJson();
      expect(json['tun-stack'], 'gvisor');
    });

    test('toJson 在默认 mixed 时写入 tun-stack', () {
      final config = AppStoredConfig.empty();
      final json = config.toJson();
      expect(json['tun-stack'], 'mixed');
    });

    test('copyWith 保留原值', () {
      final config = AppStoredConfig.empty().copyWith(
        tunStack: TunStack.system,
      );
      final copied = config.copyWith();
      expect(copied.tunStack, TunStack.system);
    });
  });

  group('AppStoredConfig ruleSetProxy', () {
    test('fromJson 默认值取 Defaults.ruleSetProxy', () {
      final config = AppStoredConfig.fromJson({});
      expect(config.ruleSetProxy, Defaults.ruleSetProxy);
    });

    test('fromJson 正确读取 rule-set-proxy', () {
      final config = AppStoredConfig.fromJson({
        'rule-set-proxy': 'https://example.com',
      });
      expect(config.ruleSetProxy, 'https://example.com');
    });

    test('toJson 在非默认值时写入 rule-set-proxy', () {
      final config = AppStoredConfig.empty().copyWith(
        ruleSetProxy: 'https://example.com',
      );
      expect(config.toJson()['rule-set-proxy'], 'https://example.com');
    });

    test('toJson 在默认值时也写入 rule-set-proxy', () {
      final config = AppStoredConfig.empty();
      expect(config.toJson()['rule-set-proxy'], Defaults.ruleSetProxy);
    });

    test('toJson 在清空直连时写入空串 rule-set-proxy', () {
      final config = AppStoredConfig.empty().copyWith(ruleSetProxy: '');
      expect(config.toJson()['rule-set-proxy'], '');
    });

    test('copyWith 保留原值', () {
      final config = AppStoredConfig.empty().copyWith(
        ruleSetProxy: 'https://example.com',
      );
      final copied = config.copyWith();
      expect(copied.ruleSetProxy, 'https://example.com');
    });
  });

  group('AppStoredConfig toJson 默认配置', () {
    test('默认配置时包含全部字段', () {
      final json = AppStoredConfig.empty().toJson();
      expect(json.containsKey('selected-file'), true);
      expect(json.containsKey('profiles'), true);
      expect(json['delay-test-url'], Defaults.delayTestUrl);
      expect(json.containsKey('tun-if'), true);
      expect(json['sub-ua'], Defaults.subUA);
      expect(json.containsKey('theme-mode'), true);
      expect(json.containsKey('ignored-version'), true);
      expect(json['auto-check-update'], true);
      expect(json.containsKey('locale'), true);
      expect(json['auto-start'], false);
      expect(json['tun-stack'], 'mixed');
      expect(json['rule-set-proxy'], Defaults.ruleSetProxy);
    });
  });
}

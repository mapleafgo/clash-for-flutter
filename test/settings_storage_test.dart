import 'package:flutter_test/flutter_test.dart';
import 'package:singcast/data/local/app_settings_storage.dart';

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
}

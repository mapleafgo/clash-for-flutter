import 'dart:convert';

import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/services/core_config.dart';
import 'package:flutter_test/flutter_test.dart';

const _profileJson = '''
{
  "log": {"level": "debug"},
  "inbounds": [
    {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 7890}
  ],
  "outbounds": [
    {"type": "direct", "tag": "DIRECT"},
    {"type": "selector", "tag": "PROXY", "outbounds": ["DIRECT"]}
  ],
  "experimental": {
    "clash_api": {"external_controller": "127.0.0.1:9090"}
  }
}
''';

void main() {
  group('mergeProfileConfig sing-box JSON', () {
    test('overrides mixed inbound and log level', () {
      coreConfig.value = SingboxConfig(
        mixedPort: 8080,
        logLevel: LogLevel.warning,
        portEnabled: true,
      );
      final result = jsonDecode(mergeProfileConfig(_profileJson));
      final inbounds = (result['inbounds'] as List)
          .cast<Map<String, dynamic>>();
      expect(inbounds.single['listen_port'], 8080);
      expect(result['log']['level'], 'warn');
    });

    test('removes mixed inbound when port disabled', () {
      coreConfig.value = SingboxConfig(portEnabled: false);
      final result = jsonDecode(mergeProfileConfig(_profileJson));
      expect(result['inbounds'], isNull);
    });

    test('injects tun inbound with ipv6 address', () {
      coreConfig.value = SingboxConfig(
        tun: TunConfig(enable: true),
        ipv6: true,
      );
      final result = jsonDecode(mergeProfileConfig(_profileJson));
      final tun = (result['inbounds'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((e) => e['type'] == 'tun');
      expect(tun['auto_route'], true);
      expect((tun['address'] as List).length, 2);
    });

    test('injects clash_api when api enabled', () {
      coreConfig.value = SingboxConfig(
        externalController: true,
        externalControllerAddr: '127.0.0.1:9091',
        mode: Mode.global,
      );
      final result = jsonDecode(mergeProfileConfig(_profileJson));
      final api =
          (result['experimental'] as Map)['clash_api'] as Map<String, dynamic>;
      expect(api['external_controller'], '127.0.0.1:9091');
      expect(api['default_mode'], 'Global');
    });
  });
}

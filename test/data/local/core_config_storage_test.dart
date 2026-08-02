import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singcast/data/local/core_config_storage.dart';
import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/utils/constants.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('singcast-storage-test');
    Constants.homeDir = tmp;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('save/load roundtrip with sing-box keys', () {
    CoreConfigStorage.save(SingboxConfig(
      mixedPort: 8080,
      allowLan: true,
      mode: Mode.global,
      logLevel: LogLevel.warning,
      ipv6: true,
      externalController: true,
      externalControllerAddr: '127.0.0.1:9091',
      portEnabled: true,
    ));

    final raw = jsonDecode(
      File('${tmp.path}/config.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect((raw['inbounds'] as List).first['listen_port'], 8080);
    expect(raw['log']['level'], 'warn');
    expect(raw['experimental']['clash_api']['default_mode'], 'Global');
    expect(raw['dns']['strategy'], 'prefer_ipv6');

    final loaded = CoreConfigStorage.load();
    expect(loaded.mixedPort, 8080);
    expect(loaded.allowLan, true);
    expect(loaded.mode, Mode.global);
    expect(loaded.logLevel, LogLevel.warning);
    expect(loaded.ipv6, true);
    expect(loaded.portEnabled, true);
  });

  test('set_system_proxy stored natively in mixed inbound', () {
    CoreConfigStorage.save(SingboxConfig(
      mixedPort: 7890,
      systemProxy: true,
    ));
    final raw = jsonDecode(
      File('${tmp.path}/config.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    // set_system_proxy 是 sing-box 原生字段，存在 mixed inbound 中
    final inbound = (raw['inbounds'] as List).first as Map<String, dynamic>;
    expect(inbound['set_system_proxy'], isTrue);
    // 不存在自定义顶层 system_proxy
    expect(raw.containsKey('system_proxy'), isFalse);

    final loaded = CoreConfigStorage.load();
    expect(loaded.systemProxy, isTrue);
  });

  test('save with all-null sing-box fields produces no empty sections', () {
    CoreConfigStorage.save(SingboxConfig());
    final raw = jsonDecode(
      File('${tmp.path}/config.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(raw.containsKey('inbounds'), isFalse);
    expect(raw.containsKey('experimental'), isFalse);
    expect(raw.containsKey('log'), isFalse);
    expect(raw.containsKey('dns'), isFalse);
    expect(raw['port_enabled'], isFalse);
    expect(raw['api_enabled'], isFalse);
  });

  test('load returns defaults when file missing', () {
    final loaded = CoreConfigStorage.load();
    expect(loaded.mixedPort, isNull);
    expect(loaded.portEnabled, isNull);
  });

  test('createDefault writes config.json', () {
    CoreConfigStorage.createDefault();
    expect(File('${tmp.path}/config.json').existsSync(), isTrue);
  });

  test('createDefault skips when config.yaml exists', () {
    File('${tmp.path}/config.yaml').writeAsStringSync('mixed-port: 1\n');
    CoreConfigStorage.createDefault();
    expect(File('${tmp.path}/config.json').existsSync(), isFalse);
  });
}

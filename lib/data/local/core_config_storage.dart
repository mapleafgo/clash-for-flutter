import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/utils/constants.dart';
import 'package:settings_yaml/settings_yaml.dart';

class CoreConfigStorage {
  static String get _path =>
      p.join(Constants.homeDir.path, Constants.clashConfig);

  static bool exists() => File(_path).existsSync();

  static ClashConfig load() {
    try {
      final yaml = SettingsYaml.load(pathToSettings: _path);
      return ClashConfig(
        mixedPort: yaml['mixed-port'] as int?,
        allowLan: yaml['allow-lan'] as bool?,
        // mode 必须持久化：内核消费配置的 mode 字段作为 default_mode（启动初始模式），
        // 但内核运行时 SetMode 不写回配置文件，所以持久化由 Flutter 侧负责。
        mode: _parseEnum(yaml['mode'], Mode.values),
        logLevel: _parseEnum(yaml['log-level'], LogLevel.values),
        ipv6: yaml['ipv6'] as bool?,
        externalController: yaml['external-controller'] as bool?,
        externalControllerAddr: yaml['external-controller-addr'] as String?,
        portEnabled: yaml['port-enabled'] as bool?,
        mixedSystemProxy: yaml['mixed-system-proxy'] as bool?,
      );
    } catch (_) {
      return ClashConfig();
    }
  }

  static void save(ClashConfig config) {
    final yaml = SettingsYaml.load(pathToSettings: _path);
    if (config.mixedPort != null) yaml['mixed-port'] = config.mixedPort;
    if (config.allowLan != null) yaml['allow-lan'] = config.allowLan;
    if (config.mode != null) yaml['mode'] = config.mode!.name;
    if (config.logLevel != null) yaml['log-level'] = config.logLevel!.name;
    if (config.ipv6 != null) yaml['ipv6'] = config.ipv6;
    if (config.externalController != null) yaml['external-controller'] = config.externalController;
    if (config.externalControllerAddr != null) yaml['external-controller-addr'] = config.externalControllerAddr;
    if (config.portEnabled != null) yaml['port-enabled'] = config.portEnabled;
    if (config.mixedSystemProxy != null) yaml['mixed-system-proxy'] = config.mixedSystemProxy;
    yaml.save();
  }

  /// 将字符串解析为枚举值，无法匹配时返回 null。
  static T? _parseEnum<T extends Enum>(dynamic value, List<T> values) {
    if (value is! String) return null;
    return values.where((e) => e.name == value).firstOrNull;
  }

  static void createDefault() {
    final file = File(_path);
    // 仅在配置文件不存在时写入默认值。
    // writeAsStringSync 默认 FileMode.write 是覆盖写法，若不加守卫会清空
    // 用户已保存的内核配置，导致每次启动配置"丢失"。
    if (file.existsSync()) return;
    try {
      file.writeAsStringSync('mixed-port: ${Constants.defaultMixedPort}\n');
    } on FileSystemException catch (_) {
      // 目录不可写或并发创建时忽略
    }
  }
}
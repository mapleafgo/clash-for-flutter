import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';

class CoreConfigStorage {
  static String get _path =>
      p.join(Constants.homeDir.path, Constants.coreConfigFile);

  static bool exists() => File(_path).existsSync();

  static SingboxConfig load() {
    try {
      final file = File(_path);
      if (!file.existsSync()) return SingboxConfig();
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final inbound = _mixedInbound(json);
      final clashApi =
          (json['experimental'] as Map<String, dynamic>?)?['clash_api']
              as Map<String, dynamic>?;
      final dns = json['dns'] as Map<String, dynamic>?;
      return SingboxConfig(
        mixedPort: (inbound?['listen_port'] as num?)?.toInt(),
        allowLan: inbound != null && inbound['listen'] != '127.0.0.1',
        mode: _parseEnum(
          (clashApi?['default_mode'] as String?)?.toLowerCase(),
          Mode.values,
        ),
        logLevel: _parseEnum(_logLevelName(json), LogLevel.values),
        ipv6: dns?['strategy'] == null
            ? null
            : dns!['strategy'] == 'prefer_ipv6',
        externalController: json['api_enabled'] as bool?,
        externalControllerAddr:
            clashApi?['external_controller'] as String?,
        portEnabled: json['port_enabled'] as bool?,
        systemProxy: (inbound?['set_system_proxy'] as bool?) ?? false,
      );
    } catch (e) {
      LogFileWriter.instance?.log(
        'Failed to load core config, using defaults: $e',
        level: LogLevel.warning,
        name: 'settings',
      );
      return SingboxConfig();
    }
  }

  static void save(SingboxConfig config) {
    final json = <String, dynamic>{};

    // sing-box 字段：仅在有值时写入
    if (config.logLevel != null) {
      json['log'] = {'level': _singboxLogLevel(config.logLevel!)};
    }
    // mixed inbound：有端口或开了系统代理时写入（系统代理依赖端口）
    if (config.mixedPort != null || config.systemProxy == true) {
      final inbound = <String, dynamic>{
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': config.allowLan == true ? '0.0.0.0' : '127.0.0.1',
        'listen_port': config.mixedPort ?? Constants.defaultMixedPort,
      };
      if (config.systemProxy == true) {
        inbound['set_system_proxy'] = true;
      }
      json['inbounds'] = [
        inbound,
      ];
    }
    // clash_api：仅在 API 开启时写入，与 mergeProfileConfig 下发逻辑一致
    if (config.apiEnabled) {
      final clashApi = <String, dynamic>{};
      if (config.mode != null) {
        clashApi['default_mode'] = _modeName(config.mode!);
      }
      clashApi['external_controller'] = config.apiAddr;
      json['experimental'] = {'clash_api': clashApi};
    }
    if (config.ipv6 != null) {
      json['dns'] = {'strategy': config.ipv6! ? 'prefer_ipv6' : 'ipv4_only'};
    }

    // 应用级开关（非 sing-box 字段，顶层存储）
    json['port_enabled'] = config.portEnabled ?? false;
    json['api_enabled'] = config.externalController ?? false;

    File(_path)
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  }

  static void createDefault() {
    final file = File(_path);
    if (file.existsSync()) return;
    // 旧版标记存在时交给迁移入口处理，避免抢先创建 config.json
    if (File(p.join(Constants.homeDir.path, 'config.yaml')).existsSync()) {
      return;
    }
    try {
      file.writeAsStringSync(jsonEncode({
        'port_enabled': false,
        'api_enabled': false,
      }));
    } on FileSystemException catch (_) {}
  }

  static Map<String, dynamic>? _mixedInbound(Map<String, dynamic> json) {
    final list = json['inbounds'] as List?;
    if (list == null) return null;
    for (final item in list) {
      if (item is Map<String, dynamic> && item['type'] == 'mixed') {
        return item;
      }
    }
    return null;
  }

  static String? _logLevelName(Map<String, dynamic> json) {
    final log = json['log'] as Map<String, dynamic>?;
    final level = log?['level'] as String?;
    if (level == 'warn') return 'warning';
    return level;
  }

  static String _singboxLogLevel(LogLevel level) =>
      level == LogLevel.warning ? 'warn' : level.name;

  static String _modeName(Mode mode) =>
      mode.name[0].toUpperCase() + mode.name.substring(1);

  static T? _parseEnum<T extends Enum>(dynamic value, List<T> values) {
    if (value is! String) return null;
    return values.where((e) => e.name == value).firstOrNull;
  }
}

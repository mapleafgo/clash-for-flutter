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
        mode: null,
        logLevel: _parseLogLevel(yaml['log-level']),
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

  static LogLevel? _parseLogLevel(dynamic value) {
    if (value is! String) return null;
    return LogLevel.values.where((l) => l.name == value).firstOrNull;
  }

  static void createDefault() {
    try {
      File(_path).writeAsStringSync('mixed-port: 7890\n');
    } on FileSystemException catch (_) {
      // File may already exist from another instance — safe to ignore
    }
  }
}
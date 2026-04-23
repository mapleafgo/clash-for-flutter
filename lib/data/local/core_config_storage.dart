import 'dart:io';

import 'package:clash_for_flutter/domain/config.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:settings_yaml/settings_yaml.dart';

class CoreConfigStorage {
  static final _path =
      '${Constants.homeDir.path}${Constants.clashConfig}';

  static bool exists() => File(_path).existsSync();

  static ClashConfig load() {
    final yaml = SettingsYaml.load(pathToSettings: _path);
    return ClashConfig(
      mixedPort: yaml['mixed-port'] as int?,
      redirPort: yaml['redir-port'] as int?,
      tproxyPort: yaml['tproxy-port'] as int?,
      allowLan: yaml['allow-lan'] as bool?,
      mode: null,
      logLevel: null,
      ipv6: yaml['ipv6'] as bool?,
    );
  }

  static void save(ClashConfig config) {
    final yaml = SettingsYaml.load(pathToSettings: _path);
    if (config.mixedPort != null) yaml['mixed-port'] = config.mixedPort;
    if (config.redirPort != null) yaml['redir-port'] = config.redirPort;
    if (config.tproxyPort != null) yaml['tproxy-port'] = config.tproxyPort;
    if (config.allowLan != null) yaml['allow-lan'] = config.allowLan;
    if (config.mode != null) yaml['mode'] = config.mode!.name;
    if (config.logLevel != null) yaml['log-level'] = config.logLevel!.name;
    if (config.ipv6 != null) yaml['ipv6'] = config.ipv6;
    yaml.save();
  }

  static void createDefault() {
    if (!exists()) {
      File(_path).createSync(recursive: true);
      File(_path).writeAsStringSync('mixed-port: 7890\n');
    }
  }
}
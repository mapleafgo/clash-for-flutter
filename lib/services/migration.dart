import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/data/local/app_settings_storage.dart';
import 'package:singcast/data/local/core_config_storage.dart';
import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/profile.dart';
import 'package:singcast/services/subscription.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';
import 'package:yaml/yaml.dart';

/// 旧版（Clash YAML 时代）统一迁移入口。
///
/// 以 `config.yaml` 是否存在作为迁移标记：存在才执行；全部迁移成功后删除标记，
/// 任一设置/订阅迁移失败时保留标记，下次启动重试。异常不阻塞启动。
Future<void> migrateLegacy({
  Future<String> Function(String content)? convert,
  Future<void> Function(String filePath)? validate,
}) async {
  final legacyConfig = File(p.join(Constants.homeDir.path, 'config.yaml'));
  if (!legacyConfig.existsSync()) return;

  final converter = convert ?? (content) => LibCore.instance.convert(content);
  final validator = validate ?? validateConfigFile;

  var failed = false;
  final sw = Stopwatch()..start();
  var yamlTotal = 0;
  var yamlConverted = 0;
  var yamlFailed = 0;

  // 1. 设置存储：旧 yaml → config.json
  try {
    final legacy = _loadLegacyConfig();
    if (legacy != null) {
      CoreConfigStorage.save(legacy);
      LogFileWriter.instance?.log(
        'migrate core config: config.yaml → config.json',
        name: 'migrate',
      );
    } else {
      LogFileWriter.instance?.log(
        'migrate core config: config.yaml parse returned null',
        level: LogLevel.warning,
        name: 'migrate',
      );
      failed = true;
    }
  } catch (e) {
    LogFileWriter.instance?.log(
      'migrate core config failed: $e',
      level: LogLevel.warning,
      name: 'migrate',
    );
    failed = true;
  }

  // 2. 订阅：URL 型与文件型统一走本地文件转换，迁移期不重新拉取
  final stored = AppSettingsStorage.load();
  final storedConfig = AppStoredConfig.fromJson(stored);
  final dir = Directory(p.join(Constants.homeDir.path, Constants.profilesDir));
  final migrated = <Profile>[];
  var changed = false;
  for (final profile in storedConfig.profiles) {
    if (!profile.file.endsWith('.yaml') && !profile.file.endsWith('.yml')) {
      migrated.add(profile);
      continue;
    }
    yamlTotal++;
    final path = p.join(dir.path, profile.file);
    if (!File(path).existsSync()) {
      migrated.add(profile);
      continue;
    }
    try {
      final next = await _convertLocalFile(
        dir: dir,
        profile: profile,
        converter: converter,
        validator: validator,
      );
      await File(path).delete();
      migrated.add(next);
      changed = true;
      yamlConverted++;
    } catch (e) {
      LogFileWriter.instance?.log(
        'legacy profile migration failed: ${profile.file}: $e',
        level: LogLevel.warning,
        name: 'migrate',
      );
      failed = true;
      yamlFailed++;
      migrated.add(profile);
    }
  }
  if (changed) {
    AppSettingsStorage.save(storedConfig.copyWith(profiles: migrated).toJson());
  }

  LogFileWriter.instance?.log(
    'migrate profiles: $yamlTotal yaml, $yamlConverted converted, '
    '$yamlFailed failed in ${sw.elapsedMilliseconds}ms, '
    'marker ${failed ? "kept" : "deleted"}',
    name: 'migrate',
  );

  // 3. 完成标记：全部成功才删除，失败保留以便下次启动重试
  if (!failed) {
    try {
      await legacyConfig.delete();
    } catch (e) {
      LogFileWriter.instance?.log(
        'delete legacy config.yaml marker failed: $e',
        level: LogLevel.warning,
        name: 'migrate',
      );
    }
  }
}

Future<Profile> _convertLocalFile({
  required Directory dir,
  required Profile profile,
  required Future<String> Function(String content) converter,
  required Future<void> Function(String filePath) validator,
}) async {
  final content = await File(p.join(dir.path, profile.file)).readAsString();
  final jsonContent = await converter(content);
  final file = uniqueProfileFileName();
  await File(p.join(dir.path, file)).writeAsString(jsonContent);
  await validator(p.join(dir.path, file));
  return Profile(
    file: file,
    name: profile.name,
    type: profile.type,
    time: DateTime.now(),
    url: profile.url,
    interval: profile.interval,
    userinfo: profile.userinfo,
  );
}

SingboxConfig? _loadLegacyConfig() {
  try {
    final path = p.join(Constants.homeDir.path, 'config.yaml');
    final doc = loadYaml(File(path).readAsStringSync()) as Map;
    T? val<T>(String key) => doc[key] as T?;
    final modeStr = val<String>('mode');
    final logStr = val<String>('log-level');
    return SingboxConfig(
      mixedPort: val<int>('mixed-port'),
      allowLan: val<bool>('allow-lan'),
      mode: modeStr == null
          ? null
          : Mode.values.where((e) => e.name == modeStr).firstOrNull,
      logLevel: logStr == null
          ? null
          : LogLevel.values.where((e) => e.name == logStr).firstOrNull,
      ipv6: val<bool>('ipv6'),
      externalController: val<bool>('external-controller'),
      externalControllerAddr: val<String>('external-controller-addr'),
      portEnabled: val<bool>('port-enabled'),
      systemProxy: val<bool>('mixed-system-proxy'),
    );
  } catch (e) {
    LogFileWriter.instance?.log(
      'read legacy config.yaml failed: $e',
      level: LogLevel.warning,
      name: 'migrate',
    );
    return null;
  }
}

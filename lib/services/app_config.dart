import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/data/local/app_settings_storage.dart';
import 'package:singcast/domain/profile.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';
import 'package:singcast/domain/enums.dart';
import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';
import 'package:singcast/services/subscription.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

final selectedFile = signal<String?>(null);
final profiles = signal<List<Profile>>([]);
final profileError = signal<String?>(null);
final delayTestUrl = signal(Defaults.delayTestUrl);
final tunIf = signal<bool?>(null);
final subUA = signal(Defaults.subUA);
final ruleSetProxy = signal(Defaults.ruleSetProxy);
final initError = signal<String?>(null);
final coreActivating = signal(false);
final vpnConnected = signal(false);

bool _activating = false;
Timer? _saveTimer;
String? _lastWorkingConfig; // 用于回滚到最后可用配置

void initAppConfig() {
  final config = AppSettingsStorage.load();
  final stored = AppStoredConfig.fromJson(config);
  final validProfiles = _filterExistingProfiles(stored.profiles);
  profiles.value = validProfiles;
  selectedFile.value = _resolveSelected(stored.selectedFile, validProfiles);
  delayTestUrl.value = stored.delayTestUrl;
  tunIf.value = stored.tunIf ?? !Constants.isDesktop;
  subUA.value = stored.subUA;
  if (stored.themeMode != null) {
    final mode = _parseThemeMode(stored.themeMode!);
    if (mode != null) themeMode.value = mode;
  }
  // coreElevated 由 detectElevation() 实时检测，不从存储恢复
  _startAutoSave();
}

ThemeMode? _parseThemeMode(String name) {
  switch (name) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    case 'system':
      return ThemeMode.system;
    default:
      return null;
  }
}

List<Profile> _filterExistingProfiles(List<Profile> list) {
  final dir = Directory('${Constants.homeDir.path}${Constants.profilesPath}');
  if (!dir.existsSync()) return [];
  final files = dir.listSync().map((e) => p.basename(e.path)).toSet();
  return list.where((e) => files.contains(e.file)).toList();
}

String? _resolveSelected(String? file, List<Profile> list) {
  if (file != null && list.any((e) => e.file == file)) return file;
  return list.isEmpty ? null : list.first.file;
}

void _startAutoSave() {
  effect(() {
    selectedFile.value;
    profiles.value;
    delayTestUrl.value;
    tunIf.value;
    subUA.value;
    themeMode.value;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _save);
  });
  _startSubUpdateTimer();
}

void _save() {
  AppSettingsStorage.save(AppStoredConfig(
    selectedFile: selectedFile.value,
    profiles: profiles.value,
    delayTestUrl: delayTestUrl.value,
    tunIf: tunIf.value,
    subUA: subUA.value,
    themeMode: themeMode.value?.name,
  ).toJson());
}

void _startSubUpdateTimer() {
  // 启动后首次检查
  _checkSubUpdates();
  // 之后每小时检查一次
  Timer.periodic(const Duration(hours: 1), (_) => _checkSubUpdates());
}

Future<void> _checkSubUpdates() async {
  final now = DateTime.now();
  final expired = profiles.value.where(
    (p) => p.type == ProfileType.url && p.url != null && p.interval > 0
        && now.isAfter(p.time.add(Duration(hours: p.interval))),
  ).toList();
  for (final p in expired) {
    if (!profiles.value.any((e) => e.file == p.file)) continue;
    try {
      await refreshProfile(p);
      LogFileWriter.instance?.log(
        '自动更新订阅成功: ${p.name}',
        level: LogLevel.info,
        name: 'sub-update',
      );
    } catch (e) {
      LogFileWriter.instance?.log(
        '自动更新订阅失败: $e',
        level: LogLevel.warning,
        name: 'sub-update',
      );
    }
  }
}

/// 下载订阅并替换旧 profile。校验失败时抛出异常。
Future<Profile> refreshProfile(Profile old) async {
  final dir = '${Constants.homeDir.path}${Constants.profilesPath}';
  final updated = await downloadSubscription(
    url: old.url!,
    profilesDir: dir,
    name: old.name,
    interval: old.interval,
  );
  final path = p.join(dir, updated.file);
  final validation = await LibCore.instance.checkConfig(
    await File(path).readAsString(),
  );
  if (validation.isNotEmpty) {
    await File(path).delete();
    throw Exception('配置校验失败: $validation');
  }
  final isActive = selectedFile.value == old.file;
  profiles.value = profiles.value
      .map((p) => p.file == old.file ? updated : p)
      .toList();
  if (isActive) selectedFile.value = updated.file;
  final oldPath = p.join(dir, old.file);
  if (File(oldPath).existsSync()) await File(oldPath).delete();
  return updated;
}

void startWatchingSelectedFile() {
  effect(() {
    final file = selectedFile.value;
    if (file == null) return;
    final path = p.isAbsolute(file)
        ? file
        : '${Constants.homeDir.path}${Constants.profilesPath}/$file';
    if (!File(path).existsSync()) return;
    LogFileWriter.instance?.log(
      'startWatchingSelectedFile: activating profile $file (state=${LibCore.instance.stateSignal.peek()})',
      name: 'tun',
    );
    profileError.value = null;
    _activateProfile(path);
  });
}

/// Merge the profile YAML with the app's [ClashConfig] overrides,
/// then start the core with the merged content.
///
/// 使用社区最佳实践：
/// 1. 配置预验证 - 在断开 VPN 前验证新配置
/// 2. 原子性操作 - 失败时回滚到上次工作配置
/// 3. 状态一致性 - 确保 VPN 状态正确同步
Future<bool> _activateProfile(String yamlPath) async {
  if (_activating) {
    LogFileWriter.instance?.log('_activateProfile: already activating, skip', name: 'tun');
    return true;
  }

  _activating = true;
  coreActivating.value = true;

  // 保存当前配置用于回滚
  final previousConfig = _lastWorkingConfig;

  try {
    final yamlContent = await File(yamlPath).readAsString();
    final merged = mergeProfileConfig(yamlContent);

    // 引擎重建恢复：内核仍在运行但 _lastWorkingConfig 为空（新 isolate），
    // 同步 _lastWorkingConfig 但不重启内核，避免流量计数器归零
    if (_lastWorkingConfig == null &&
        LibCore.instance.stateSignal.peek() == LibCore.kStateRunning) {
      _lastWorkingConfig = merged;
      LogFileWriter.instance?.log(
        '_activateProfile: engine rebuild, synced _lastWorkingConfig without restart',
        name: 'tun',
      );
      return true;
    }

    // 即将重启内核，清除旧统计数据避免短暂显示上次运行时长
    LibCore.instance.clearStats();

    // 步骤 1: 预验证新配置（配置未变时跳过，仅配置变更时验证）
    if (_lastWorkingConfig != null && merged != _lastWorkingConfig) {
      try {
        final validationResult = await LibCore.instance.checkConfig(merged);
        if (validationResult.isNotEmpty) {
          profileError.value = validationResult;
          return false;
        }
      } catch (_) {}
    }

    try {
      await LibCore.instance.startCoreWithContent(
        merged,
        ruleSetProxy: ruleSetProxy.value,
      );
    } catch (e) {
      LogFileWriter.instance?.log('_activateProfile: startCoreWithContent failed: $e', level: LogLevel.error, name: 'tun');
      // 回滚到上次工作配置
      if (previousConfig != null) {
        try {
          await LibCore.instance.startCoreWithContent(
            previousConfig,
            ruleSetProxy: ruleSetProxy.value,
          );
          profileError.value = e.toString();
        } catch (_) {
          profileError.value = e.toString();
        }
      } else {
        profileError.value = e.toString();
      }
      return false;
    }

    // 配置成功，保存为最后工作配置
    _lastWorkingConfig = merged;
    profileError.value = null;
    return true;
  } catch (e) {
    profileError.value = e.toString();
    LogFileWriter.instance?.log('_activateProfile: unexpected error: $e', level: LogLevel.error, name: 'tun');
    return false;
  } finally {
    _activating = false;
    coreActivating.value = false;
  }
}

/// Overlay [ClashConfig] values onto the profile YAML string.
String mergeProfileConfig(String yamlContent) {
  final config = clashConfig.value;
  final editor = YamlEditor(yamlContent);

  // 系统代理依赖 mixed-port，开启时隐式需要端口
  final portOn = config.userPortEnabled || config.systemProxyEnabled;
  if (portOn && config.mixedPort != null) {
    editor.update(['mixed-port'], config.mixedPort);
  } else {
    final doc = loadYaml(editor.toString());
    if (doc is YamlMap && doc.containsKey('mixed-port')) {
      editor.remove(['mixed-port']);
    }
  }
  if (config.allowLan != null) {
    editor.update(['allow-lan'], config.allowLan);
  }
  if (config.mode != null) {
    editor.update(['mode'], config.mode!.name);
  }
  if (config.logLevel != null) {
    editor.update(['log-level'], config.logLevel!.name);
  }
  if (config.ipv6 != null) {
    editor.update(['ipv6'], config.ipv6);
  }
  if (config.tun != null) {
    if (config.tun!.enable == true) {
      var doc = loadYaml(editor.toString());
      if (doc is YamlMap && !doc.containsKey('tun')) {
        editor.update(['tun'], {});
      }
      editor.update(['tun', 'enable'], true);
      // 补充 TUN 路由参数，地址由内核使用默认值
      doc = loadYaml(editor.toString()) as YamlMap;
      final tun = doc['tun'];
      if (tun is! YamlMap || !tun.containsKey('auto-route')) {
        editor.update(['tun', 'auto-route'], true);
      }
      if (tun is! YamlMap || !tun.containsKey('strict-route')) {
        editor.update(['tun', 'strict-route'], true);
      }
      if (tun is! YamlMap || !tun.containsKey('device')) {
        editor.update(['tun', 'device'], 'singcast');
      }
      // 移动端使用 gvisor 栈，避免 mixed/system 栈在 Android 上
      // SO_BINDTODEVICE 权限不足导致 "bind forwarder to interface" 失败
      if (!Constants.isDesktop) {
        if (tun is! YamlMap || !tun.containsKey('stack')) {
          editor.update(['tun', 'stack'], 'gvisor');
        }
      }
    } else {
      // 完全移除 tun 段，避免内核在无 VPN fd 时尝试配置 TUN
      final doc = loadYaml(editor.toString());
      if (doc is YamlMap && doc.containsKey('tun')) {
        editor.remove(['tun']);
      }
    }
  }

  if (config.apiEnabled) {
    editor.update(['external-controller'], config.apiAddr);
  } else {
    final doc = loadYaml(editor.toString());
    if (doc is YamlMap && doc.containsKey('external-controller')) {
      editor.remove(['external-controller']);
    }
  }

  if (config.systemProxyEnabled) {
    editor.update(['mixed-system-proxy'], true);
  } else {
    final doc = loadYaml(editor.toString());
    if (doc is YamlMap && doc.containsKey('mixed-system-proxy')) {
      editor.remove(['mixed-system-proxy']);
    }
  }

  return editor.toString();
}

Profile? get activeProfile {
  final file = selectedFile.value;
  if (file == null) return null;
  try {
    return profiles.value.firstWhere((e) => e.file == file);
  } catch (_) {
    return null;
  }
}

Future<bool> asyncProfile() async {
  final file = selectedFile.value;
  if (file == null) return true;
  final path = p.isAbsolute(file)
      ? file
      : '${Constants.homeDir.path}${Constants.profilesPath}/$file';
  return _activateProfile(path);
}

String get profilesPath =>
    '${Constants.homeDir.path}${Constants.profilesPath}';

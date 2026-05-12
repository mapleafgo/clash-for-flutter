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
import 'package:proxy_manager/proxy_manager.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

final _proxyManager = ProxyManager();

final systemProxy = signal(false);
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
    systemProxy.value;
    selectedFile.value;
    profiles.value;
    delayTestUrl.value;
    tunIf.value;
    subUA.value;
    themeMode.value;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _save);
  });
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

bool _profileAutoActivated = false;

void startWatchingSelectedFile() {
  effect(() {
    final file = selectedFile.value;
    if (file == null) return;
    final path = p.isAbsolute(file)
        ? file
        : '${Constants.homeDir.path}${Constants.profilesPath}/$file';
    if (!File(path).existsSync()) return;
    // 首次触发：由 _initApp 显式调用 asyncProfile()，此处仅标记已激活
    if (!_profileAutoActivated) {
      _profileAutoActivated = true;
      return;
    }
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

  if (config.mixedPort != null) {
    editor.update(['mixed-port'], config.mixedPort);
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

  editor.update(['external-controller'], '127.0.0.1:9090');

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

Future<void> openProxy() async {
  if (!Constants.isDesktop) return;
  final port = clashConfig.value.port;
  if (port == 0) {
    updateClashConfig(mixedPort: 7890);
  }
  final actualPort = clashConfig.value.port;
  if (Platform.isLinux) {
    await _proxyManager.setAsSystemProxy(ProxyTypes.http, Constants.localhost, actualPort);
    await _proxyManager.setAsSystemProxy(ProxyTypes.https, Constants.localhost, actualPort);
    await _proxyManager.setAsSystemProxy(ProxyTypes.socks, Constants.localhost, actualPort);
    await Process.run('gsettings', ['set', 'org.gnome.system.proxy', 'mode', 'manual']);
  } else if (Platform.isMacOS) {
    await _proxyManager.setAsSystemProxy(ProxyTypes.http, Constants.localhost, actualPort);
    await _proxyManager.setAsSystemProxy(ProxyTypes.socks, Constants.localhost, actualPort);
  } else {
    await _proxyManager.setAsSystemProxy(ProxyTypes.http, Constants.localhost, actualPort);
    await _proxyManager.setAsSystemProxy(ProxyTypes.https, Constants.localhost, actualPort);
  }
  systemProxy.value = true;
}

Future<void> closeProxy() async {
  if (!Constants.isDesktop) return;
  _proxyManager.cleanSystemProxy();
  systemProxy.value = false;
}

String get profilesPath =>
    '${Constants.homeDir.path}${Constants.profilesPath}';

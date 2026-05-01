import 'dart:async';
import 'dart:io';

import 'package:singcast/core/lib_core.dart';
import 'package:singcast/core/tun_elevation.dart';
import 'package:singcast/data/local/app_config_storage.dart';
import 'package:singcast/domain/profile.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/utils/constants.dart';
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

Timer? _saveTimer;

void initAppConfig() {
  final config = AppConfigStorage.load();
  final validProfiles = _filterExistingProfiles(config.profiles);
  profiles.value = validProfiles;
  selectedFile.value = _resolveSelected(config.selectedFile, validProfiles);
  delayTestUrl.value = config.delayTestUrl;
  tunIf.value = config.tunIf ?? !Constants.isDesktop;
  subUA.value = config.subUA;
  coreElevated.value = config.coreElevated;
  _startAutoSave();
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
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _save);
  });
}

void _save() {
  AppConfigStorage.save(AppStoredConfig(
    selectedFile: selectedFile.value,
    profiles: profiles.value,
    delayTestUrl: delayTestUrl.value,
    tunIf: tunIf.value,
    subUA: subUA.value,
    coreElevated: coreElevated.value,
  ));
}

void startWatchingSelectedFile() {
  effect(() {
    final file = selectedFile.value;
    if (file == null) return;
    final path = p.isAbsolute(file)
        ? file
        : '${Constants.homeDir.path}${Constants.profilesPath}/$file';
    if (!File(path).existsSync()) return;
    profileError.value = null;
    _activateProfile(path).then((ok) {
      if (!ok) profileError.value = '配置激活失败';
    }).catchError((e) {
      profileError.value = e.toString();
    });
  });
}

/// Merge the profile YAML with the app's [ClashConfig] overrides,
/// then start the core with the merged content.
Future<bool> _activateProfile(String yamlPath) async {
  coreActivating.value = true;
  try {
    final yamlContent = await File(yamlPath).readAsString();
    final merged = mergeProfileConfig(yamlContent);

    if (Platform.isAndroid || Platform.isIOS) {
      if (clashConfig.value.tunEnabled && !vpnConnected.value) {
        // 首次建立 VPN 隧道
        await LibCore.instance.connectVpn(
          prepareMobileConfig(merged),
          ruleSetProxy: ruleSetProxy.value,
        );
        vpnConnected.value = true;
      } else if (vpnConnected.value) {
        // VPN 模式下切换配置：先停止内核再重启，TUN fd 由 VPN 服务保持
        await LibCore.instance.stopCore();
        await LibCore.instance.startCoreWithContent(
          prepareMobileConfig(merged),
          ruleSetProxy: ruleSetProxy.value,
        );
      } else {
        // 代理模式：直接重启核心
        await LibCore.instance.startCoreWithContent(
          merged,
          ruleSetProxy: ruleSetProxy.value,
        );
      }
    } else {
      await LibCore.instance.startCoreWithContent(
        merged,
        ruleSetProxy: ruleSetProxy.value,
      );
    }
    return true;
  } finally {
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
    final doc = loadYaml(editor.toString());
    if (doc is YamlMap && !doc.containsKey('tun')) {
      editor.update(['tun'], {});
    }
    editor.update(['tun', 'enable'], config.tun!.enable ?? false);
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

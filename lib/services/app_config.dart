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
  final yamlContent = await File(yamlPath).readAsString();
  final merged = mergeProfileConfig(yamlContent);

  if (Platform.isAndroid || Platform.isIOS) {
    if (clashConfig.value.tunEnabled) {
      await LibCore.instance.connectVpn(
        prepareMobileConfig(merged),
        ruleSetProxy: ruleSetProxy.value,
      );
    } else {
      await LibCore.instance.startCoreWithContent(
        merged,
        ruleSetProxy: ruleSetProxy.value,
      );
    }
  } else {
    // 桌面端
    await LibCore.instance.startCoreWithContent(
      merged,
      ruleSetProxy: ruleSetProxy.value,
    );
  }
  return true;
}

/// Overlay [ClashConfig] values onto the profile YAML string.
/// Injects or replaces top-level keys without converting to JSON.
String mergeProfileConfig(String yamlContent) {
  final config = clashConfig.value;
  var result = yamlContent;

  if (config.mixedPort != null) {
    result = _overrideYamlKey(result, 'mixed-port', config.mixedPort!);
  }
  if (config.allowLan != null) {
    result = _overrideYamlKey(result, 'allow-lan', config.allowLan!);
  }
  if (config.mode != null) {
    result = _overrideYamlKey(result, 'mode', config.mode!.name);
  }
  if (config.logLevel != null) {
    result = _overrideYamlKey(result, 'log-level', config.logLevel!.name);
  }
  if (config.ipv6 != null) {
    result = _overrideYamlKey(result, 'ipv6', config.ipv6!);
  }
  if (config.tun != null) {
    result = _overrideTunSection(result, config.tun!.enable ?? false);
  }

  // Ensure external-controller is always set for sing-box API
  if (!RegExp(r'^external-controller\s*:', multiLine: true).hasMatch(result)) {
    result = 'external-controller: 127.0.0.1:9090\n$result';
  }

  return result;
}

String _overrideYamlKey(String yaml, String key, dynamic value) {
  final pattern = RegExp('^' + RegExp.escape(key) + r'\s*:\s*.*$', multiLine: true);
  if (pattern.hasMatch(yaml)) {
    return yaml.replaceFirst(pattern, '$key: $value');
  }
  return '$key: $value\n$yaml';
}

String _overrideTunSection(String yaml, bool enable) {
  final lines = yaml.split('\n');
  int tunIndex = -1;
  int enableIndex = -1;

  for (int i = 0; i < lines.length; i++) {
    if (tunIndex < 0 && lines[i].startsWith('tun:')) {
      tunIndex = i;
    } else if (tunIndex >= 0 && enableIndex < 0) {
      final trimmed = lines[i].trim();
      if (trimmed.startsWith('enable:')) {
        enableIndex = i;
        break;
      }
      // Stop looking if we hit another top-level key
      if (!lines[i].startsWith(' ') && !lines[i].startsWith('\t') && trimmed.isNotEmpty) {
        break;
      }
    }
  }

  if (enableIndex >= 0) {
    lines[enableIndex] = '  enable: $enable';
  } else if (tunIndex >= 0) {
    lines.insert(tunIndex + 1, '  enable: $enable');
  } else {
    lines.insert(0, 'tun:');
    lines.insert(1, '  enable: $enable');
  }

  return lines.join('\n');
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

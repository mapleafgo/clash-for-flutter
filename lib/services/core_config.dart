import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:path/path.dart' as p;
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/i18n/strings.g.dart';
import 'package:singcast/data/local/core_config_storage.dart';
import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_reload.dart'
    show asyncProfile, lastMergedConfig;
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

final clashConfig = signal(ClashConfig.defaults());

Timer? _reloadTimer;
bool _internalUpdate = false;

/// 应用主题模式：null 表示跟随系统。
final themeMode = signal<ThemeMode?>(null);

ThemeMode get resolvedThemeMode => themeMode.value ?? ThemeMode.system;

Future<void> initCoreConfig() async {
  if (CoreConfigStorage.exists()) {
    _updateConfig((_) => CoreConfigStorage.load());
  }
  LogFileWriter.instance?.setMinLevel(
    clashConfig.value.logLevel ?? LogLevel.info,
  );

  effect(() {
    clashConfig.value; // 订阅变化
    tunStack.value; // TUN 协议栈切换也走同一热重载链路
    if (_internalUpdate) {
      _internalUpdate = false;
      return;
    }
    _scheduleReload();
  });
}

/// 保存配置到磁盘。TUN 和系统代理不持久化，每次启动需手动开启。
void _saveToDisk() {
  final config = clashConfig.value.copyWith(
    tun: TunConfig(enable: false),
    mixedSystemProxy: false,
  );
  CoreConfigStorage.save(config);
}

/// 内部修改配置：更新 signal + 立即持久化，effect 跳过重载
void _updateConfig(ClashConfig Function(ClashConfig) updater) {
  _internalUpdate = true;
  clashConfig.value = updater(clashConfig.value);
  _internalUpdate = false;
  _saveToDisk();
}

Future<void> _syncModeToCore(Mode? mode) async {
  if (mode == null) return;
  try {
    final modeStr = mode.name[0].toUpperCase() + mode.name.substring(1);
    await LibCore.instance.setMode(modeStr);
    _updateConfig((c) => c.copyWith(mode: mode));
    LibCore.instance.modeSignal.value = mode.name;
  } catch (e) {
    LogFileWriter.instance?.log(
      'setMode failed: $e',
      level: LogLevel.error,
      name: 'core_config',
    );
    profileError.value = t.core.modeSwitchFailed(error: '$e');
  }
}

Future<void> changeMode(Mode mode) async {
  if (LibCore.instance.stateSignal.value != LibCore.kStateRunning) return;
  await _syncModeToCore(mode);
}

Future<void> changeModeStr(String mode) async {
  final m = Mode.values.where((v) => v.name == mode);
  if (m.isNotEmpty) return changeMode(m.first);
}

void _scheduleReload() {
  if (selectedFile.peek() == null) return;
  final state = LibCore.instance.stateSignal.peek();
  LogFileWriter.instance?.log(
    '_scheduleReload: scheduled (file=${selectedFile.peek()}, tun=${clashConfig.value.tunEnabled}, state=$state)',
    name: 'tun',
  );
  _reloadTimer?.cancel();
  _reloadTimer = Timer(const Duration(seconds: 1), () async {
    _saveToDisk();
    LogFileWriter.instance?.log(
      '_scheduleReload: firing asyncProfile (tun=${clashConfig.value.tunEnabled})',
      name: 'tun',
    );
    asyncProfile();
  });
}

void updateClashConfig({
  int? mixedPort,
  bool? allowLan,
  Mode? mode,
  LogLevel? logLevel,
  bool? ipv6,
  bool? externalController,
  String? externalControllerAddr,
  bool? portEnabled,
  bool? mixedSystemProxy,
}) {
  clashConfig.value = clashConfig.value.copyWith(
    mixedPort: mixedPort,
    allowLan: allowLan,
    mode: mode,
    logLevel: logLevel,
    ipv6: ipv6,
    externalController: externalController,
    externalControllerAddr: externalControllerAddr,
    portEnabled: portEnabled,
    mixedSystemProxy: mixedSystemProxy,
  );
  if (logLevel != null) {
    LogFileWriter.instance?.setMinLevel(logLevel);
  }
}

Future<void> toggleTun(bool enable) async {
  if (enable) {
    await enableTun();
  } else {
    await disableTun();
  }
}

Future<void> enableSystemProxy() async {
  if (!Constants.isDesktop) return;
  _updateConfig(
    (c) => c.copyWith(mixedSystemProxy: true, tun: TunConfig(enable: false)),
  );
  await asyncProfile();
}

Future<void> disableSystemProxy() async {
  if (!Constants.isDesktop) return;
  _updateConfig((c) => c.copyWith(mixedSystemProxy: false));
  await asyncProfile();
}

Future<void> toggleSystemProxy(bool enable) async {
  if (enable) {
    await enableSystemProxy();
  } else {
    await disableSystemProxy();
  }
}

Future<void> enableTun() async {
  if (!Constants.isDesktop) {
    final file = selectedFile.value;
    if (file == null) return;
    final path = _resolveProfilePath(file);
    if (!File(path).existsSync()) return;

    try {
      _reloadTimer?.cancel();
      _applyTunConfig(true);
      final yamlContent = await File(path).readAsString();
      final merged = mergeProfileConfig(yamlContent);
      await LibCore.instance.connectVpn(
        merged,
        ruleSetProxy: ruleSetProxy.value,
        ipv6: clashConfig.value.ipv6,
      );
      lastMergedConfig.value = merged;
    } catch (e) {
      _applyTunConfig(false);
      rethrow;
    }
    return;
  }
  await _enableTunDesktop();
}

Future<void> disableTun() async {
  if (!Constants.isDesktop) {
    vpnConnected.value = false;
    _applyTunConfig(false);
    // 先关闭 VPN 接口（不停内核），避免 refreshConfig 中 fdsan 崩溃
    await LibCore.instance.disconnectVpn();
    // fire-and-forget：内核后台热重载，FAB loading 由 StateUpdate 回调清除
    asyncProfile();
    return;
  }
  await _disableTunDesktop();
}

// --- Desktop TUN ---

Future<void> _enableTunDesktop() async {
  final svc = LibCore.instance.serviceManager;
  if (svc != null && !await svc.isReady()) {
    final ok = await LibCore.instance.elevateService();
    if (!ok) {
      throw TunElevationException(t.core.elevationFailed);
    }
    try {
      await LibCore.instance.restart();
    } on StateError catch (e) {
      throw TunElevationException(e.message);
    }
    // restart → onProcessReady 已用 ensureProxyMode + asyncProfile 完成重载
    return;
  }
  // unit 已装但当前降级直跑（ACL 缺当前 uid）：补一次 ACL 刷新
  if (svc is UnixServiceManager && LibCore.instance.isDegradedService) {
    final ok = await svc.refreshCallerUid();
    if (!ok) {
      throw TunElevationException(t.core.elevationFailed);
    }
    await LibCore.instance.restart();
    return;
  }
  _applyTunConfig(true);
  asyncProfile();
}

Future<void> _disableTunDesktop() async {
  _applyTunConfig(false);
  if (LibCore.instance.stateSignal.value != LibCore.kStateRunning) return;
  asyncProfile();
}

void _applyTunConfig(bool enable) {
  _updateConfig(
    (c) => c.copyWith(
      tun: TunConfig(enable: enable),
      mixedSystemProxy: enable ? false : c.mixedSystemProxy,
    ),
  );
}

/// 引擎重建恢复时同步 TUN 启用状态（不触发重载）
void ensureTunEnabled(bool enabled) {
  if (clashConfig.value.tunEnabled != enabled) {
    _updateConfig((c) => c.copyWith(tun: TunConfig(enable: enabled)));
  }
}

/// 恢复代理模式开关到指定状态，不触发重载。
void ensureProxyMode(bool tunMode) {
  final cur = clashConfig.value;
  final curTun = cur.tun?.enable ?? false;
  final curProxy = cur.mixedSystemProxy ?? false;
  if (curTun == tunMode && curProxy == !tunMode) return;
  _updateConfig(
    (c) => c.copyWith(
      tun: TunConfig(enable: tunMode),
      mixedSystemProxy: !tunMode,
    ),
  );
}

String _resolveProfilePath(String file) {
  if (file.startsWith('/')) return file;
  return p.join(Constants.homeDir.path, Constants.profilesDir, file);
}

class TunElevationException implements Exception {
  final String message;
  TunElevationException(this.message);

  @override
  String toString() => 'TunElevationException: $message';
}

/// Overlay [ClashConfig] values onto the profile YAML string.
String mergeProfileConfig(String yamlContent) {
  final config = clashConfig.value;
  final editor = YamlEditor(yamlContent);

  // 剔除订阅中可能误导应用的配置项，由应用自行管理
  const stripKeys = [
    // 代理端口 — 应用按需管理
    'port',
    'socks-port',
    'mixed-port',
    'redir-port',
    'tproxy-port',
    'bind-address',
    'authentication',
    'listeners',
    // 外部控制 — 应用自行管理 API 鉴权与 UI
    'external-controller',
    'external-controller-cors',
    'external-controller-unix',
    'external-controller-pipe',
    'external-controller-tls',
    'external-doh-server',
    'external-ui',
    'external-ui-name',
    'external-ui-url',
    'secret',
    'tls',
    // 应用覆盖 — 由 ClashConfig 控制
    'allow-lan',
    'mode',
    'log-level',
    'ipv6',
    'tun',
    'mixed-system-proxy',
  ];
  final doc = loadYaml(editor.toString());
  if (doc is YamlMap) {
    for (final key in stripKeys) {
      if (doc.containsKey(key)) {
        editor.remove([key]);
      }
    }
  }

  // 系统代理依赖 mixed-port，开启时隐式需要端口
  final portOn = config.userPortEnabled || config.systemProxyEnabled;
  if (portOn && config.mixedPort != null) {
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
  if (config.tun?.enable == true) {
    editor.update(['tun'], <String, dynamic>{
      'enable': true,
      'auto-route': true,
      'strict-route': true,
      if (!Platform.isMacOS) 'device': 'singcast',
      'stack': tunStack.value.name,
    });
  }

  if (config.apiEnabled) {
    editor.update(['external-controller'], config.apiAddr);
  }

  if (config.systemProxyEnabled) {
    editor.update(['mixed-system-proxy'], true);
  }

  return editor.toString();
}

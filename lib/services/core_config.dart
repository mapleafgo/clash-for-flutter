import 'dart:async';

import 'dart:convert';
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

final coreConfig = signal(SingboxConfig.defaults());

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
    coreConfig.value.logLevel ?? LogLevel.info,
  );

  effect(() {
    coreConfig.value; // 订阅变化
    tunStack.value; // TUN 协议栈切换也走同一热重载链路
    if (_internalUpdate) {
      _internalUpdate = false;
      return;
    }
    _scheduleReload();
  });
}

/// 保存配置到磁盘。TUN 和系统代理不持久化，每次启动需手动开启。
///
/// 写盘失败只记日志不上抛：调用方多是 UI 回调与 effect，
/// 让磁盘异常冲垮设置变更得不偿失。
void _saveToDisk() {
  final config = coreConfig.value.copyWith(
    tun: TunConfig(enable: false),
    systemProxy: false,
  );
  try {
    CoreConfigStorage.save(config);
  } catch (e) {
    LogFileWriter.instance?.log(
      'save core config failed: $e',
      level: LogLevel.warning,
      name: 'core_config',
    );
  }
}

/// 内部修改配置：更新 signal + 立即持久化，effect 跳过重载
void _updateConfig(SingboxConfig Function(SingboxConfig) updater) {
  _internalUpdate = true;
  coreConfig.value = updater(coreConfig.value);
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
    '_scheduleReload: scheduled (file=${selectedFile.peek()}, tun=${coreConfig.value.tunEnabled}, state=$state)',
    name: 'tun',
  );
  _reloadTimer?.cancel();
  _reloadTimer = Timer(const Duration(seconds: 1), () async {
    _saveToDisk();
    LogFileWriter.instance?.log(
      '_scheduleReload: firing asyncProfile (tun=${coreConfig.value.tunEnabled})',
      name: 'tun',
    );
    asyncProfile();
  });
}

void updateCoreConfig({
  int? mixedPort,
  bool? allowLan,
  Mode? mode,
  LogLevel? logLevel,
  bool? ipv6,
  bool? externalController,
  String? externalControllerAddr,
  bool? portEnabled,
  bool? systemProxy,
}) {
  coreConfig.value = coreConfig.value.copyWith(
    mixedPort: mixedPort,
    allowLan: allowLan,
    mode: mode,
    logLevel: logLevel,
    ipv6: ipv6,
    externalController: externalController,
    externalControllerAddr: externalControllerAddr,
    portEnabled: portEnabled,
    systemProxy: systemProxy,
  );
  if (logLevel != null) {
    LogFileWriter.instance?.setMinLevel(logLevel);
  }
  // 直接落盘，不依赖 _scheduleReload 里的持久化：无选中配置时
  // _scheduleReload 会提前返回，这些设置将永远写不进 config.yaml。
  _saveToDisk();
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
    (c) => c.copyWith(systemProxy: true, tun: TunConfig(enable: false)),
  );
  await asyncProfile();
}

Future<void> disableSystemProxy() async {
  if (!Constants.isDesktop) return;
  _updateConfig((c) => c.copyWith(systemProxy: false));
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
        ipv6: coreConfig.value.ipv6,
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
  if (svc is LinuxServiceManager && svc.isDegradedRun) {
    final ok = await svc.reinstallForCurrentUser();
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
  final state = LibCore.instance.stateSignal.value;
  if (state == LibCore.kStateStarting) {
    // starting 窗口期不能下发，但也不能丢：否则配置与 UI 都显示"已关闭"
    // 而内核仍带着 TUN 在跑。交给 asyncProfile 挂起，转 running 后补发。
    asyncProfile();
    return;
  }
  if (state != LibCore.kStateRunning) return;
  asyncProfile();
}

void _applyTunConfig(bool enable) {
  _updateConfig(
    (c) => c.copyWith(
      tun: TunConfig(enable: enable),
      systemProxy: enable ? false : c.systemProxy,
    ),
  );
}

/// 引擎重建恢复时同步 TUN 启用状态（不触发重载）
void ensureTunEnabled(bool enabled) {
  if (coreConfig.value.tunEnabled != enabled) {
    _updateConfig((c) => c.copyWith(tun: TunConfig(enable: enabled)));
  }
}

/// 恢复代理模式开关到指定状态，不触发重载。
void ensureProxyMode(bool tunMode) {
  final cur = coreConfig.value;
  final curTun = cur.tun?.enable ?? false;
  final curProxy = cur.systemProxy ?? false;
  if (curTun == tunMode && curProxy == !tunMode) return;
  _updateConfig(
    (c) => c.copyWith(
      tun: TunConfig(enable: tunMode),
      systemProxy: !tunMode,
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

/// Overlay [SingboxConfig] values onto the profile JSON.
String mergeProfileConfig(String jsonContent) {
  final doc = jsonDecode(jsonContent) as Map<String, dynamic>;
  final config = coreConfig.value;

  const managedTypes = {'mixed', 'http', 'socks', 'tun', 'redirect', 'tproxy'};
  final inbounds = (doc['inbounds'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .where((e) => !managedTypes.contains(e['type']))
          .toList() ??
      <Map<String, dynamic>>[];

  final portOn = config.userPortEnabled || config.systemProxyEnabled;
  if (portOn) {
    inbounds.add({
      'type': 'mixed',
      'tag': 'mixed-in',
      'listen': config.allowLan == true ? '0.0.0.0' : '127.0.0.1',
      'listen_port': config.mixedPort ?? Constants.defaultMixedPort,
      if (config.systemProxyEnabled) 'set_system_proxy': true,
    });
  }

  if (config.tun?.enable == true) {
    inbounds.add({
      'type': 'tun',
      'tag': 'tun-in',
      'auto_route': true,
      'strict_route': true,
      'stack': tunStack.value.name,
      if (Platform.isLinux) 'auto_redirect': true,
      'address': [
        '172.18.0.1/30',
        if (config.ipv6 == true) 'fdfe:dcba:9876::1/126',
      ],
    });
  }

  if (inbounds.isNotEmpty) {
    doc['inbounds'] = inbounds;
  } else {
    doc.remove('inbounds');
  }

  if (config.logLevel != null) {
    final log =
        (doc['log'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    log['level'] = config.logLevel == LogLevel.warning
        ? 'warn'
        : config.logLevel!.name;
    doc['log'] = log;
  }

  if (config.apiEnabled) {
    final exp =
        (doc['experimental'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final clashApi =
        (exp['clash_api'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    clashApi['external_controller'] = config.apiAddr;
    if (config.mode != null) {
      clashApi['default_mode'] =
          config.mode!.name[0].toUpperCase() + config.mode!.name.substring(1);
    }
    exp['clash_api'] = clashApi;
    doc['experimental'] = exp;
  } else {
    final exp = doc['experimental'] as Map<String, dynamic>?;
    exp?.remove('clash_api');
    if (exp != null && exp.isEmpty) doc.remove('experimental');
  }

  if (config.ipv6 != null) {
    final dns =
        (doc['dns'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    dns['strategy'] = config.ipv6! ? 'prefer_ipv6' : 'ipv4_only';
    doc['dns'] = dns;
  }

  return jsonEncode(doc);
}

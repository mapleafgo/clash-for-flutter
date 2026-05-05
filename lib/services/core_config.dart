import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:singcast/core/lib_core.dart';
import 'package:singcast/core/tun_elevation.dart';
import 'package:singcast/data/local/core_config_storage.dart';
import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/utils/constants.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

final clashConfig = signal(ClashConfig.defaults());

Timer? _syncTimer;
Timer? _reloadTimer;
Mode? _lastSyncedMode;
int? _lastSyncedPort;
bool? _lastSyncedTun;

final modeChanging = signal(false);

Future<void> initCoreConfig() async {
  if (CoreConfigStorage.exists()) {
    clashConfig.value = CoreConfigStorage.load();
  }
  _lastSyncedMode = clashConfig.value.mode;
  _lastSyncedPort = clashConfig.value.mixedPort;
  _lastSyncedTun = clashConfig.value.tunEnabled;
  detectElevation();
  await elevationReady;
  effect(() {
    final config = clashConfig.value;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 1), () {
      CoreConfigStorage.save(config);
    });
    if (config.mode != _lastSyncedMode) {
      _lastSyncedMode = config.mode;
      _saveSync();
    } else if (config.tunEnabled != _lastSyncedTun) {
      _lastSyncedTun = config.tunEnabled;
      _saveSync();
    } else {
      _scheduleReload();
    }
  });
  effect(() {
    if (LibCore.instance.vpnDisconnectedByUser.value) {
      _setTunEnabled(false);
      vpnConnected.value = false;
      LibCore.instance.vpnDisconnectedByUser.value = false;
    }
  });
}

void _saveSync() {
  CoreConfigStorage.save(clashConfig.value);
}

Future<void> _syncModeToCore(Mode? mode) async {
  if (mode == null) return;
  try {
    await LibCore.instance.setMode(mode.name);
    LibCore.instance.modeSignal.value = mode.name;
  } catch (e) {
    log('[core_config] setMode(${mode.name}) failed: $e');
  }
}

/// 通知内核切换模式，UI 状态由 [watchModeFromCore] 从内核事件回写更新。
Future<void> changeMode(Mode mode) async {
  if (modeChanging.value) return;
  modeChanging.value = true;
  try {
    await _syncModeToCore(mode);
  } finally {
    modeChanging.value = false;
  }
}

void _scheduleReload() {
  if (selectedFile.value == null) return;
  _reloadTimer?.cancel();
  _reloadTimer = Timer(const Duration(seconds: 1), () async {
    await asyncProfile();
    if (systemProxy.value && _lastSyncedPort != clashConfig.value.mixedPort) {
      _lastSyncedPort = clashConfig.value.mixedPort;
      await openProxy();
    }
  });
}

void updateClashConfig({
  int? mixedPort,
  bool? allowLan,
  Mode? mode,
  LogLevel? logLevel,
  bool? ipv6,
}) {
  clashConfig.value = clashConfig.value.copyWith(
    mixedPort: mixedPort,
    allowLan: allowLan,
    mode: mode,
    logLevel: logLevel,
    ipv6: ipv6,
  );
}

void watchModeFromCore() {
  effect(() {
    final modeStr = LibCore.instance.modeSignal.value;
    final mode = Mode.values.where((m) => m.name == modeStr).firstOrNull;
    if (mode != null && clashConfig.value.mode != mode) {
      _lastSyncedMode = mode;
      clashConfig.value = clashConfig.value.copyWith(mode: mode);
    }
  });
}

Future<void> toggleTun(bool enable) async {
  if (enable) {
    await openTun();
  } else {
    await closeTun();
  }
}

Future<void> openTun() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await _openTunMobile();
  } else {
    await _openTunDesktop();
  }
}

Future<void> closeTun() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await _closeTunMobile();
  } else {
    await _closeTunDesktop();
  }
}

// --- Desktop TUN ---

Future<void> _openTunDesktop() async {
  if (!coreElevated.value) {
    _setTunEnabled(true);
    if (Platform.isLinux) {
      // Linux: one-time setcap，重启后 capability 持久化，后续无需再提权
      final ok = await setupTunCapability();
      if (!ok) {
        _setTunEnabled(false);
        throw TunElevationException('授予网络权限失败，请确认 pkexec 可用');
      }
      if (await relaunchSelf()) {
        exit(0);
      }
      // 启动新进程失败，回滚状态
      _setTunEnabled(false);
      throw TunElevationException('重启应用失败');
    } else if (Platform.isMacOS) {
      // macOS: 以 root 重启，传递 homeDir 避免 root 使用 /var/root 数据目录
      if (await relaunchElevated(homeDir: Constants.homeDir.path)) {
        exit(0);
      }
      _setTunEnabled(false);
      throw TunElevationException('提权失败，请重试');
    } else {
      // Windows: 以管理员重启，同一用户 %APPDATA% 不变，无需传 homeDir
      if (await relaunchElevated()) {
        exit(0);
      }
      _setTunEnabled(false);
      throw TunElevationException('提权失败，请重试');
    }
  }
  _setTunEnabled(true);
  await asyncProfile();
}

Future<void> _closeTunDesktop() async {
  _setTunEnabled(false);
  await asyncProfile();
}

void _setTunEnabled(bool enable) {
  clashConfig.value = clashConfig.value.copyWith(
    tun: TunConfig(enable: enable),
  );
  _saveSync();
}

// --- Mobile TUN ---

Future<void> _openTunMobile() async {
  final file = selectedFile.value;
  if (file == null) return;

  final path = _resolveProfilePath(file);
  if (!File(path).existsSync()) return;

  try {
    // 先停止代理模式下的内核，避免 VPN 启动时内核冲突
    try {
      await LibCore.instance.stopCore();
    } catch (_) {}

    final yamlContent = await File(path).readAsString();
    final merged = mergeProfileConfig(yamlContent);
    await LibCore.instance.connectVpn(
      prepareMobileConfig(merged),
      ruleSetProxy: ruleSetProxy.value,
    );

    _setTunEnabled(true);
    vpnConnected.value = true;
  } catch (e) {
    rethrow;
  }
}

Future<void> _closeTunMobile() async {
  try {
    await LibCore.instance.disconnectVpn();
  } catch (_) {}

  _setTunEnabled(false);
  vpnConnected.value = false;

  // 关闭 TUN 后重新以代理模式启动内核，保持 API 可用
  final file = selectedFile.value;
  if (file == null) return;
  final path = _resolveProfilePath(file);
  if (!File(path).existsSync()) return;

  try {
    final yamlContent = await File(path).readAsString();
    final merged = mergeProfileConfig(yamlContent);
    await LibCore.instance.startCoreWithContent(
      prepareMobileConfig(merged, tunEnabled: false),
      ruleSetProxy: ruleSetProxy.value,
    );
  } catch (_) {}
}

String _resolveProfilePath(String file) {
  if (file.startsWith('/')) return file;
  return '${Constants.homeDir.path}${Constants.profilesPath}/$file';
}

/// Modify config for mobile (Android/iOS).
/// VpnService / Network Extension handles routing; the Go platform layer
/// skips interface detection for mobile (runtime.GOOS check), so
/// auto-detect-interface can safely remain true (default).
/// When [tunEnabled] (VPN mode):
///   enable: true, auto-route: false, strict-route: false
/// When ![tunEnabled] (proxy mode):
///   enable: false
String prepareMobileConfig(String yaml, {bool tunEnabled = true}) {
  final editor = YamlEditor(yaml);
  final doc = loadYaml(editor.toString());
  if (doc is YamlMap && !doc.containsKey('tun')) {
    editor.update(['tun'], {});
  }
  if (tunEnabled) {
    editor.update(['tun', 'enable'], true);
    editor.update(['tun', 'auto-route'], false);
    editor.update(['tun', 'strict-route'], false);
  } else {
    editor.update(['tun', 'enable'], false);
  }
  return editor.toString();
}

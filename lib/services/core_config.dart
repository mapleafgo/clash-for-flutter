import 'dart:async';
import 'dart:io';

import 'package:singcast/core/lib_core.dart';
import 'package:singcast/core/tun_elevation.dart';
import 'package:singcast/data/local/core_config_storage.dart';
import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/utils/constants.dart';
import 'package:signals_flutter/signals_flutter.dart';

final clashConfig = signal(ClashConfig.defaults());

Timer? _syncTimer;
Timer? _reloadTimer;
Mode? _lastSyncedMode;

void initCoreConfig() {
  if (CoreConfigStorage.exists()) {
    clashConfig.value = CoreConfigStorage.load();
  }
  _lastSyncedMode = clashConfig.value.mode;
  effect(() {
    final config = clashConfig.value;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 1), () {
      CoreConfigStorage.save(config);
    });
    // mode 变化走 setMode 热更新，其他变化延迟重载内核
    if (config.mode != _lastSyncedMode) {
      _lastSyncedMode = config.mode;
      _syncModeToCore(config.mode);
    } else {
      _scheduleReload();
    }
  });
  // 监听通知栏断开 VPN 事件，同步本地状态
  effect(() {
    if (LibCore.instance.vpnDisconnectedByUser.value) {
      _setTunEnabled(false);
      LibCore.instance.vpnDisconnectedByUser.value = false;
    }
  });
  detectElevation();
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
    print('[core_config] setMode(${mode.name}) failed: $e');
  }
}

void _scheduleReload() {
  if (selectedFile.value == null) return;
  _reloadTimer?.cancel();
  _reloadTimer = Timer(const Duration(seconds: 1), _reloadCoreWithCurrentProfile);
}

void updateClashConfig({
  int? mixedPort,
  bool? allowLan,
  Mode? mode,
  LogLevel? logLevel,
  bool? ipv6,
}) {
  final old = clashConfig.value;
  clashConfig.value = ClashConfig(
    mixedPort: mixedPort ?? old.mixedPort,
    allowLan: allowLan ?? old.allowLan,
    mode: mode ?? old.mode,
    logLevel: logLevel ?? old.logLevel,
    ipv6: ipv6 ?? old.ipv6,
    tun: old.tun,
  );
}

void watchModeFromCore() {
  effect(() {
    final modeStr = LibCore.instance.modeSignal.value;
    final mode = Mode.values.where((m) => m.name == modeStr).firstOrNull;
    if (mode != null && clashConfig.value.mode != mode) {
      clashConfig.value = ClashConfig(
        mixedPort: clashConfig.value.mixedPort,
        allowLan: clashConfig.value.allowLan,
        mode: mode,
        logLevel: clashConfig.value.logLevel,
        ipv6: clashConfig.value.ipv6,
        tun: clashConfig.value.tun,
      );
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
    if (Platform.isLinux) {
      // Linux: one-time setcap, then restart normally (no root needed)
      final ok = await setupTunCapability();
      if (!ok) {
        throw TunElevationException('授予网络权限失败，请确认 pkexec 可用');
      }
      _setTunEnabled(true);
      await relaunchSelf();
    } else {
      // macOS/Windows: restart with admin privileges
      _setTunEnabled(true);
      await relaunchElevated();
    }
    return;
  }
  _setTunEnabled(true);
  await _reloadCoreWithCurrentProfile();
}

Future<void> _closeTunDesktop() async {
  _setTunEnabled(false);
  await _reloadCoreWithCurrentProfile();
}

void _setTunEnabled(bool enable) {
  clashConfig.value = ClashConfig(
    mixedPort: clashConfig.value.mixedPort,
    allowLan: clashConfig.value.allowLan,
    mode: clashConfig.value.mode,
    logLevel: clashConfig.value.logLevel,
    ipv6: clashConfig.value.ipv6,
    tun: TunConfig(enable: enable),
  );
  _saveSync();
}

Future<void> _reloadCoreWithCurrentProfile() async {
  final file = selectedFile.value;
  if (file == null) return;

  final path = _resolveProfilePath(file);
  if (!File(path).existsSync()) return;

  try {
    final yamlContent = await File(path).readAsString();
    final merged = mergeProfileConfig(yamlContent);
    await LibCore.instance.stopCore();
    await LibCore.instance.startCoreWithContent(
      merged,
      ruleSetProxy: ruleSetProxy.value,
    );
  } catch (_) {}
}

// --- Mobile TUN ---

Future<void> _openTunMobile() async {
  final file = selectedFile.value;
  if (file == null) return;

  final path = _resolveProfilePath(file);
  if (!File(path).existsSync()) return;

  try {
    final yamlContent = await File(path).readAsString();
    final merged = mergeProfileConfig(yamlContent);
    await LibCore.instance.connectVpn(
      prepareMobileConfig(merged),
      ruleSetProxy: ruleSetProxy.value,
    );

    _setTunEnabled(true);
  } catch (e) {
    rethrow;
  }
}

Future<void> _closeTunMobile() async {
  try {
    await LibCore.instance.disconnectVpn();
  } catch (_) {}

  _setTunEnabled(false);

  // 关闭 TUN 后重新以代理模式启动内核，保持 API 可用
  final file = selectedFile.value;
  if (file == null) return;
  final path = _resolveProfilePath(file);
  if (!File(path).existsSync()) return;

  try {
    final yamlContent = await File(path).readAsString();
    final merged = mergeProfileConfig(yamlContent);
    await LibCore.instance.startCoreWithContent(
      merged,
      ruleSetProxy: ruleSetProxy.value,
    );
  } catch (_) {}
}

String _resolveProfilePath(String file) {
  if (file.startsWith('/')) return file;
  return '${Constants.homeDir.path}${Constants.profilesPath}/$file';
}

/// Modify TUN config for mobile (Android/iOS).
/// VpnService / Network Extension handles routing, so the core must not
/// access netlink. Follows community best practice (FlClash, sing-box SFA):
///   auto-route: false           — VpnService manages routing
///   strict-route: false         — not supported on mobile
///   auto-detect-interface: false — prevents netlink socket creation
String prepareMobileConfig(String yaml) {
  final lines = yaml.split('\n');
  final result = <String>[];
  bool inTun = false;
  bool hasAutoRoute = false;
  bool hasStrictRoute = false;
  bool hasAutoDetect = false;

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();

    if (line.startsWith('tun:')) {
      inTun = true;
      result.add(line);
      continue;
    }

    if (inTun &&
        !line.startsWith(' ') &&
        !line.startsWith('\t') &&
        trimmed.isNotEmpty) {
      if (!hasAutoRoute) result.add('  auto-route: false');
      if (!hasStrictRoute) result.add('  strict-route: false');
      if (!hasAutoDetect) result.add('  auto-detect-interface: false');
      inTun = false;
    }

    if (inTun) {
      if (trimmed.startsWith('auto-route:')) {
        result.add('  auto-route: false');
        hasAutoRoute = true;
        continue;
      }
      if (trimmed.startsWith('strict-route:')) {
        result.add('  strict-route: false');
        hasStrictRoute = true;
        continue;
      }
      if (trimmed.startsWith('auto-detect-interface:')) {
        result.add('  auto-detect-interface: false');
        hasAutoDetect = true;
        continue;
      }
    }

    result.add(line);
  }

  if (inTun) {
    if (!hasAutoRoute) result.add('  auto-route: false');
    if (!hasStrictRoute) result.add('  strict-route: false');
    if (!hasAutoDetect) result.add('  auto-detect-interface: false');
  }

  return result.join('\n');
}

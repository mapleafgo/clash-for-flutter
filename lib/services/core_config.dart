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

final clashConfig = signal(ClashConfig.defaults());

Timer? _syncTimer;
Timer? _reloadTimer;
int? _lastSyncedPort;
bool _internalUpdate = false;

final modeChanging = signal(false);

Future<void> initCoreConfig() async {
  if (CoreConfigStorage.exists()) {
    clashConfig.value = CoreConfigStorage.load();
  }
  _lastSyncedPort = clashConfig.value.mixedPort;
  detectElevation();
  await elevationReady;
  effect(() {
    clashConfig.value; // 订阅变化
    if (_internalUpdate) {
      _internalUpdate = false;
      return;
    }
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 1), () {
      CoreConfigStorage.save(clashConfig.value);
    });
    _scheduleReload();
  });
  effect(() {
    if (LibCore.instance.vpnDisconnectedByUser.value) {
      _setTunEnabled(false);
      vpnConnected.value = false;
      LibCore.instance.vpnDisconnectedByUser.value = false;
    }
  });
}

/// 内部修改配置：更新 signal + 立即持久化，effect 跳过重载
void _updateConfig(ClashConfig Function(ClashConfig) updater) {
  _internalUpdate = true;
  clashConfig.value = updater(clashConfig.value);
  _internalUpdate = false;
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
  if (!LibCore.instance.coreConnected.value) return;
  modeChanging.value = true;
  try {
    await _syncModeToCore(mode);
  } finally {
    modeChanging.value = false;
  }
}

void _scheduleReload() {
  if (selectedFile.value == null) return;
  // 移动端 VPN 未开且内核未运行，跳过
  if (!Constants.isDesktop && !vpnConnected.value && !LibCore.instance.coreConnected.value) return;
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
      _updateConfig((c) => c.copyWith(mode: mode));
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
  if (!Constants.isDesktop) {
    final file = selectedFile.value;
    if (file == null) return;
    final path = _resolveProfilePath(file);
    if (!File(path).existsSync()) return;

    try {
      _setTunEnabled(true);
      final yamlContent = await File(path).readAsString();
      final merged = mergeProfileConfig(yamlContent);
      await LibCore.instance.openTun(
        merged,
        ruleSetProxy: ruleSetProxy.value,
        ipv6: clashConfig.value.ipv6,
      );
    } catch (e) {
      _setTunEnabled(false);
      rethrow;
    }
    return;
  }
  await _openTunDesktop();
}

Future<void> closeTun() async {
  if (!Constants.isDesktop) {
    _setTunEnabled(false);
    vpnConnected.value = false;
    await LibCore.instance.closeTun();
    await asyncProfile();
    return;
  }
  await _closeTunDesktop();
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
  if (!LibCore.instance.coreConnected.value) return;
  await asyncProfile();
}

void _setTunEnabled(bool enable) {
  _updateConfig((c) => c.copyWith(tun: TunConfig(enable: enable)));
}

/// 引擎重建恢复时同步 TUN 启用状态（不触发重载）
void ensureTunEnabled(bool enabled) {
  if (clashConfig.value.tunEnabled != enabled) {
    _updateConfig((c) => c.copyWith(tun: TunConfig(enable: enabled)));
  }
}


String _resolveProfilePath(String file) {
  if (file.startsWith('/')) return file;
  return '${Constants.homeDir.path}${Constants.profilesPath}/$file';
}

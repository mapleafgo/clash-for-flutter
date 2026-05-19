import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/core/tun_elevation.dart';
import 'package:singcast/data/local/core_config_storage.dart';
import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';
import 'package:signals_flutter/signals_flutter.dart';

final clashConfig = signal(ClashConfig.defaults());

/// 总开关开启的时间戳（毫秒），每次切换时重置。
int switchedAt = 0;

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

  detectElevation();
  await elevationReady;
  effect(() {
    clashConfig.value; // 订阅变化
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

void watchModeFromCore() {
  // 模式变更由 setMode 成功后直接更新，无需事件回调
}

Future<void> toggleTun(bool enable) async {
  final sw = Stopwatch()..start();
  LogFileWriter.instance?.log('toggleTun($enable) called', name: 'tun');
  if (enable) {
    await enableTun();
  } else {
    await disableTun();
  }
  switchedAt = enable ? DateTime.now().millisecondsSinceEpoch : 0;
  LogFileWriter.instance?.log(
    'toggleTun($enable): ${sw.elapsedMilliseconds}ms',
    name: 'tun',
  );
}

Future<void> enableSystemProxy() async {
  if (!Constants.isDesktop) return;
  _updateConfig((c) => c.copyWith(
    mixedSystemProxy: true,
    tun: TunConfig(enable: false),
  ));
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
  switchedAt = enable ? DateTime.now().millisecondsSinceEpoch : 0;
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
  // 内核处理 TUN 与系统代理互斥，只需设置目标配置

  if (!coreElevated.value) {
    _applyTunConfig(true);
    if (Platform.isLinux) {
      // Linux: one-time setcap，重启后 capability 持久化，后续无需再提权
      final ok = await setupTunCapability();
      if (!ok) {
        _applyTunConfig(false);
        throw TunElevationException('授予网络权限失败，请确认 pkexec 及 patchelf 可用');
      }
      if (await relaunchSelf()) {
        exit(0);
      }
      // 启动新进程失败，回滚状态
      _applyTunConfig(false);
      throw TunElevationException('重启应用失败');
    } else if (Platform.isMacOS) {
      // macOS: 以 root 重启，传递 homeDir 避免 root 使用 /var/root 数据目录
      if (await relaunchElevated(homeDir: Constants.homeDir.path)) {
        exit(0);
      }
      _applyTunConfig(false);
      throw TunElevationException('提权失败，请重试');
    } else {
      // Windows: 以管理员重启，同一用户 %APPDATA% 不变，无需传 homeDir
      if (await relaunchElevated()) {
        exit(0);
      }
      _applyTunConfig(false);
      throw TunElevationException('提权失败，请重试');
    }
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
  _updateConfig((c) => c.copyWith(
    tun: TunConfig(enable: enable),
    mixedSystemProxy: enable ? false : c.mixedSystemProxy,
  ));
}

/// 提权重启后自动启用 TUN（仅内存，不持久化）。
void applyStartupTun() {
  clashConfig.value = clashConfig.value.copyWith(tun: TunConfig(enable: true));
  switchedAt = DateTime.now().millisecondsSinceEpoch;
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

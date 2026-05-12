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

Timer? _syncTimer;
Timer? _reloadTimer;
int? _lastSyncedPort;
bool _internalUpdate = false;

/// 应用主题模式：null 表示跟随系统。
final themeMode = signal<ThemeMode?>(null);

ThemeMode get resolvedThemeMode => themeMode.value ?? ThemeMode.system;

Future<void> initCoreConfig() async {
  if (CoreConfigStorage.exists()) {
    _updateConfig((_) => CoreConfigStorage.load());
  }
  _lastSyncedPort = clashConfig.value.mixedPort;
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
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 1), _saveToDisk);
    _scheduleReload();
  });
}

/// 保存配置到磁盘。移动端不持久化 tun 状态（每次启动以代理模式运行）。
void _saveToDisk() {
  var config = clashConfig.value;
  if (!Constants.isDesktop) {
    config = config.copyWith(tun: TunConfig(enable: false));
  }
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
  if (selectedFile.value == null) return;
  final state = LibCore.instance.stateSignal.value;
  LogFileWriter.instance?.log(
    '_scheduleReload: scheduled (file=${selectedFile.value}, tun=${clashConfig.value.tunEnabled}, state=$state)',
    name: 'tun',
  );
  _reloadTimer?.cancel();
  _reloadTimer = Timer(const Duration(seconds: 1), () async {
    if (clashConfig.value.tunEnabled) {
      LogFileWriter.instance?.log(
        '_scheduleReload: skipped (TUN active)',
        name: 'tun',
      );
      return;
    }
    final curState = LibCore.instance.stateSignal.value;
    if (curState == LibCore.kStateRunning ||
        curState == LibCore.kStateStarting) {
      LogFileWriter.instance?.log(
        '_scheduleReload: skipped (kernel $curState)',
        name: 'tun',
      );
      return;
    }
    LogFileWriter.instance?.log(
      '_scheduleReload: firing asyncProfile (tun=${clashConfig.value.tunEnabled})',
      name: 'tun',
    );
    asyncProfile();
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
    await openTun();
  } else {
    await closeTun();
  }
  LogFileWriter.instance?.log(
    'toggleTun($enable): ${sw.elapsedMilliseconds}ms',
    name: 'tun',
  );
}

Future<void> openTun() async {
  if (!Constants.isDesktop) {
    final file = selectedFile.value;
    if (file == null) return;
    final path = _resolveProfilePath(file);
    if (!File(path).existsSync()) return;

    try {
      _reloadTimer?.cancel();
      _setTunEnabled(true);
      final yamlContent = await File(path).readAsString();
      final merged = mergeProfileConfig(yamlContent);
      await LibCore.instance.connectVpn(
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
    vpnConnected.value = false;
    _setTunEnabled(false);
    // 先关闭 VPN 接口（不停内核），避免 refreshConfig 中 fdsan 崩溃
    await LibCore.instance.disconnectVpn();
    // fire-and-forget：内核后台热重载，FAB loading 由 StateUpdate 回调清除
    asyncProfile();
    return;
  }
  await _closeTunDesktop();
}

// --- Desktop TUN ---

Future<void> _openTunDesktop() async {
  // TUN 模式接管全部系统流量，需关闭系统代理避免浏览器绕过 TUN
  await closeProxy();

  if (!coreElevated.value) {
    _setTunEnabled(true);
    if (Platform.isLinux) {
      // Linux: one-time setcap，重启后 capability 持久化，后续无需再提权
      final ok = await setupTunCapability();
      if (!ok) {
        _setTunEnabled(false);
        throw TunElevationException('授予网络权限失败，请确认 pkexec 及 patchelf 可用');
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
  asyncProfile();
}

Future<void> _closeTunDesktop() async {
  _setTunEnabled(false);
  if (LibCore.instance.stateSignal.value != LibCore.kStateRunning) return;
  asyncProfile();
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

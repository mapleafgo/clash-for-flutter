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

final modeChanging = signal(false);

/// 应用主题模式：null 表示跟随系统。
final themeMode = signal<ThemeMode?>(null);

ThemeMode get resolvedThemeMode =>
    themeMode.value ?? ThemeMode.system;

Future<void> initCoreConfig() async {
  if (CoreConfigStorage.exists()) {
    _updateConfig((_) => CoreConfigStorage.load());
  }
  _lastSyncedPort = clashConfig.value.mixedPort;
  LogFileWriter.instance?.setMinLevel(clashConfig.value.logLevel ?? LogLevel.info);

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
  } catch (e) {
    LogFileWriter.instance?.log('setMode failed: $e', level: LogLevel.error, name: 'core_config');
  }
}

/// 通知内核切换模式，UI 状态由 setMode 成功后直接更新。
Future<void> changeMode(Mode mode) async {
  if (modeChanging.value) return;
  if (LibCore.instance.stateSignal.value < 2) return;
  modeChanging.value = true;
  try {
    await _syncModeToCore(mode);
  } catch (e) {
    LogFileWriter.instance?.log('changeMode error: $e', level: LogLevel.error, name: 'core_config');
  } finally {
    modeChanging.value = false;
  }
}

Future<void> changeModeStr(String mode) async {
  final m = Mode.values.where((v) => v.name == mode);
  if (m.isNotEmpty) return changeMode(m.first);
}

void _scheduleReload() {
  if (selectedFile.value == null) return;
  LogFileWriter.instance?.log(
    '_scheduleReload: scheduled (file=${selectedFile.value}, tun=${clashConfig.value.tunEnabled}, state=${LibCore.instance.stateSignal.value})',
    name: 'tun',
  );
  _reloadTimer?.cancel();
  _reloadTimer = Timer(const Duration(seconds: 1), () async {
    if (clashConfig.value.tunEnabled) {
      LogFileWriter.instance?.log('_scheduleReload: skipped (TUN active)', name: 'tun');
      return;
    }
    LogFileWriter.instance?.log(
      '_scheduleReload: firing asyncProfile (tun=${clashConfig.value.tunEnabled})',
      name: 'tun',
    );
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
  if (logLevel != null) {
    LogFileWriter.instance?.setMinLevel(logLevel);
  }
}

void watchModeFromCore() {
  // 模式变更由 setMode 成功后直接更新，无需事件回调
}

Future<void> toggleTun(bool enable) async {
  LogFileWriter.instance?.log('toggleTun($enable) called', name: 'tun');
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
      LogFileWriter.instance?.log('openTun: mobile path start (file=$file)', name: 'tun');
      _reloadTimer?.cancel();
      _setTunEnabled(true);
      final yamlContent = await File(path).readAsString();
      final merged = mergeProfileConfig(yamlContent);
      LogFileWriter.instance?.log(
        'openTun: calling connectVpn (merged=${merged.length} chars, tunEnabled=${clashConfig.value.tunEnabled})',
        name: 'tun',
      );
      await LibCore.instance.connectVpn(
        merged,
        ruleSetProxy: ruleSetProxy.value,
        ipv6: clashConfig.value.ipv6,
      );
      LogFileWriter.instance?.log('openTun: connectVpn completed', name: 'tun');
    } catch (e) {
      LogFileWriter.instance?.log('openTun: FAILED: $e', level: LogLevel.error, name: 'tun');
      _setTunEnabled(false);
      rethrow;
    }
    return;
  }
  await _openTunDesktop();
}

Future<void> closeTun() async {
  if (!Constants.isDesktop) {
    LogFileWriter.instance?.log('closeTun: mobile path start', name: 'tun');
    vpnConnected.value = false;
    await LibCore.instance.disconnectVpn();
    // _setTunEnabled 触发 effect 后 1 秒自动调度 asyncProfile 重启内核（代理模式），
    // 无需手动调用 asyncProfile() 避免双重重启。
    _setTunEnabled(false);
    LogFileWriter.instance?.log('closeTun: done', name: 'tun');
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
  if (LibCore.instance.stateSignal.value < 2) return;
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

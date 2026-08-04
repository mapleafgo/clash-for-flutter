import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/domain/enums.dart' show LogLevel;
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart'
    show coreConfig, mergeProfileConfig;
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';

/// 最近一次发送到内核的合并后配置。
final lastMergedConfig = signal<String?>(null);

/// 因内核处于 starting/stopping 等窗口期而被推迟的重载目标。
/// 状态转 running 后由 [flushPendingReload] 补发。
String? _pendingReloadPath;

/// 正在进行的重载，用于串行化：并发下发会让内核最终跑的配置不确定，
/// 且 lastMergedConfig 交错写入后与内核实际配置不符，回滚会滚到错的配置上。
Future<bool>? _activating;

/// 内核进入 running 后补发被推迟的重载。由 LibCore 的状态回调触发。
void flushPendingReload() {
  final path = _pendingReloadPath;
  if (path == null) return;
  _pendingReloadPath = null;
  LogFileWriter.instance?.log(
    'flushPendingReload: replaying deferred reload',
    name: 'profile',
  );
  _activateProfile(path);
}

/// 记录最近一次发送到内核的合并配置（内存，供回滚与状态恢复）。
void recordMergedConfig(String merged) {
  lastMergedConfig.value = merged;
}

/// 磁贴专用 TUN 缓存：只把 TUN 启动配置落盘 cache-tun.json。
/// 非 TUN 重载（系统代理/直连）不写，否则关闭 VPN 后磁贴会读到
/// 没有 tun inbound 的配置，建连后无网络且 TUN fd 无人关闭。
void writeTunConfigCache(String merged) {
  File(
    p.join(Constants.homeDir.path, Constants.tunConfigCache),
  ).writeAsStringSync(merged);
}

/// 记录合并配置并按需更新磁贴 TUN 缓存。
void cacheTunConfig(String merged) {
  recordMergedConfig(merged);
  writeTunConfigCache(merged);
}

void startWatchingSelectedFile() {
  // 内核转 running 时补发窗口期内被推迟的重载
  LibCore.instance.onKernelRunning = flushPendingReload;
  effect(() {
    final file = selectedFile.value;
    if (file == null) return;
    final path = p.isAbsolute(file)
        ? file
        : p.join(Constants.homeDir.path, Constants.profilesDir, file);
    if (!File(path).existsSync()) return;
    LogFileWriter.instance?.log(
      'startWatchingSelectedFile: activating profile $file (state=${LibCore.instance.stateSignal.peek()})',
      name: 'profile',
    );
    profileError.value = null;
    _activateProfile(path);
  });
}

/// Merge the profile JSON with the app's [SingboxConfig] overrides,
/// then hot-reload the core with the merged content.
///
/// 内核支持热重载，切换订阅/配置变更无需重启内核。
/// 提权重启等需要重启内核的场景由 enableTun 负责。
Future<bool> _activateProfile(String profilePath) {
  // 串行化：改端口武装的 1s 防抖定时器与手动开关代理可能并发下发两份配置，
  // 完成顺序不定会让内核最终跑旧配置。
  final previous = _activating;
  final next = previous == null
      ? _doActivateProfile(profilePath)
      : previous
            .then((_) => _doActivateProfile(profilePath))
            .catchError((_) => _doActivateProfile(profilePath));
  _activating = next;
  next.whenComplete(() {
    if (identical(_activating, next)) _activating = null;
  });
  return next;
}

Future<bool> _doActivateProfile(String profilePath) async {
  try {
    final profileContent = await File(profilePath).readAsString();
    final merged = mergeProfileConfig(profileContent);

    final state = LibCore.instance.stateSignal.peek();

    // 内核仍在启动中：此刻下发会报 "invalid state starting"
    // （自启时 toggleTun/toggleSystemProxy 与 startWatchingSelectedFile 并发触发）。
    // 但不能只是丢弃——否则 UI 已显示"已开启代理"而内核从未收到该配置，
    // 流量实际在裸奔。挂起，等状态转 running 时由 flushPendingReload 补发。
    if (state == LibCore.kStateStarting) {
      _pendingReloadPath = profilePath;
      LogFileWriter.instance?.log(
        '_activateProfile: core is starting, deferring reload',
        level: LogLevel.debug,
        name: 'profile',
      );
      return true;
    }

    // Flutter hot restart 重置 isolate 导致缓存为空，
    // 但内核进程仍在运行。此时同步缓存但不热重载，
    // 避免流量计数器归零
    if (lastMergedConfig.peek() == null && state == LibCore.kStateRunning) {
      recordMergedConfig(merged);
      if (coreConfig.value.tunEnabled) writeTunConfigCache(merged);
      return true;
    }

    // 清除旧统计数据（运行时长等），热重载后由新服务时间重新计时
    LibCore.instance.clearStats();

    // 预验证新配置
    try {
      final validationResult = await LibCore.instance.checkConfig(merged);
      if (validationResult.isNotEmpty) {
        profileError.value = validationResult;
        return false;
      }
    } catch (e) {
      LogFileWriter.instance?.log(
        'checkConfig failed: $e',
        level: LogLevel.warning,
        name: 'profile',
      );
    }

    try {
      await LibCore.instance.startCoreWithContent(
        merged,
        ruleSetProxy: ruleSetProxy.value,
        enabledVpn: coreConfig.value.tunEnabled,
      );
    } catch (e) {
      profileError.value = e.toString();
      LogFileWriter.instance?.log(
        '_activateProfile: startCoreWithContent failed: $e',
        level: LogLevel.error,
        name: 'profile',
      );
      await _rollbackToPreviousConfig(merged);
      return false;
    }

    recordMergedConfig(merged);
    if (coreConfig.value.tunEnabled) writeTunConfigCache(merged);
    profileError.value = null;
    return true;
  } catch (e) {
    profileError.value = e.toString();
    LogFileWriter.instance?.log(
      '_activateProfile: unexpected error: $e',
      level: LogLevel.error,
      name: 'profile',
    );
    return false;
  }
}

/// 新配置启动失败后，用上一份成功下发的配置恢复内核，
/// 避免切换订阅失败导致代理直接断线。失败原因仍保留在 [profileError]。
Future<void> _rollbackToPreviousConfig(String failed) async {
  final previous = lastMergedConfig.peek();
  if (previous == null || previous == failed) return;
  try {
    await LibCore.instance.startCoreWithContent(
      previous,
      ruleSetProxy: ruleSetProxy.value,
      enabledVpn: coreConfig.value.tunEnabled,
    );
    LogFileWriter.instance?.log(
      '_activateProfile: rolled back to previous config',
      level: LogLevel.warning,
      name: 'profile',
    );
  } catch (e) {
    LogFileWriter.instance?.log(
      '_activateProfile: rollback failed: $e',
      level: LogLevel.error,
      name: 'profile',
    );
  }
}

Future<bool> asyncProfile() async {
  final file = selectedFile.value;
  if (file == null) return true;
  // 快速开关防竞态：如果 TUN 已被重新启用，跳过这次无 TUN 的热重载
  if (!Constants.isDesktop && coreConfig.value.tunEnabled) return true;
  final path = p.isAbsolute(file)
      ? file
      : p.join(Constants.homeDir.path, Constants.profilesDir, file);
  return _activateProfile(path);
}

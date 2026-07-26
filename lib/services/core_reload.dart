import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/domain/enums.dart' show LogLevel;
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart'
    show clashConfig, mergeProfileConfig;
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';


/// 最近一次发送到内核的合并后配置。
final lastMergedConfig = signal<String?>(null);

/// 缓存上次发送的合并配置：同时写入 signal 和磁盘文件。
void _cacheMergedConfig(String merged) {
  lastMergedConfig.value = merged;
  File(p.join(Constants.homeDir.path, Constants.mergedConfigCache))
      .writeAsStringSync(merged);
}

void startWatchingSelectedFile() {
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

/// Merge the profile YAML with the app's [ClashConfig] overrides,
/// then hot-reload the core with the merged content.
///
/// 内核支持热重载，切换订阅/配置变更无需重启内核。
/// 提权重启等需要重启内核的场景由 enableTun 负责。
Future<bool> _activateProfile(String yamlPath) async {
  try {
    final yamlContent = await File(yamlPath).readAsString();
    final merged = mergeProfileConfig(yamlContent);

    final state = LibCore.instance.stateSignal.peek();

    // 内核仍在启动中：跳过避免 "invalid state starting" 错误
    // （自启时 toggleTun/toggleSystemProxy 与 startWatchingSelectedFile 并发触发）
    if (state == LibCore.kStateStarting) {
      LogFileWriter.instance?.log(
        '_activateProfile: core is starting, skipping reload',
        level: LogLevel.debug,
        name: 'profile',
      );
      return true;
    }

    // Flutter hot restart 重置 isolate 导致缓存为空，
    // 但内核进程仍在运行。此时同步缓存但不热重载，
    // 避免流量计数器归零
    if (lastMergedConfig.peek() == null && state == LibCore.kStateRunning) {
      _cacheMergedConfig(merged);
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
        enabledVpn: clashConfig.value.tunEnabled,
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

    _cacheMergedConfig(merged);
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
      enabledVpn: clashConfig.value.tunEnabled,
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
  if (!Constants.isDesktop && clashConfig.value.tunEnabled) return true;
  final path = p.isAbsolute(file)
      ? file
      : p.join(Constants.homeDir.path, Constants.profilesDir, file);
  return _activateProfile(path);
}

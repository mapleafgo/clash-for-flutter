import 'dart:io';

import 'package:singcast/core/lib_core.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart' show clashConfig, mergeProfileConfig;
import 'package:singcast/utils/constants.dart';
import 'package:singcast/domain/enums.dart' show LogLevel;
import 'package:singcast/utils/log_file.dart';
import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';

final coreActivating = signal(false);

String? _lastWorkingConfig;

void startWatchingSelectedFile() {
  effect(() {
    final file = selectedFile.value;
    if (file == null) return;
    final path = p.isAbsolute(file)
        ? file
        : '${Constants.homeDir.path}${Constants.profilesPath}/$file';
    if (!File(path).existsSync()) return;
    LogFileWriter.instance?.log(
      'startWatchingSelectedFile: activating profile $file (state=${LibCore.instance.stateSignal.peek()})',
      name: 'tun',
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
  coreActivating.value = true;
  final previousConfig = _lastWorkingConfig;

  try {
    final yamlContent = await File(yamlPath).readAsString();
    final merged = mergeProfileConfig(yamlContent);

    // Flutter hot restart 重置 isolate 导致 _lastWorkingConfig 为空，
    // 但内核进程仍在运行。此时同步 _lastWorkingConfig 但不热重载，
    // 避免流量计数器归零
    if (_lastWorkingConfig == null &&
        LibCore.instance.stateSignal.peek() == LibCore.kStateRunning) {
      _lastWorkingConfig = merged;
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
    } catch (_) {}

    try {
      await LibCore.instance.startCoreWithContent(
        merged,
        ruleSetProxy: ruleSetProxy.value,
      );
    } catch (e) {
      LogFileWriter.instance?.log(
        '_activateProfile: startCoreWithContent failed: $e',
        level: LogLevel.error,
        name: 'tun',
      );
      if (previousConfig != null) {
        try {
          await LibCore.instance.startCoreWithContent(
            previousConfig,
            ruleSetProxy: ruleSetProxy.value,
          );
          profileError.value = e.toString();
        } catch (_) {
          profileError.value = e.toString();
        }
      } else {
        profileError.value = e.toString();
      }
      return false;
    }

    _lastWorkingConfig = merged;
    profileError.value = null;
    return true;
  } catch (e) {
    profileError.value = e.toString();
    LogFileWriter.instance?.log(
      '_activateProfile: unexpected error: $e',
      level: LogLevel.error,
      name: 'tun',
    );
    return false;
  } finally {
    coreActivating.value = false;
  }
}

Future<bool> asyncProfile() async {
  final file = selectedFile.value;
  if (file == null) return true;
  // 快速开关防竞态：如果 TUN 已被重新启用，跳过这次无 TUN 的热重载
  if (!Constants.isDesktop && clashConfig.value.tunEnabled) return true;
  final path = p.isAbsolute(file)
      ? file
      : '${Constants.homeDir.path}${Constants.profilesPath}/$file';
  return _activateProfile(path);
}

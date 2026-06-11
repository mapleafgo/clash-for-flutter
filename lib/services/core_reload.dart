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

/// 最近一次发送到内核的合并后配置（待机/TUN 关闭）。
final mergedConfigStandby = signal<String?>(null);

/// 最近一次发送到内核的合并后配置（TUN 开启）。
final mergedConfigProxy = signal<String?>(null);

/// 当前生效的合并后配置（指向待机或代理开启配置）。
final lastMergedConfig = computed(() {
  if (mergedConfigProxy.value != null) return mergedConfigProxy.value;
  return mergedConfigStandby.value;
});

String get _standbyPath =>
    p.join(Constants.homeDir.path, Constants.mergedConfigCacheStandby);
String get _proxyPath =>
    p.join(Constants.homeDir.path, Constants.mergedConfigCacheProxy);

/// 缓存待机配置（TUN 关闭）：同时写入 signal 和磁盘文件。
void cacheMergedConfigStandby(String merged) {
  mergedConfigStandby.value = merged;
  File(_standbyPath).writeAsStringSync(merged);
}

/// 缓存代理开启配置（TUN 开启）：同时写入 signal 和磁盘文件。
void cacheMergedConfigProxy(String merged) {
  mergedConfigProxy.value = merged;
  File(_proxyPath).writeAsStringSync(merged);
}

/// 从磁盘恢复缓存到 signal。
void restoreMergedConfigCache() {
  final standbyFile = File(_standbyPath);
  if (standbyFile.existsSync()) {
    mergedConfigStandby.value = standbyFile.readAsStringSync();
  }
  final proxyFile = File(_proxyPath);
  if (proxyFile.existsSync()) {
    mergedConfigProxy.value = proxyFile.readAsStringSync();
  }
}

/// 根据当前 TUN 状态写入对应缓存。
void _cacheByTunState(String merged) {
  if (clashConfig.value.tunEnabled) {
    cacheMergedConfigProxy(merged);
  } else {
    cacheMergedConfigStandby(merged);
  }
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

    // Flutter hot restart 重置 isolate 导致缓存为空，
    // 但内核进程仍在运行。此时同步缓存但不热重载，
    // 避免流量计数器归零
    if (lastMergedConfig.peek() == null &&
        LibCore.instance.stateSignal.peek() == LibCore.kStateRunning) {
      _cacheByTunState(merged);
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
      return false;
    }

    _cacheByTunState(merged);
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

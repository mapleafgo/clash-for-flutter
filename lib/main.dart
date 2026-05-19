import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/core/tun_elevation.dart';
import 'package:singcast/data/local/core_config_storage.dart';
import 'package:singcast/presentation/app.dart' show App, appReady;
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/services/tray_service.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Defaults.init();

  if (Constants.isDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        minimumSize: Size(460, 600),
        size: Size(630, 580),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.show();
      },
    );
  }

  timeago.setLocaleMessages('zh_cn', TimeagoZhCnMessages());

  // 提权重启时通过文件标记 /tmp/.singcast_pending 恢复状态：
  // - 文件存在（返回值 != null） → 需要自动启用 TUN
  // - 返回值非空字符串 → macOS root 场景下的用户数据目录路径
  final pendingResult = checkAndConsumePending();
  final tunPending = pendingResult != null;
  Constants.homeDir = (pendingResult != null && pendingResult.isNotEmpty)
      ? Directory(pendingResult)
      : await getApplicationSupportDirectory();
  CoreConfigStorage.createDefault();

  // 初始化内核和配置
  runApp(const App());
  await _initApp(tunPending: tunPending);
  appReady.value = true;

  if (Constants.isDesktop) {
    await initTray();
    windowManager.addListener(_WindowListener());
  }
}

Future<void> _initApp({bool tunPending = false}) async {
  final sw = Stopwatch()..start();

  await LibCore.instance.init();
  _log('[startup] LibCore.init: ${sw.elapsedMilliseconds}ms state=${LibCore.instance.stateSignal.peek()}');

  // initCore 是幂等的 — 冷启动时初始化内核，引擎重建时跳过
  try {
    await LibCore.instance
        .initCore(Constants.homeDir.path)
        .timeout(const Duration(seconds: 10));
  } on TimeoutException {
    initError.value = '内核初始化超时';
  } catch (e) {
    initError.value = '内核初始化失败: $e';
  }
  _log('[startup] initCore: ${sw.elapsedMilliseconds}ms state=${LibCore.instance.stateSignal.peek()}');

  await initCoreConfig();
  _log('[startup] initCoreConfig: ${sw.elapsedMilliseconds}ms');

  watchModeFromCore();
  initAppConfig();
  _log('[startup] initAppConfig: ${sw.elapsedMilliseconds}ms');

  // 移动端：引擎重建恢复时内核可能仍在运行，同步真实状态
  if (!Constants.isDesktop) {
    await LibCore.instance.syncKernelState();
    final syncedState = LibCore.instance.stateSignal.peek();
    _log('[startup] syncKernelState: ${sw.elapsedMilliseconds}ms syncedState=$syncedState');
    if (syncedState == LibCore.kStateRunning) {
      vpnConnected.value = true;
      ensureTunEnabled(true);
      _log('[startup] restored VPN state: vpnConnected=true tunEnabled=true');
    }
  }

  // 提权重启后自动启用 TUN（标记文件由 relaunchSelf/relaunchElevated 写入 /tmp）
  // 必须在 startWatchingSelectedFile 之前，确保 effect 触发时 clashConfig 已含 TUN 配置
  _log('[startup] tunPending=$tunPending executableArguments: ${Platform.executableArguments}');
  if (tunPending) {
    applyStartupTun();
    _log('[startup] applyStartupTun: auto-enabling TUN after elevation restart');
  }

  startWatchingSelectedFile();
  _log('[startup] startWatchingSelectedFile: ${sw.elapsedMilliseconds}ms file=${selectedFile.value} state=${LibCore.instance.stateSignal.peek()}');

  // 有配置文件且内核未运行时，直接激活 profile（不 await，内核后台启动，UI 先渲染）
  final state = LibCore.instance.stateSignal.peek();
  if (selectedFile.value != null && state != LibCore.kStateRunning && state != LibCore.kStateStarting) {
    asyncProfile();
  }

  // 无配置文件时内核不会启动，手动将状态设为"就绪"
  if (selectedFile.value == null && LibCore.instance.stateSignal.peek() == LibCore.kStateCreated) {
    LibCore.instance.stateSignal.value = LibCore.kStateInitialized;
  }
  _log('[startup] done: ${sw.elapsedMilliseconds}ms finalState=${LibCore.instance.stateSignal.peek()}');
}

void _log(String msg) {
  print(msg);
  LogFileWriter.instance?.log(msg, name: 'startup');
}

class _WindowListener with WindowListener {
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  @override
  void onWindowFocus() {
    WidgetsBinding.instance.focusManager.primaryFocus?.unfocus();
  }
}

class TimeagoZhCnMessages extends timeago.LookupMessages {
  @override
  String prefixAgo() => '';
  @override
  String prefixFromNow() => '';
  @override
  String suffixAgo() => '前';
  @override
  String suffixFromNow() => '后';
  @override
  String lessThanOneMinute(int seconds) => '刚刚';
  @override
  String aboutAMinute(int minutes) => '1 分钟';
  @override
  String minutes(int minutes) => '$minutes 分钟';
  @override
  String aboutAnHour(int minutes) => '1 小时';
  @override
  String hours(int hours) => '$hours 小时';
  @override
  String aDay(int hours) => '1 天';
  @override
  String days(int days) => '$days 天';
  @override
  String aboutAMonth(int days) => '1 个月';
  @override
  String months(int months) => '$months 个月';
  @override
  String aboutAYear(int year) => '1 年';
  @override
  String years(int years) => '$years 年';
  @override
  String wordSeparator() => '';
}

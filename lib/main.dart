import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/data/local/core_config_storage.dart';
import 'package:singcast/presentation/app.dart' show App, appReady;
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/services/tray_service.dart';
import 'package:singcast/utils/constants.dart';
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

  // 提权重启时通过 --home-dir 指定用户数据目录，避免 root 使用 /var/root
  final homeDirOverride = _parseHomeDirArg();
  Constants.homeDir = homeDirOverride != null
      ? Directory(homeDirOverride)
      : await getApplicationSupportDirectory();
  CoreConfigStorage.createDefault();

  // 初始化内核和配置
  runApp(const App());
  await _initApp();
  appReady.value = true;

  if (Constants.isDesktop) {
    await initTray();
    windowManager.addListener(_WindowListener());
  }
}

Future<void> _initApp() async {
  final sw = Stopwatch()..start();

  await LibCore.instance.init();
  print('[startup] LibCore.init: ${sw.elapsedMilliseconds}ms state=${LibCore.instance.stateSignal.peek()}');

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
  print('[startup] initCore: ${sw.elapsedMilliseconds}ms state=${LibCore.instance.stateSignal.peek()}');

  await initCoreConfig();
  print('[startup] initCoreConfig: ${sw.elapsedMilliseconds}ms');

  watchModeFromCore();
  initAppConfig();
  print('[startup] initAppConfig: ${sw.elapsedMilliseconds}ms');

  // 移动端：引擎重建恢复时内核可能仍在运行，同步真实状态
  if (!Constants.isDesktop) {
    await LibCore.instance.syncKernelState();
    final syncedState = LibCore.instance.stateSignal.peek();
    print('[startup] syncKernelState: ${sw.elapsedMilliseconds}ms syncedState=$syncedState');
    if (syncedState == LibCore.kStateRunning) {
      vpnConnected.value = true;
      ensureTunEnabled(true);
      print('[startup] restored VPN state: vpnConnected=true tunEnabled=true');
    }
  }

  startWatchingSelectedFile();
  print('[startup] startWatchingSelectedFile: ${sw.elapsedMilliseconds}ms file=${selectedFile.value} state=${LibCore.instance.stateSignal.peek()}');

  // 有配置文件且内核未运行时，直接激活 profile（不 await，内核后台启动，UI 先渲染）
  final state = LibCore.instance.stateSignal.peek();
  if (selectedFile.value != null && state != LibCore.kStateRunning && state != LibCore.kStateStarting) {
    asyncProfile();
  }

  // 无配置文件时内核不会启动，手动将状态设为"就绪"
  if (selectedFile.value == null && LibCore.instance.stateSignal.peek() == LibCore.kStateCreated) {
    LibCore.instance.stateSignal.value = LibCore.kStateInitialized;
  }
  print('[startup] done: ${sw.elapsedMilliseconds}ms finalState=${LibCore.instance.stateSignal.peek()}');
}

/// 解析 --home-dir 命令行参数，提权重启时用于指定用户数据目录。
String? _parseHomeDirArg() {
  final args = Platform.executableArguments;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--home-dir') return args[i + 1];
  }
  return null;
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

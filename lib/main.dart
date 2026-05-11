import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/data/local/core_config_storage.dart';
import 'package:singcast/presentation/app.dart';
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
  await _initApp();

  if (Constants.isDesktop) {
    await initTray();
    windowManager.addListener(_WindowListener());
  }

  runApp(const App());
}

Future<void> _initApp() async {
  await LibCore.instance.init();

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

  await initCoreConfig();
  watchModeFromCore();
  initAppConfig();

  // 移动端：同步 VPN 运行状态（引擎重建恢复时内核可能仍在运行）
  if (!Constants.isDesktop) {
    try {
      if (await LibCore.instance.isVpnRunning()) {
        vpnConnected.value = true;
        ensureTunEnabled(true);
        LibCore.instance.syncRunningState();
      }
    } catch (_) {}
  }

  startWatchingSelectedFile();

  // 无配置文件时内核不会启动，手动将状态设为"就绪"避免 UI 持续 loading
  if (selectedFile.value == null && LibCore.instance.stateSignal.peek() == 0) {
    LibCore.instance.stateSignal.value = 1;
  }
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

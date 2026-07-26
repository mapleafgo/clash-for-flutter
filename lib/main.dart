import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/data/local/core_config_storage.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/i18n/strings.g.dart';
import 'package:singcast/presentation/app.dart' show App;
import 'package:singcast/presentation/app_state.dart' show appReady;
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/app_lifecycle.dart' show initTerminationHook;
import 'package:singcast/services/core_reload.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/services/deep_link.dart';
import 'package:singcast/services/startup_service.dart'
    show autostartArg, enableAutostartArg, setAutoStart;
import 'package:singcast/services/startup_checks.dart';
import 'package:singcast/services/tray_service.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:window_manager/window_manager.dart';

void main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();

  autoStartFromArgs = arguments.contains(autostartArg);
  enableAutostartRequested = arguments.contains(enableAutostartArg);

  await Defaults.init();

  // 初始化语言：优先使用设备语言，非中英文时 fallback 到中文
  LocaleSettings.useDeviceLocale();
  if (!{AppLocale.zh, AppLocale.en}.contains(LocaleSettings.currentLocale)) {
    LocaleSettings.setLocale(AppLocale.en);
  }

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
        if (!autoStartFromArgs) {
          await windowManager.show();
        }
        // 自启场景：不 show()，窗口保持隐藏到托盘
      },
    );
  }

  timeago.setLocaleMessages('zh_cn', TimeagoZhCnMessages());

  Constants.homeDir = await getApplicationSupportDirectory();
  CoreConfigStorage.createDefault();

  // 初始化内核和配置
  runApp(const App());

  if (Constants.isDesktop) {
    await initTray();
    windowManager.addListener(_WindowListener());
    initTerminationHook();
  }

  // 任何初始化异常都不能让 appReady 永远为 false —— 否则 UI 永久卡在闪屏，
  // 用户看不到任何错误，托盘/深链/心跳也都不会启动。
  try {
    await _initApp();
  } catch (e, st) {
    _log('[startup] _initApp failed: $e\n$st');
    initError.value ??= '$e';
  }
  appReady.value = true;

  LibCore.instance.startHeartbeat();
  runStartupChecks();
  initDeepLinks();
}

Future<void> _initApp() async {
  final sw = Stopwatch()..start();

  try {
    await LibCore.instance.init();
  } catch (e) {
    _log('[startup] LibCore.init failed: $e');
    initError.value = t.core.connectionFailed(error: '$e');
  }
  _log(
    '[startup] LibCore.init: ${sw.elapsedMilliseconds}ms state=${LibCore.instance.stateSignal.peek()}',
  );

  // 内核连接失败时跳过后续初始化，让 UI 正常进入首页显示错误
  if (initError.value != null) {
    appReady.value = true;
    return;
  }

  // initCore 是幂等的 — 冷启动时初始化内核，引擎重建时跳过
  try {
    await LibCore.instance
        .initCore(Constants.homeDir.path)
        .timeout(const Duration(seconds: 10));
  } on TimeoutException {
    initError.value = t.core.initTimeout;
  } catch (e) {
    initError.value = t.core.initFailed(error: '$e');
  }
  _log(
    '[startup] initCore: ${sw.elapsedMilliseconds}ms state=${LibCore.instance.stateSignal.peek()}',
  );

  await initCoreConfig();
  _log('[startup] initCoreConfig: ${sw.elapsedMilliseconds}ms');

  initAppConfig();
  _log('[startup] initAppConfig: ${sw.elapsedMilliseconds}ms');

  // 安装器勾选"开机自启"后首次启动：统一走应用内通道注册系统自启项
  // （注册表 Run / SMAppService / .desktop），并写入 settings.json，使设置页
  // 开关与系统真实状态一致。由 Inno postinstall 以 --enable-autostart 启动触发。
  if (enableAutostartRequested) {
    try {
      await setAutoStart(true);
      autoStart.value = true;
    } catch (e) {
      _log('[startup] enable-autostart failed: $e');
    }
  }

  if (Platform.isIOS) {
    // iOS：RPC 未连接，如果 VPN 正在运行，需要先连接 RPC 再同步状态
    final vpnRunning = await LibCore.instance.isVpnRunning();
    if (vpnRunning) {
      try {
        await LibCore.instance.connectIpc();
      } catch (e) {
        _log('[startup] iOS connectIpc failed: $e');
      }
      await LibCore.instance.syncKernelState();
      vpnConnected.value = true;
      ensureTunEnabled(true);
      _log(
        '[startup] iOS tunnel running: synced '
        'state=${LibCore.instance.stateSignal.peek()}',
      );
    } else {
      _log('[startup] iOS tunnel not running');
    }
  } else if (!Constants.isDesktop) {
    // Android：内核在本进程，引擎重建恢复时内核可能仍在运行，同步真实状态
    await LibCore.instance.syncKernelState();
    final vpnRunning = await LibCore.instance.isVpnRunning();
    if (vpnRunning) {
      vpnConnected.value = true;
      ensureTunEnabled(true);
      _log('[startup] VPN running, synced vpnConnected=true tunEnabled=true');
    }
  } else {
    // 桌面端：LibCore.init() 已通过 syncKernelState 恢复状态
    final syncedState = LibCore.instance.stateSignal.peek();
    _log('[startup] desktop state after syncKernelState: $syncedState');
    // 内核仍在运行时（如前端重启但 core 存活），恢复代理开关。TUN/系统代理不
    // 持久化，从磁盘加载为 false；若不同步到 tunIf，后续配置变更触发的重载会
    // 生成零 inbound 配置导致 TUN 消失断网。
    if (syncedState == LibCore.kStateRunning) {
      ensureProxyMode(tunIf.value == true);
    }
    // restart / uninstallServiceAndRestart 后统一重新激活内核
    LibCore.instance.onProcessReady = () async {
      if (selectedFile.value == null) return;
      // 先恢复代理开关再重载，顺序不能反
      ensureProxyMode(tunIf.value == true);
      await asyncProfile();
    };
    // 自启时 onProcessReady 不触发，直接恢复上次代理模式
    if (autoStartFromArgs && selectedFile.value != null) {
      try {
        if (tunIf.value == true) {
          await toggleTun(true);
        } else {
          await toggleSystemProxy(true);
        }
      } catch (e) {
        LogFileWriter.instance?.log(
          '开机自启连接代理失败: $e',
          level: LogLevel.error,
          name: 'autostart',
        );
      }
    }
  }

  startWatchingSelectedFile();
  _log(
    '[startup] startWatchingSelectedFile: ${sw.elapsedMilliseconds}ms file=${selectedFile.value} state=${LibCore.instance.stateSignal.peek()}',
  );

  // 无配置文件时内核不会启动，手动将状态设为"就绪"
  if (selectedFile.value == null &&
      LibCore.instance.stateSignal.peek() == LibCore.kStateCreated) {
    LibCore.instance.stateSignal.value = LibCore.kStateInitialized;
  }
  _log(
    '[startup] done: ${sw.elapsedMilliseconds}ms finalState=${LibCore.instance.stateSignal.peek()}',
  );
}

/// 标记应用是否通过开机自启启动（命令行携带 autostartArg 参数）。
late bool autoStartFromArgs;

/// 标记安装器是否请求开启自启（命令行携带 enableAutostartArg 参数）。
late bool enableAutostartRequested;

void _log(String msg) {
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

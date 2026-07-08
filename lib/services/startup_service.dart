import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:singcast/utils/constants.dart';

/// 初始化 launch_at_startup 插件，注册 appName / appPath / args。
///
/// 仅桌面端执行，在 main() 中调用一次。
/// args 携带 `--autostart` 标记，启动时用于判断是否为自启场景。
Future<void> initStartupService() async {
  if (!Constants.isDesktop) return;
  launchAtStartup.setup(
    appName: 'Singcast',
    appPath: Platform.resolvedExecutable,
    args: ['--autostart'],
  );
}

/// 开启或关闭开机自启。
///
/// 由设置页开关调用，实际注册/注销系统自启项。
/// 不修改 [autoStart] signal，调用方负责更新信号。
Future<void> setAutoStart(bool enabled) async {
  if (!Constants.isDesktop) return;
  if (enabled) {
    await launchAtStartup.enable();
  } else {
    await launchAtStartup.disable();
  }
}

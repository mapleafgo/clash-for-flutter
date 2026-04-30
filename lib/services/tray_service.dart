import 'dart:io';

import 'package:singcast/domain/enums.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/utils/constants.dart';
import 'package:desktop_tray/desktop_tray.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:window_manager/window_manager.dart';

Future<void> initTray() async {
  if (!Constants.isDesktop) return;

  await desktopTray.setIcon(
    Platform.isWindows ? 'assets/icon.ico' : 'assets/logo_64.png',
  );

  desktopTray.addListener(_TrayHandler());

  effect(() => _rebuildMenu(systemProxy.value, clashConfig.value.mode));
}

Future<void> _rebuildMenu(bool proxyOn, Mode? mode) async {
  final menu = TrayMenu(
    items: [
      TrayMenuItem(label: '显示窗口', key: 'show'),
      TrayMenuItem.separator(),
      TrayMenuItem.checkbox(label: '系统代理', key: 'proxy', checked: proxyOn),
      TrayMenuItem.separator(),
      TrayMenuItem.checkbox(
        label: '规则模式',
        key: Mode.rule.name,
        checked: mode == Mode.rule,
      ),
      TrayMenuItem.checkbox(
        label: '全局模式',
        key: Mode.global.name,
        checked: mode == Mode.global,
      ),
      TrayMenuItem.checkbox(
        label: '直连模式',
        key: Mode.direct.name,
        checked: mode == Mode.direct,
      ),
      TrayMenuItem.separator(),
      TrayMenuItem(label: '退出', key: 'exit'),
    ],
  );
  await desktopTray.setContextMenu(menu);
}

class _TrayHandler with DesktopTrayListener {
  @override
  void onTrayIconMouseDown() => windowManager.show();

  @override
  void onTrayIconRightMouseDown() => desktopTray.popUpContextMenu();

  @override
  void onTrayMenuItemClick(TrayMenuItem item) async {
    switch (item.key) {
      case 'show':
        await windowManager.show();
      case 'proxy':
        if (item.checked ?? false) {
          await closeProxy();
        } else {
          await openProxy();
        }
      case 'exit':
        await closeProxy();
        await windowManager.close();
        await windowManager.destroy();
      default:
        final mode = Mode.values.where((m) => m.name == item.key);
        if (mode.isNotEmpty) changeMode(mode.first);
    }
  }
}

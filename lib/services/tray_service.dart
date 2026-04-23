import 'dart:io';

import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/services/app_config.dart';
import 'package:clash_for_flutter/services/core_config.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

Future<void> initTray() async {
  if (!Constants.isDesktop) return;

  await trayManager.setIcon(
    Platform.isWindows ? 'assets/icon.ico' : 'assets/logo_64.png',
  );

  effect(() => _rebuildMenu(systemProxy.value, clashConfig.value.mode));
}

Future<void> _rebuildMenu(bool proxyOn, Mode? mode) async {
  final menu = Menu(items: [
    MenuItem(key: 'show', label: '显示窗口'),
    MenuItem.separator(),
    MenuItem.checkbox(key: 'proxy', label: '代理', checked: proxyOn),
    MenuItem.submenu(
      label: '模式',
      submenu: Menu(items: [
        MenuItem.checkbox(key: Mode.rule.name, label: 'Rule', checked: mode == Mode.rule),
        MenuItem.checkbox(key: Mode.global.name, label: 'Global', checked: mode == Mode.global),
        MenuItem.checkbox(key: Mode.direct.name, label: 'Direct', checked: mode == Mode.direct),
      ]),
    ),
    MenuItem(key: 'exit', label: '退出'),
  ]);
  await trayManager.setContextMenu(menu);
}

class TrayListenerImpl with TrayListener {
  @override
  void onTrayIconMouseDown() => windowManager.show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
      case 'proxy':
        if (menuItem.checked ?? false) {
          await closeProxy();
        } else {
          await openProxy();
        }
      case 'exit':
        await closeProxy();
        windowManager.close().then((_) => windowManager.destroy());
      default:
        final mode = Mode.values.where((m) => m.name == menuItem.key);
        if (mode.isNotEmpty) updateClashConfig(mode: mode.first);
    }
  }
}

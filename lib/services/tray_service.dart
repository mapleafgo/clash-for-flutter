import 'dart:io';

import 'package:singcast/core/lib_core.dart';
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

  effect(() => _rebuildMenu(
    tunIf.value == true ? clashConfig.value.tunEnabled : clashConfig.value.systemProxyEnabled,
    LibCore.instance.availableModesSignal.value,
    LibCore.instance.modeSignal.value,
  ));
}

const _trayModeLabels = {
  'rule': '规则',
  'global': '全局',
  'direct': '直连',
};

Future<void> _rebuildMenu(bool proxyOn, List<String> modes, String current) async {
  final modeItems = modes.map((m) => TrayMenuItem.checkbox(
    label: _trayModeLabels[m] ?? m,
    key: m,
    checked: m == current,
  )).toList();
  final isTunMode = tunIf.value == true;
  final proxyLabel = isTunMode ? 'TUN 模式' : '系统代理';
  final menu = TrayMenu(
    items: [
      TrayMenuItem(label: '显示窗口', key: 'show'),
      TrayMenuItem.separator(),
      TrayMenuItem.checkbox(label: proxyLabel, key: 'proxy', checked: proxyOn),
      if (modeItems.isNotEmpty) ...[
        TrayMenuItem.separator(),
        ...modeItems,
      ],
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
        final isTun = tunIf.value == true;
        if (isTun) {
          await toggleTun(!(item.checked ?? false));
        } else {
          await toggleSystemProxy(!(item.checked ?? false));
        }
      case 'exit':
        await LibCore.instance.destroyCore();
        await windowManager.close();
        await windowManager.destroy();
      default:
        if (item.key != null) changeModeStr(item.key!);
    }
  }
}

import 'dart:io';

import 'package:singcast/core/lib_core.dart';
import 'package:singcast/presentation/app_state.dart' show appReady;
import 'package:singcast/presentation/router.dart' show navigatorKey;
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/dialog.dart' show showErrorDialog;
import 'package:desktop_tray/desktop_tray.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:singcast/i18n/strings.g.dart';
import 'package:singcast/utils/format.dart' show modeLabel;
import 'package:singcast/utils/log_file.dart' show LogFileWriter;
import 'package:window_manager/window_manager.dart';

Future<void> initTray() async {
  if (!Constants.isDesktop) return;

  await desktopTray.setIcon(
    Platform.isWindows ? 'assets/icon.ico' : 'assets/logo_64.png',
  );

  desktopTray.addListener(_TrayHandler());

  effect(() => _rebuildMenu(
    _proxyEnabled,
    LibCore.instance.availableModesSignal.value,
    LibCore.instance.modeSignal.value,
  ));

  // rebuild tray labels when locale changes
  effect(() {
    localeVersion.value;
    _rebuildMenu(
      _proxyEnabled,
      LibCore.instance.availableModesSignal.peek(),
      LibCore.instance.modeSignal.peek(),
    );
  });
}

bool get _proxyEnabled =>
    tunIf.value == true ? coreConfig.value.tunEnabled : coreConfig.value.systemProxyEnabled;


Future<void> _rebuildMenu(bool proxyOn, List<String> modes, String current) async {
  final ready = appReady.value;
  final menu = TrayMenu(
    items: [
      TrayMenuItem(label: t.tray.showWindow, key: 'show'),
      if (ready) ...[
        TrayMenuItem.separator(),
        TrayMenuItem.checkbox(
          label: tunIf.value == true ? t.tray.tunMode : t.tray.systemProxy,
          key: 'proxy',
          checked: proxyOn,
        ),
        if (modes.isNotEmpty) ...[
          TrayMenuItem.separator(),
          ...modes.map((m) => TrayMenuItem.checkbox(
            label: modeLabel(m),
            key: m,
            checked: m == current,
          )),
        ],
      ],
      TrayMenuItem.separator(),
      TrayMenuItem(label: t.tray.exit, key: 'exit'),
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
        try {
          final isTun = tunIf.value == true;
          if (isTun) {
            await toggleTun(!(item.checked ?? false));
          } else {
            await toggleSystemProxy(!(item.checked ?? false));
          }
        } catch (e) {
          final ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) showErrorDialog(ctx, e.toString());
        } finally {
          _rebuildMenu(
            _proxyEnabled,
            LibCore.instance.availableModesSignal.value,
            LibCore.instance.modeSignal.value,
          );
        }
      case 'exit':
        // 先 flush 设置：防抖定时器里还压着最近 1s 的改动
        try {
          flushAppConfig();
        } catch (_) {}
        try {
          await LibCore.instance.dispose();
        } catch (_) {}
        await LogFileWriter.instance?.close();
        await windowManager.close();
        await windowManager.destroy();
      default:
        if (item.key != null) changeModeStr(item.key!);
    }
  }
}

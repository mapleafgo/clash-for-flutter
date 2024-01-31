import 'dart:io';

import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/source/app_config.dart';
import 'package:clash_for_flutter/app/source/core_config.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:mobx/mobx.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 托盘菜单控制类
class TrayController extends Disposable with TrayListener {
  final _config = Modular.get<AppConfig>();
  final _core = Modular.get<CoreConfig>();

  Future<void> init() async {
    trayManager.addListener(this);
    // 监听系统代理
    reaction(
      (_) => _config.systemProxy,
      (status) {
        _menuReset(isChecked: status, mode: _core.clash.mode ?? Mode.Rule);
      },
    );
    // 监听代理模式
    reaction(
      (_) => _core.clash.mode,
      (mode) {
        _menuReset(isChecked: _config.systemProxy, mode: mode ?? Mode.Rule);
      },
    );
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/icon.ico' : 'assets/logo_64.png',
    );
    // 初始化托盘菜单
    await _menuReset(
      isChecked: _config.systemProxy,
      mode: _core.clash.mode ?? Mode.Rule,
    );
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
  }

  Future<void> _menuReset({required bool isChecked, required Mode mode}) async {
    final Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: '显示窗口',
        ),
        MenuItem.separator(),
        MenuItem.checkbox(key: 'proxy', label: '代理', checked: isChecked),
        MenuItem.submenu(
          label: '模式',
          submenu: Menu(
            items: [
              MenuItem.checkbox(
                key: Mode.Rule.value,
                label: Mode.Rule.value,
                checked: mode == Mode.Rule,
              ),
              MenuItem.checkbox(
                key: Mode.Global.value,
                label: Mode.Global.value,
                checked: mode == Mode.Global,
              ),
              MenuItem.checkbox(
                key: Mode.Direct.value,
                label: Mode.Direct.value,
                checked: mode == Mode.Direct,
              ),
            ],
          ),
        ),
        MenuItem(
          label: '退出',
          key: 'exit_app',
        )
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show_window') {
      windowManager.show();
    } else if (menuItem.key == 'proxy') {
      if (menuItem.checked ?? false) {
        await _config.closeProxy();
      } else {
        await _config.openProxy();
      }
    } else if (menuItem.key == 'exit_app') {
      await _config.closeProxy();
      windowManager.close().then((_) => windowManager.destroy());
    } else if (menuItem.key == Mode.Rule.value) {
      _core.setState(mode: Mode.Rule);
    } else if (menuItem.key == Mode.Global.value) {
      _core.setState(mode: Mode.Global);
    } else if (menuItem.key == Mode.Direct.value) {
      _core.setState(mode: Mode.Direct);
    }
  }
}

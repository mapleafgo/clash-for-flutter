import 'dart:io';

import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:mobx/mobx.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

/// 托盘菜单控制类
class TrayController {
  final SystemTray _tray = SystemTray();
  final _config = Modular.get<GlobalConfig>();

  init() {
    // 监听系统代理
    reaction(
      (_) => _config.systemProxy,
      (status) => _menuReset(isChecked: status, mode: _config.clashConfig.mode!),
    );
    // 监听代理模式
    reaction(
      (_) => _config.clashConfig.mode,
      (mode) => _menuReset(isChecked: _config.systemProxy, mode: mode!),
    );
    _tray.initSystemTray(
      iconPath: Platform.isWindows ? 'assets/icon.ico' : 'assets/logo_64.png',
      toolTip: "Clash For Flutter",
    );
    _tray.registerSystemTrayEventHandler((e) {
      if (e == kSystemTrayEventClick) {
        windowManager.show();
      } else if (e == kSystemTrayEventRightClick) {
        _tray.popUpContextMenu();
      }
    });
    // 初始化托盘菜单
    _menuReset(isChecked: _config.systemProxy, mode: _config.clashConfig.mode ?? Mode.Rule);
  }

  void _menuReset({required bool isChecked, required Mode mode}) async {
    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(label: "显示窗口", onClicked: (_) => windowManager.show()),
      MenuSeparator(),
      MenuItemCheckbox(
        label: "代理",
        checked: isChecked,
        onClicked: (b) async {
          if (b.checked) {
            await _config.closeProxy();
          } else {
            await _config.openProxy();
          }
        },
      ),
      SubMenu(label: "模式", children: [
        MenuItemCheckbox(
          checked: mode == Mode.Rule,
          label: Mode.Rule.value,
          onClicked: (_) => _config.setState(mode: Mode.Rule),
        ),
        MenuItemCheckbox(
          checked: mode == Mode.Global,
          label: Mode.Global.value,
          onClicked: (_) => _config.setState(mode: Mode.Global),
        ),
        MenuItemCheckbox(
          checked: mode == Mode.Direct,
          label: Mode.Direct.value,
          onClicked: (_) => _config.setState(mode: Mode.Direct),
        ),
      ]),
      MenuItemLabel(
        label: "退出",
        onClicked: (_) async {
          await _config.closeProxy();
          windowManager.close().then((_) => windowManager.destroy());
        },
      ),
    ]);
    await _tray.setContextMenu(menu);
  }
}

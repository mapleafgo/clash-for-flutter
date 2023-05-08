import 'dart:io';

import 'package:asuka/asuka.dart';
import 'package:clash_for_flutter/app/bean/profile_url_bean.dart';
import 'package:clash_for_flutter/app/component/drawer_component.dart';
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/pages/index/index_module.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:mobx/mobx.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

class IndexPage extends StatefulWidget {
  const IndexPage({super.key});

  @override
  State<IndexPage> createState() => _IndexPageState();
}

class _IndexPageState extends State<IndexPage> with WindowListener, ProtocolListener, WidgetsBindingObserver {
  final _config = Modular.get<GlobalConfig>();
  final _request = Modular.get<Request>();
  final PageController _page = PageController();
  final SystemTray systemTray = SystemTray();

  @override
  void initState() {
    reaction(
      (_) => _config.systemProxy,
      (status) => trayMenuChange(isChecked: status, mode: _config.clashConfig.mode!),
    );
    reaction(
      (_) => _config.clashConfig.mode,
      (mode) => trayMenuChange(isChecked: _config.systemProxy, mode: mode!),
    );
    windowManager.addListener(this);
    protocolHandler.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    _init();
    super.initState();
    Modular.to.navigate("/tab/home/");
  }

  Future<void> _init() async {
    await windowManager.setPreventClose(true);
    systemTray.initSystemTray(
      iconPath: Platform.isWindows ? 'assets/icon.ico' : 'assets/logo_64.png',
      toolTip: "ClashForFlutter",
    );
    trayMenuChange(isChecked: _config.systemProxy, mode: _config.clashConfig.mode ?? Mode.Rule);
    systemTray.registerSystemTrayEventHandler((e) {
      if (e == kSystemTrayEventClick) {
        windowManager.show();
      } else if (e == kSystemTrayEventRightClick) {
        systemTray.popUpContextMenu();
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    protocolHandler.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void trayMenuChange({required bool isChecked, required Mode mode}) async {
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
    await systemTray.setContextMenu(menu);
  }

  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      windowManager.hide();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print("状态改变: $state");
  }

  /// 外链接
  @override
  void onProtocolUrlReceived(String url) {
    var uri = Uri.parse(Uri.decodeFull(url));
    // 导入订阅
    if (uri.host == "install-config") {
      var params = uri.queryParameters;
      var subscribeUrl = params["url"];
      if (subscribeUrl != null) {
        var profile = ProfileURL.emptyBean()
          ..url = subscribeUrl
          ..name = params["name"] ?? "";

        var loading = Loading.builder();
        Asuka.addOverlay(loading);
        _request.getSubscribe(profile: profile, profilesDir: _config.profilesPath).then((p) {
          var tempList = _config.profiles.toList();
          tempList.add(p);
          _config.setState(profiles: tempList);
          Asuka.showSnackBar(const SnackBar(content: Text("导入成功")));
        }).catchError((e) {
          Asuka.showSnackBar(SnackBar(content: Text("导入异常: $e")));
        }).then((_) {
          loading.remove();
          _page.jumpToPage(2);
        });
      } else {
        Asuka.showSnackBar(const SnackBar(content: Text("导入订阅链接有误")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      AppDrawer(page: _page),
      Expanded(
        child: PageView.builder(
          controller: _page,
          itemCount: menu.size,
          onPageChanged: (i) => Modular.to.navigate("/tab${menu.getPath(i)}/"),
          itemBuilder: (_, __) => const RouterOutlet(),
        ),
      )
    ]);
  }
}

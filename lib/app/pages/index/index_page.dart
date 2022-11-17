import 'dart:io';
import 'dart:math';

import 'package:asuka/asuka.dart';
import 'package:clash_for_flutter/app/bean/profile_url_bean.dart';
import 'package:clash_for_flutter/app/component/drawer_component.dart';
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:clash_for_flutter/app/utils/constants.dart';
import 'package:flutter/material.dart' hide MenuItem;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:mobx/mobx.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class IndexPage extends StatefulWidget {
  const IndexPage({super.key});

  @override
  State<IndexPage> createState() => _IndexPageState();
}

class _IndexPageState extends State<IndexPage>
    with
        TrayListener,
        WindowListener,
        ProtocolListener,
        WidgetsBindingObserver {
  final _config = Modular.get<GlobalConfig>();
  final _request = Modular.get<Request>();
  final PageController _page = PageController();
  late final ReactionDisposer _disposeSystemProxy;

  @override
  void initState() {
    _disposeSystemProxy = reaction(
      (_) => _config.systemProxy,
      (status) => trayMenuChange(status),
    );
    trayManager.addListener(this);
    windowManager.addListener(this);
    protocolHandler.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    _init();
    super.initState();
    Modular.to.navigate("/tab/home/");
  }

  Future<void> _init() async {
    await windowManager.setPreventClose(true);
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/icon.ico' : 'assets/logo_64.png',
    );
    trayMenuChange(_config.systemProxy);
    await trayManager.setTitle("ClashForFlutter");
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    protocolHandler.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _disposeSystemProxy();
    super.dispose();
  }

  void trayMenuChange(bool isChecked) async {
    List<MenuItem> items = [
      MenuItem(
        key: Constants.systrayWinKey,
        label: '显示窗口',
      ),
      MenuItem.separator(),
      MenuItem.checkbox(
        key: Constants.systrayProxyKey,
        label: '代理',
        checked: isChecked,
      ),
      MenuItem(
        key: Constants.systrayExitKey,
        label: '退出',
      ),
    ];
    await trayManager.setContextMenu(Menu(items: items));
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
    switch (menuItem.key) {
      case Constants.systrayWinKey:
        windowManager.show();
        break;
      case Constants.systrayProxyKey:
        if (menuItem.checked!) {
          await _config.closeProxy();
        } else {
          await _config.openProxy();
        }
        break;
      case Constants.systrayExitKey:
        await _config.closeProxy();
        windowManager.close().then((_) => windowManager.destroy());
        break;
    }
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
        var profileURL = ProfileURL.emptyBean()
          ..url = subscribeUrl
          ..name = params["name"] ?? Random().nextInt(11000).toString();

        var loading = Loading.builder();
        Asuka.addOverlay(loading);
        _request
            .getSubscribe(
          profile: profileURL,
          profilesDir: _config.profilesPath,
        )
            .then((p) {
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
          itemCount: 4,
          onPageChanged: (i) {
            switch (i) {
              case 0:
                Modular.to.navigate("/tab/home/");
                break;
              case 1:
                Modular.to.navigate("/tab/proxys/");
                break;
              case 2:
                Modular.to.navigate("/tab/profiles/");
                break;
              case 3:
                Modular.to.navigate("/tab/settings/");
                break;
            }
          },
          itemBuilder: (_, __) => const RouterOutlet(),
        ),
      )
    ]);
  }
}

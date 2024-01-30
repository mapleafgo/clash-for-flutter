import 'package:asuka/asuka.dart';
import 'package:clash_for_flutter/app/bean/profile_url_bean.dart';
import 'package:clash_for_flutter/app/component/drawer_component.dart';
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/pages/index/tray_controller.dart';
import 'package:clash_for_flutter/app/pages/router.dart';
import 'package:clash_for_flutter/app/source/app_config.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:desktop_lifecycle/desktop_lifecycle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:window_manager/window_manager.dart';

class IndexDesktopPage extends StatefulWidget {
  const IndexDesktopPage({super.key});

  @override
  State<IndexDesktopPage> createState() => _IndexDesktopPageState();
}

class _IndexDesktopPageState extends State<IndexDesktopPage>
    with WindowListener, ProtocolListener, WidgetsBindingObserver {
  final _config = Modular.get<AppConfig>();
  final _request = Modular.get<Request>();
  final _tray = Modular.get<TrayController>();
  final _lifeEvent = DesktopLifecycle.instance.isActive;

  final PageController _page = PageController();

  @override
  void initState() {
    super.initState();
    // 窗口监听
    windowManager.addListener(this);
    // 协议监听
    protocolHandler.addListener(this);
    // 移动端前后台监听
    WidgetsBinding.instance.addObserver(this);
    // 桌面端前后台监听
    _lifeEvent.addListener(() => appListener(_lifeEvent.value));
    // 接管窗口的关闭按钮
    windowManager.setPreventClose(true);
    // 托盘初始化
    _tray.init();
    Modular.to.navigate("/tab/home/");
  }

  @override
  void dispose() {
    _tray.dispose();
    windowManager.removeListener(this);
    protocolHandler.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      windowManager.hide();
    }
  }

  @override
  void onWindowFocus() {
    setState(() {});
  }

  /// 处理在移动端前后台
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appListener(state == AppLifecycleState.inactive);
  }

  /// 统一处理前后台改变
  void appListener(bool state) {
    if (state) {
      print("应用前台");
    } else {
      print("应用后台");
    }
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

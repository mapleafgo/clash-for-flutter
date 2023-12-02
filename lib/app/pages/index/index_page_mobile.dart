import 'package:asuka/asuka.dart';
import 'package:clash_for_flutter/app/bean/profile_url_bean.dart';
import 'package:clash_for_flutter/app/component/drawer_component.dart';
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/pages/router.dart';
import 'package:clash_for_flutter/app/source/app_config.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:protocol_handler/protocol_handler.dart';

class IndexMobilePage extends StatefulWidget {
  const IndexMobilePage({super.key});

  @override
  State<IndexMobilePage> createState() => _IndexPageState();
}

class _IndexPageState extends State<IndexMobilePage> with ProtocolListener, WidgetsBindingObserver {
  final _config = Modular.get<AppConfig>();
  final _request = Modular.get<Request>();

  final PageController _page = PageController();

  @override
  void initState() {
    super.initState();
    // 协议监听
    protocolHandler.addListener(this);
    // 移动端前后台监听
    WidgetsBinding.instance.addObserver(this);
    Modular.to.navigate("/tab/home/");
  }

  @override
  void dispose() {
    protocolHandler.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

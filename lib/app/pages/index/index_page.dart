import 'package:asuka/asuka.dart' as asuka;
import 'package:clash_for_flutter/app/pages/home/home_module.dart';
import 'package:clash_for_flutter/app/pages/index/index_controller.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_module.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_module.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/plugin/pac-proxy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';

class IndexPage extends StatefulWidget {
  @override
  _IndexPageState createState() => _IndexPageState();
}

class _IndexPageState extends ModularState<IndexPage, IndexController> {
  GlobalConfig _config = Modular.get<GlobalConfig>();

  @override
  void initState() {
    Future.wait([_config.init(), PACProxy.init()])
        .then((_) => controller.status = 1)
        .catchError((err) {
      asuka.showSnackBar(SnackBar(
        content: Text(
          err is PlatformException ? err.message : "发生未知错误",
          style: TextStyle(fontFamily: "NotoSansCJK"),
        ),
      ));
      controller.status = 2;
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<IndexController>(builder: (_, __) {
      switch (controller.status) {
        case 0:
          return Center(child: CircularProgressIndicator());
        case 2:
          return Center(child: Text("初始化失败"));
        default:
          return RouterOutletList(
            controller: controller.router,
            modules: [
              HomeModule(),
              ProxysModule(),
              ProfilesModule(),
            ],
          );
      }
    });
  }
}

import 'package:clash_for_flutter/app/pages/home/home_module.dart';
import 'package:clash_for_flutter/app/pages/index/index_controller.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_module.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_module.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/plugin/pac-proxy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class IndexPage extends StatefulWidget {
  @override
  _IndexPageState createState() => _IndexPageState();
}

class _IndexPageState extends ModularState<IndexPage, IndexController> {
  GlobalConfig _config = Modular.get<GlobalConfig>();

  @override
  void initState() {
    _config.init();
    PACProxy.init();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return RouterOutletList(
      modules: [
        HomeModule(),
        ProxysModule(),
        ProfilesModule(),
      ],
      controller: controller.router,
    );
  }
}

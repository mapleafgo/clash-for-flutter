import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/pages/index/index_page.dart';
import 'package:clash_for_flutter/app/pages/index/init_page.dart';
import 'package:clash_for_flutter/app/pages/index/tray_controller.dart';
import 'package:clash_for_flutter/app/pages/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class IndexModule extends Module {
  @override
  List<Module> get imports => menu.moduleList;

  @override
  void binds(i) {
    i.addSingleton(TrayController.new);
  }

  @override
  void routes(r) {
    r.child("/", child: (_) => const InitPage(), children: [
      ChildRoute(
        "/error",
        child: (_) => const Scaffold(
          appBar: SysAppBar(title: Text("Clash For Flutter")),
          body: Center(child: Text("初始化失败")),
        ),
      ),
    ]);
    r.child("/tab", child: (_) => const IndexPage(), children: menu.routes);
  }
}

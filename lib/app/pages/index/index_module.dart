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
  final List<Bind> binds = [Bind.singleton((_) => TrayController())];

  @override
  final List<ModularRoute> routes = [
    ChildRoute("/", child: (_, __) => const InitPage(), children: [
      ChildRoute(
        "/error",
        child: (_, __) => const Scaffold(
          appBar: SysAppBar(title: Text("Clash For Flutter")),
          body: Center(child: Text("初始化失败")),
        ),
      ),
    ]),
    ChildRoute("/tab", child: (_, __) => const IndexPage(), children: menu.routes),
  ];
}

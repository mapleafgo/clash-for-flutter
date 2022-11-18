import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/pages/home/home_module.dart';
import 'package:clash_for_flutter/app/pages/index/index_page.dart';
import 'package:clash_for_flutter/app/pages/index/init_page.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_module.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_module.dart';
import 'package:clash_for_flutter/app/pages/settings/settings_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class IndexModule extends Module {
  @override
  List<Module> get imports {
    return [
      HomeModule(),
      ProfilesModule(),
      ProxysModule(),
      SettingsModule(),
    ];
  }

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
    ChildRoute("/tab", child: (_, __) => const IndexPage(), children: [
      ModuleRoute("/home", module: HomeModule()),
      ModuleRoute("/profiles", module: ProfilesModule()),
      ModuleRoute("/proxys", module: ProxysModule()),
      ModuleRoute("/settings", module: SettingsModule()),
    ]),
  ];
}

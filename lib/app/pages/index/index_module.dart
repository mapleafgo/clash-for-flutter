import 'package:clash_for_flutter/app/pages/home/home_module.dart';
import 'package:clash_for_flutter/app/pages/index/index_page.dart';
import 'package:clash_for_flutter/app/pages/index/init_page.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_module.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class IndexModule extends Module {
  @override
  List<Module> get imports {
    return [
      HomeModule(),
      ProfilesModule(),
      ProxysModule(),
    ];
  }

  @override
  final List<ModularRoute> routes = [
    ChildRoute("/", child: (_, __) => InitPage(), children: [
      ChildRoute(
        "/loading",
        child: (_, __) => Center(child: CircularProgressIndicator()),
      ),
      ChildRoute(
        "/error",
        child: (_, __) => Center(child: Text("初始化失败")),
      ),
    ]),
    ChildRoute("/tab", child: (_, __) => IndexPage(), children: [
      ModuleRoute("/home", module: HomeModule()),
      ModuleRoute("/profiles", module: ProfilesModule()),
      ModuleRoute("/proxys", module: ProxysModule())
    ]),
  ];
}

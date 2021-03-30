import 'package:clash_for_flutter/app/pages/home/home_module.dart';
import 'package:clash_for_flutter/app/pages/index/index_page.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_module.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class IndexModule extends Module {
  @override
  final List<ModularRoute> routes = [
    ChildRoute("/", child: (_, __) => IndexPage(), children: [
      ChildRoute(
        "/loading",
        child: (_, __) => Center(child: CircularProgressIndicator()),
      ),
      ChildRoute(
        "/error",
        child: (_, __) => Center(child: Text("初始化失败")),
      ),
      ModuleRoute("/home", module: HomeModule()),
      ModuleRoute("/profiles", module: ProfilesModule()),
      ModuleRoute("/proxys", module: ProxysModule())
    ]),
  ];
}

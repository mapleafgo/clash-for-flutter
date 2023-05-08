import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/pages/connections/connections_module.dart';
import 'package:clash_for_flutter/app/pages/home/home_module.dart';
import 'package:clash_for_flutter/app/pages/index/index_page.dart';
import 'package:clash_for_flutter/app/pages/index/init_page.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_module.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_module.dart';
import 'package:clash_for_flutter/app/pages/settings/settings_module.dart';
import 'package:easy_sidemenu/easy_sidemenu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class MenuRouteItem {
  final int priority;
  final String title;
  final Icon icon;
  final String path;
  final Module module;

  const MenuRouteItem({
    required this.priority,
    required this.title,
    required this.icon,
    required this.path,
    required this.module,
  });
}

class MenuRoute {
  final List<MenuRouteItem> menuList;

  const MenuRoute(this.menuList);

  int get size => menuList.length;

  List<Module> get moduleList {
    return menuList.map((e) => e.module).toList();
  }

  List<ModuleRoute> get routes {
    return menuList.map((e) => ModuleRoute(e.path, module: e.module)).toList();
  }

  List<SideMenuItem> get sideMenuList {
    return menuList
        .map((e) => SideMenuItem(priority: e.priority, title: e.title, icon: e.icon, onTap: (i, c) => c.changePage(i)))
        .toList();
  }

  getPath(int index) {
    return menuList[index].path;
  }
}

final MenuRoute menu = MenuRoute([
  MenuRouteItem(
    priority: 0,
    title: "首页",
    icon: const Icon(Icons.home_outlined),
    path: "/home",
    module: HomeModule(),
  ),
  MenuRouteItem(
    priority: 1,
    title: "代理",
    icon: const Icon(Icons.cloud_outlined),
    path: "/proxys",
    module: ProxysModule(),
  ),
  MenuRouteItem(
    priority: 2,
    title: "连接",
    icon: const Icon(Icons.link_rounded),
    path: "/connections",
    module: ConnectionsModule(),
  ),
  MenuRouteItem(
    priority: 3,
    title: "配置",
    icon: const Icon(Icons.code_rounded),
    path: "/profiles",
    module: ProfilesModule(),
  ),
  MenuRouteItem(
    priority: 4,
    title: "设置",
    icon: const Icon(Icons.settings_outlined),
    path: "/settings",
    module: SettingsModule(),
  ),
]);

class IndexModule extends Module {
  @override
  List<Module> get imports => menu.moduleList;

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

import 'package:clash_for_flutter/app/pages/connections/connections_module.dart';
import 'package:clash_for_flutter/app/pages/home/home_module.dart';
import 'package:clash_for_flutter/app/pages/logs/logs_module.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_module.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_module.dart';
import 'package:clash_for_flutter/app/pages/settings/settings_module.dart';
import 'package:easy_sidemenu/easy_sidemenu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class MenuRouteItem {
  final String title;
  final Icon icon;
  final String path;
  final Module module;

  const MenuRouteItem({
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
    return menuList.map((e) => SideMenuItem(title: e.title, icon: e.icon, onTap: (i, c) => c.changePage(i))).toList();
  }

  getPath(int index) {
    return menuList[index].path;
  }
}

final MenuRoute menu = MenuRoute([
  MenuRouteItem(
    title: "首页",
    icon: const Icon(Icons.home_outlined),
    path: "/home",
    module: HomeModule(),
  ),
  MenuRouteItem(
    title: "代理",
    icon: const Icon(Icons.cloud_outlined),
    path: "/proxys",
    module: ProxysModule(),
  ),
  MenuRouteItem(
    title: "日志",
    icon: const Icon(Icons.list_alt_outlined),
    path: "/logs",
    module: LogsModule(),
  ),
  MenuRouteItem(
    title: "连接",
    icon: const Icon(Icons.link_rounded),
    path: "/connections",
    module: ConnectionsModule(),
  ),
  MenuRouteItem(
    title: "订阅",
    icon: const Icon(Icons.code_rounded),
    path: "/profiles",
    module: ProfilesModule(),
  ),
  MenuRouteItem(
    title: "设置",
    icon: const Icon(Icons.settings_outlined),
    path: "/settings",
    module: SettingsModule(),
  ),
]);

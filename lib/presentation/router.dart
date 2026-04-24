import 'package:clash_for_flutter/presentation/pages/connections_page.dart';
import 'package:clash_for_flutter/presentation/pages/desktop_shell.dart';
import 'package:clash_for_flutter/presentation/pages/home_page.dart';
import 'package:clash_for_flutter/presentation/pages/logs_page.dart';
import 'package:clash_for_flutter/presentation/pages/mobile_shell.dart';
import 'package:clash_for_flutter/presentation/pages/profiles_page.dart';
import 'package:clash_for_flutter/presentation/pages/proxies_page.dart';
import 'package:clash_for_flutter/presentation/pages/settings_page.dart';
import 'package:clash_for_flutter/presentation/pages/init_page.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

Widget _shellBuilder(BuildContext context, GoRouterState state, StatefulNavigationShell shell) =>
    Constants.isDesktop ? DesktopShell(shell: shell) : MobileShell(shell: shell);

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const InitPage(),
    ),
    StatefulShellRoute.indexedStack(
      builder: _shellBuilder,
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (context, state) => const HomePage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/proxies', builder: (context, state) => const ProxiesPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/logs', builder: (context, state) => const LogsPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/connections', builder: (context, state) => const ConnectionsPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/profiles', builder: (context, state) => const ProfilesPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
        ]),
      ],
    ),
  ],
);

class NavItem {
  final String path;
  final String label;
  final IconData icon;
  const NavItem(this.path, this.label, this.icon);
}

const navItems = [
  NavItem('/home', '首页', Icons.home_outlined),
  NavItem('/proxies', '代理', Icons.cloud_outlined),
  NavItem('/logs', '日志', Icons.list_alt_outlined),
  NavItem('/connections', '连接', Icons.link_rounded),
  NavItem('/profiles', '订阅', Icons.code_rounded),
  NavItem('/settings', '设置', Icons.settings_outlined),
];

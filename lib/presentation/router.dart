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

final _shellBuilder = Constants.isDesktop
    ? (_, __, shell) => DesktopShell(shell: shell)
    : (_, __, shell) => MobileShell(shell: shell);

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const InitPage(),
    ),
    StatefulShellRoute.indexedStack(
      builder: _shellBuilder,
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomePage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/proxies', builder: (_, __) => const ProxiesPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/logs', builder: (_, __) => const LogsPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/connections', builder: (_, __) => const ConnectionsPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/profiles', builder: (_, __) => const ProfilesPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
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
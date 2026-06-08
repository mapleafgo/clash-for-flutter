import 'package:singcast/i18n/strings.g.dart';
import 'package:singcast/presentation/pages/about_page.dart';
import 'package:singcast/presentation/pages/desktop_shell.dart';
import 'package:singcast/presentation/pages/home_page.dart';
import 'package:singcast/presentation/pages/mobile_shell.dart';
import 'package:singcast/presentation/pages/profiles_page.dart';
import 'package:singcast/presentation/pages/proxies_page.dart';
import 'package:singcast/presentation/pages/settings_page.dart';
import 'package:singcast/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
class Routes {
  static const home = '/home';
  static const proxies = '/proxies';
  static const profiles = '/profiles';
  static const settings = '/settings';
}

Widget _shellBuilder(
        BuildContext context, GoRouterState state, StatefulNavigationShell shell) =>
    Constants.isDesktop ? DesktopShell(shell: shell) : MobileShell(shell: shell);

final navigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: Routes.home,
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 48),
        const SizedBox(height: 16),
        SelectableText('页面未找到: ${state.error?.message ?? state.uri.path}'), // keep raw for debugging
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => context.go(Routes.home),
          child: Text(t.nav.home),
        ),
      ]),
    ),
  ),
  routes: [
    StatefulShellRoute.indexedStack(
      builder: _shellBuilder,
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
              path: Routes.home,
              builder: (context, state) => const HomePage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: Routes.proxies,
              builder: (context, state) => const ProxiesPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: Routes.profiles,
              builder: (context, state) => const ProfilesPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: Routes.settings,
              builder: (context, state) => const SettingsPage(),
              routes: [
                GoRoute(
                  path: 'about',
                  builder: (context, state) => const AboutPage(),
                ),
              ]),
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

List<NavItem> get navItems => [
  NavItem(Routes.home, t.nav.home, Icons.home_outlined),
  NavItem(Routes.proxies, t.nav.proxies, Icons.cloud_outlined),
  NavItem(Routes.profiles, t.nav.profiles, Icons.code_rounded),
  NavItem(Routes.settings, t.nav.settings, Icons.settings_outlined),
];

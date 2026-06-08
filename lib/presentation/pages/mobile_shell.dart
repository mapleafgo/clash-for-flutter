import 'package:singcast/presentation/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:singcast/services/app_config.dart';

class MobileShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const MobileShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return l10nBuilder((context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final path = GoRouterState.of(context).uri.path;
        if (path != navItems[shell.currentIndex].path) {
          context.pop();
        } else if (shell.currentIndex != 0) {
          context.go(navItems[0].path);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) {
            if (i == shell.currentIndex) {
              shell.goBranch(i, initialLocation: true);
            } else {
              context.go(navItems[i].path);
            }
          },
          destinations: navItems
              .map((e) =>
                  NavigationDestination(icon: Icon(e.icon), label: e.label))
              .toList(),
        ),
      ),
    );
    });
  }
}

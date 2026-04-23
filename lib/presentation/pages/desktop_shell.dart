import 'package:clash_for_flutter/presentation/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DesktopShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const DesktopShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(children: [
        NavigationRail(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => _navigate(context, i),
          labelType: NavigationRailLabelType.all,
          leading: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Clash', style: Theme.of(context).textTheme.titleMedium),
          ),
          destinations: navItems
              .map((e) => NavigationRailDestination(
                    icon: Icon(e.icon),
                    label: Text(e.label),
                  ))
              .toList(),
        ),
        Expanded(child: shell),
      ]),
    );
  }

  void _navigate(BuildContext context, int index) {
    if (shell.currentIndex == index) return;
    context.go(navItems[index].path);
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }
}
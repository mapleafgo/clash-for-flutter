import 'package:clash_for_flutter/presentation/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MobileShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const MobileShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) {
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
        destinations: navItems
            .map((e) => NavigationDestination(icon: Icon(e.icon), label: e.label))
            .toList(),
      ),
    );
  }
}
import 'dart:io';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:singcast/presentation/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

class DesktopShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const DesktopShell({super.key, required this.shell});

  /// macOS 红绿灯按钮区域高度，为 leading 图标留出间距
  static const _macOSTitleBarPadding = 40.0;
  static const _defaultLeadingPadding = 16.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(children: [
        NavigationRail(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => _navigate(context, i),
          labelType: NavigationRailLabelType.all,
          leading: Padding(
            padding: EdgeInsets.only(
              top: Platform.isMacOS
                  ? _macOSTitleBarPadding
                  : _defaultLeadingPadding,
              bottom: _defaultLeadingPadding,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
              child: SvgPicture.asset('assets/logo.svg', width: 48, height: 48),
            ),
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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class SysAppBar extends StatelessWidget implements PreferredSizeWidget {
  final double? toolbarHeight;

  final Widget? title;

  final List<Widget>? actions;

  const SysAppBar({super.key, this.toolbarHeight, this.title, this.actions});

  @override
  Widget build(BuildContext context) {
    List<Widget> acs = [];
    if (actions != null) {
      acs.addAll(actions!);
    }
    if (Platform.isWindows || Platform.isLinux) {
      acs.add(CloseButton(onPressed: () => windowManager.close()));
    }
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: AppBar(
        toolbarHeight: preferredSize.height,
        title: title,
        actions: acs,
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight ?? kToolbarHeight);
}

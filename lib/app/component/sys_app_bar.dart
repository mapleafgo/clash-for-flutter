import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class SysAppBar extends StatelessWidget implements PreferredSizeWidget {
  final double? toolbarHeight;

  final Widget? title;

  final List<Widget>? actions;

  const SysAppBar({Key? key, this.toolbarHeight, this.title, this.actions})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<Widget> acs = [];
    if (actions != null) {
      acs.addAll(actions!);
    }
    acs.add(CloseButton(
      onPressed: () => windowManager.close(),
    ));
    actions?.add(CloseButton(
      onPressed: () => windowManager.close(),
    ));
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

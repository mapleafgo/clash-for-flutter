import 'package:singcast/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class SysAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showClose;
  const SysAppBar({super.key, required this.title, this.showClose = true});

  @override
  Widget build(BuildContext context) {
    if (!Constants.isDesktop) {
      return AppBar(title: Text(title), centerTitle: true);
    }

    return DragToMoveArea(
      child: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        centerTitle: true,
        title: Text(title),
        actions: [
          if (showClose)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '关闭',
              onPressed: () => windowManager.hide(),
            ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

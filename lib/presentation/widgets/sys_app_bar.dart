import 'package:singcast/core/lib_core.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:window_manager/window_manager.dart';

class SysAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showClose;
  const SysAppBar({super.key, required this.title, this.showClose = true});

  @override
  Widget build(BuildContext context) {
    if (!Constants.isDesktop) {
      return AppBar(
        title: Text(title),
        centerTitle: true,
        actions: [const _KernelStateIcon()],
      );
    }

    return DragToMoveArea(
      child: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        centerTitle: true,
        title: Text(title),
        actions: [
          const _KernelStateIcon(),
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

class _KernelStateIcon extends StatelessWidget {
  const _KernelStateIcon();

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final state = LibCore.instance.stateSignal.value;
      return Padding(
        padding: EdgeInsets.only(right: Constants.isDesktop ? 8 : 12),
        child: switch (state) {
          LibCore.kStateCreated || LibCore.kStateStarting => const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          LibCore.kStateInitialized => Icon(Icons.circle, size: 12, color: Colors.grey.shade400),
          LibCore.kStateDestroyed => Icon(Icons.circle, size: 12, color: Colors.red.shade400),
          _ => Icon(Icons.circle, size: 12, color: Colors.green),
        },
      );
    });
  }
}

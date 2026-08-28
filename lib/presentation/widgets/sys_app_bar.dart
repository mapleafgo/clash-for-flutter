import 'dart:io';

import 'package:flutter/material.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/i18n/strings.g.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/utils/constants.dart';
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

    // macOS 红绿灯已提供关闭功能，不显示额外关闭按钮
    final needClose = showClose && !Platform.isMacOS;

    return DragToMoveArea(
      child: AppBar(
        titleSpacing: 0,
        centerTitle: true,
        title: Text(title),
        actions: [
          const _KernelStateIcon(),
          if (needClose)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: t.common.close,
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

  bool _isDisconnected(String state) =>
      state == LibCore.kStateDestroyed || state == LibCore.kStateCreated;

  @override
  Widget build(BuildContext context) {
    return l10nBuilder((context) {
      final state = LibCore.instance.stateSignal.value;
      final disconnected = initError.value != null || _isDisconnected(state);
      final cs = Theme.of(context).colorScheme;

      final icon = switch (state) {
        LibCore.kStateCreated ||
        LibCore.kStateStarting ||
        LibCore.kStateStopping => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        LibCore.kStateInitialized => Icon(
          Icons.circle,
          size: 12,
          color: Colors.grey.shade400,
        ),
        LibCore.kStateDestroyed => Icon(Icons.error, size: 16, color: cs.error),
        _ => Icon(Icons.circle, size: 12, color: Colors.green),
      };

      return Padding(
        padding: EdgeInsets.only(right: Constants.isDesktop ? 8 : 12),
        child: IconButton(
          icon: icon,
          tooltip: disconnected ? t.core.coreDisconnected : t.core.coreState,
          onPressed: () => _confirmReconnect(context),
        ),
      );
    });
  }

  void _confirmReconnect(BuildContext context) {
    final state = LibCore.instance.stateSignal.peek();
    final disconnected = initError.value != null || _isDisconnected(state);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(disconnected ? t.core.reconnectCore : t.core.restartCore),
        content: Text(
          disconnected ? t.core.reconnectMessage : t.core.restartMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.dialogs.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doReconnect(context);
            },
            child: Text(disconnected ? t.core.reconnect : t.core.restart),
          ),
        ],
      ),
    );
  }

  Future<void> _doReconnect(BuildContext context) async {
    try {
      initError.value = null;
      await LibCore.instance.restart();
    } catch (e) {
      if (context.mounted) {
        initError.value = t.core.connectionFailed(error: '$e');
      }
    }
  }
}

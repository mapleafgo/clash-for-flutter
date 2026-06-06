import 'dart:io';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:singcast/core/lib_core.dart';
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

  bool _isDisconnected(String state) =>
      state == LibCore.kStateDestroyed ||
      state == LibCore.kStateCreated;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(builder: (context) {
      final state = LibCore.instance.stateSignal.value;
      final disconnected = initError.value != null || _isDisconnected(state);
      final cs = Theme.of(context).colorScheme;

      final icon = switch (state) {
        LibCore.kStateCreated || LibCore.kStateStarting || LibCore.kStateStopping => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        LibCore.kStateInitialized => Icon(
          Icons.circle,
          size: 12,
          color: Colors.grey.shade400,
        ),
        LibCore.kStateDestroyed => Icon(
          Icons.error,
          size: 16,
          color: cs.error,
        ),
        _ => Icon(Icons.circle, size: 12, color: Colors.green),
      };

      return Padding(
        padding: EdgeInsets.only(right: Constants.isDesktop ? 8 : 12),
        child: IconButton(
          icon: icon,
          tooltip: disconnected ? '内核未连接，点击重新连接' : '内核状态',
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
        title: Text(disconnected ? '重新连接内核' : '重启内核'),
        content: Text(disconnected ? '内核当前未连接，是否尝试重新连接？' : '是否重启内核服务？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doReconnect(context);
            },
            child: Text(disconnected ? '重新连接' : '重启'),
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
        initError.value = '内核连接失败: $e';
      }
    }
  }
}

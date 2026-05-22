import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/core/service_manager.dart';
import 'package:singcast/presentation/widgets/animated_fab.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
import 'package:singcast/utils/constants.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: '关于'),
      body: ListView(children: [
        const _AboutHeader(),
        const _CheckUpdateTile(),
        ListTile(
          title: const Text('官方网站'),
          subtitle: const Text(Constants.homeUrl),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchUrl(Uri.parse(Constants.homeUrl)),
        ),
        ListTile(
          title: const Text('源码仓库'),
          subtitle: const Text(Constants.sourceUrl),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchUrl(Uri.parse(Constants.sourceUrl)),
        ),
        const _KernelVersionTile(),
        if (Platform.isWindows) const _UninstallServiceTile(),
      ]),
    );
  }
}

class _KernelVersionTile extends StatefulWidget {
  const _KernelVersionTile();

  @override
  State<_KernelVersionTile> createState() => _KernelVersionTileState();
}

class _KernelVersionTileState extends State<_KernelVersionTile> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await LibCore.instance.getVersion();
      if (mounted) setState(() => _version = v);
    } catch (_) {
      if (mounted) setState(() => _version = '-');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('内核版本'),
      subtitle: Text(_version.isEmpty ? '加载中...' : _version),
      trailing: const Icon(Icons.open_in_new),
      onTap: () => launchUrl(Uri.parse('https://github.com/mapleafgo/cff-core')),
    );
  }
}

class _CheckUpdateTile extends StatefulWidget {
  const _CheckUpdateTile();

  @override
  State<_CheckUpdateTile> createState() => _CheckUpdateTileState();
}

class _CheckUpdateTileState extends State<_CheckUpdateTile> {
  int _state = 0;
  String _currentVersion = '';
  String _latestVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _currentVersion = info.version);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('版本'),
      subtitle: Text(_currentVersion.isNotEmpty ? _currentVersion : '加载中...'),
      trailing: _trailing(),
      onTap: _state == 1 ? null : _check,
    );
  }

  Widget _trailing() {
    return switch (_state) {
      1 => const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      2 => const Icon(Icons.check_circle_outline, color: Colors.green),
      3 => const Icon(Icons.system_update, color: Colors.blue),
      -1 => const Icon(Icons.error_outline, color: Colors.red),
      _ => const Icon(Icons.refresh),
    };
  }

  Future<void> _check() async {
    setState(() => _state = 1);
    try {
      final resp = await Dio().get<Map<String, dynamic>>(Constants.releaseUrl);
      final tagName = resp.data?['tag_name'] as String? ?? '';
      _latestVersion = tagName.replaceFirst('v', '');

      if (_currentVersion == _latestVersion) {
        if (mounted) setState(() => _state = 2);
      } else {
        if (mounted) setState(() => _state = 3);
        _showUpdateDialog();
      }
    } catch (_) {
      if (mounted) setState(() => _state = -1);
    }
  }

  void _showUpdateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新版本'),
        content: Text('当前版本: $_currentVersion\n最新版本: $_latestVersion'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('忽略'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse('${Constants.sourceUrl}/releases/latest'));
            },
            child: const Text('前往下载'),
          ),
        ],
      ),
    );
  }
}

class _UninstallServiceTile extends StatefulWidget {
  const _UninstallServiceTile();

  @override
  State<_UninstallServiceTile> createState() => _UninstallServiceTileState();
}

class _UninstallServiceTileState extends State<_UninstallServiceTile> {
  bool _loading = false;

  Future<void> _uninstall() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认卸载服务'),
        content: const Text('将停止并删除 Windows 服务 (SingcastService)，下次使用 TUN 模式时需要重新提权安装。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    final svc = ServiceManager.create(Constants.homeDir.path);
    await svc.uninstall();
    if (mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('服务已卸载')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('卸载系统服务'),
      subtitle: const Text('删除 TUN 模式安装的 Windows 服务'),
      trailing: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.delete_outline),
      onTap: _loading ? null : _uninstall,
    );
  }
}

class _AboutHeader extends StatefulWidget {
  const _AboutHeader();

  @override
  State<_AboutHeader> createState() => _AboutHeaderState();
}

class _AboutHeaderState extends State<_AboutHeader>
    with SingleTickerProviderStateMixin {
  int _tapCount = 0;
  Timer? _resetTimer;
  late final _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void dispose() {
    _resetTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  void _onLogoTap() {
    _tapCount++;

    if (_tapCount == 1) {
      _resetTimer = Timer(const Duration(seconds: 6), () {
        _tapCount = 0;
        _resetTimer = null;
      });
    }

    if (_tapCount >= 18) {
      _tapCount = 0;
      _resetTimer?.cancel();
      _resetTimer = null;
      _shakeController.forward(from: 0);
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 150), () {
        HapticFeedback.heavyImpact();
      });
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这都被你发现了！'),
          duration: Duration(seconds: 2),
        ),
      );
    } else if (_tapCount >= 3) {
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: GestureDetector(
        onTap: _onLogoTap,
        child: ShakeBuilder(
          controller: _shakeController,
          child: Column(children: [
            SvgPicture.asset('assets/logo.svg', width: 64, height: 64),
            const SizedBox(height: 8),
            Text(
              'Singcast',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ]),
        ),
      ),
    );
  }
}

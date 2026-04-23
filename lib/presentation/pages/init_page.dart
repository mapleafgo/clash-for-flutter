import 'dart:io';

import 'package:clash_for_flutter/services/app_config.dart';
import 'package:clash_for_flutter/services/clash_api.dart';
import 'package:clash_for_flutter/services/core_config.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

class InitPage extends StatefulWidget {
  const InitPage({super.key});
  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  double _progress = 0;
  String _status = '初始化中...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await api.hello();
      initCoreConfig();
      await syncFromCore();
      initAppConfig();
      await _downloadMmdbIfNeeded();
      await api.changeConfig(
        p.join(Constants.homeDir.path, Constants.profilesPath, selectedFile.value ?? ''),
      );
      if (clashConfig.value.tunEnabled) {
        await openTun();
      }
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('初始化失败: $e')),
        );
      }
    }
  }

  Future<void> _downloadMmdbIfNeeded() async {
    final path = '${Constants.homeDir.path}${Constants.mmdb}';
    if (File(path).existsSync()) return;

    setState(() {
      _status = '正在初始下载 Country.mmdb 文件';
      _progress = 0;
    });

    await api.downloadFile(
      mmdbUrl.value,
      path,
      onProgress: (received, total) {
        if (total > 0 && mounted) {
          setState(() => _progress = received / total);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_status),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        ]),
      ),
    );
  }
}

import 'package:singcast/core/lib_core.dart';
import 'package:singcast/presentation/router.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class InitPage extends StatefulWidget {
  const InitPage({super.key});
  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  String _status = '初始化中...';
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _error = null;
      _status = '初始化中...';
    });

    try {
      // Initialize LibCore (load native library / setup MethodChannel)
      await LibCore.instance.init();

      // Initialize core runtime with home directory
      await LibCore.instance.initCore(Constants.homeDir.path);

      // Initialize configs
      initCoreConfig();
      watchModeFromCore();
      initAppConfig();

      // Activate the selected profile (read YAML -> start core with content)
      final ok = await asyncProfile();
      if (!ok && selectedFile.value != null) {
        if (mounted) {
          setState(() => _error = '配置激活失败，请检查订阅配置是否有效');
        }
        return;
      }

      _onInitComplete();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  void _onInitComplete() {
    startWatchingSelectedFile();
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: 'Singcast', showClose: false),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_status),
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            if (_error != null) ...[
              const SizedBox(height: 16),
              SelectableText(_error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _init, child: const Text('重试')),
            ],
          ]),
        ),
      ),
    );
  }
}

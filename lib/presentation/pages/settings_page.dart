import 'package:singcast/domain/enums.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/utils/constants.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: '设置'),
      body: Watch((context) {
        final config = clashConfig.value;
        return ListView(children: [
          _Section('Clash 代理端口'),
          _PortTile('Mixed Port', config.mixedPort, (v) => updateClashConfig(mixedPort: v)),
          _Section('Clash 设置'),
          SwitchListTile(
            title: const Text('允许局域网'),
            value: config.allowLan ?? false,
            onChanged: (v) => updateClashConfig(allowLan: v),
          ),
          SwitchListTile(
            title: const Text('IPv6'),
            value: config.ipv6 ?? false,
            onChanged: (v) => updateClashConfig(ipv6: v),
          ),
          ListTile(
            title: const Text('代理模式'),
            trailing: DropdownButton<Mode>(
              value: config.mode ?? Mode.rule,
              underline: const SizedBox(),
              items: Mode.values.map((m) => DropdownMenuItem(
                value: m, child: Text(m.name))).toList(),
              onChanged: (m) { if (m != null) updateClashConfig(mode: m); },
            ),
          ),
          ListTile(
            title: const Text('日志等级'),
            trailing: DropdownButton<LogLevel>(
              value: config.logLevel ?? LogLevel.info,
              underline: const SizedBox(),
              items: LogLevel.values.map((l) => DropdownMenuItem(
                value: l, child: Text(l.name))).toList(),
              onChanged: (l) { if (l != null) updateClashConfig(logLevel: l); },
            ),
          ),
          _Section('其他设置'),
          _UaTile(),
          _UrlTile('延迟测试 Url', delayTestUrl.value, (v) => delayTestUrl.value = v),
          _UrlTile('Rule-Set 代理', ruleSetProxy.value, (v) => ruleSetProxy.value = v),
          _Section('关于'),
          ListTile(
            title: const Text('官方网站'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse(Constants.homeUrl)),
          ),
          ListTile(
            title: const Text('源码仓库'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse(Constants.sourceUrl)),
          ),
          _CheckUpdateTile(),
        ]);
      }),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _PortTile extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int> onChanged;
  const _PortTile(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(value?.toString() ?? '未设置'),
      onTap: () async {
        final controller = TextEditingController(text: value?.toString() ?? '');
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(label),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '输入端口号',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('确定'),
              ),
            ],
          ),
        );
        if (result != null) {
          final port = int.tryParse(result);
          if (port != null) onChanged(port);
        }
      },
    );
  }
}

class _UrlTile extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  const _UrlTile(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () async {
        final controller = TextEditingController(text: value);
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(label),
            content: TextFormField(
              controller: controller,
              maxLines: null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              onFieldSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('确定'),
              ),
            ],
          ),
        );
        if (result != null) onChanged(result);
      },
    );
  }
}

class _CheckUpdateTile extends StatefulWidget {
  @override
  State<_CheckUpdateTile> createState() => _CheckUpdateTileState();
}

class _CheckUpdateTileState extends State<_CheckUpdateTile> {
  int _state = 0; // 0=idle, 1=checking, 2=up-to-date, 3=has-update, -1=error
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
      1 => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      2 => const Icon(Icons.check, color: Colors.green),
      3 => const Icon(Icons.system_update, color: Colors.blue),
      -1 => const Icon(Icons.error, color: Colors.red),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('忽略')),
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

class _UaTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final ua = subUA.value;
      return ListTile(
        title: const Text('订阅 User-Agent'),
        subtitle: Text(ua == Defaults.subUA ? '默认' : ua, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => _showUaPicker(context),
      );
    });
  }

  void _showUaPicker(BuildContext context) {
    final controller = TextEditingController(text: subUA.value);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('订阅 User-Agent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: '输入 User-Agent',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.pop(ctx),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('默认', style: TextStyle(fontSize: 12)),
                  onPressed: () => controller.text = Defaults.subUA,
                ),
                ...Defaults.uaPresets.skip(1).map((ua) => ActionChip(
                  label: Text(ua, style: const TextStyle(fontSize: 12)),
                  onPressed: () => controller.text = ua,
                )),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) subUA.value = v;
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

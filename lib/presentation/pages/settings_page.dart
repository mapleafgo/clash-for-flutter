import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/presentation/widgets/sys_app_bar.dart';
import 'package:clash_for_flutter/services/app_config.dart';
import 'package:clash_for_flutter/services/clash_api.dart';
import 'package:clash_for_flutter/services/core_config.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:flutter/material.dart';
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
          _PortTile('Redir Port', config.redirPort, (v) => updateClashConfig(redirPort: v)),
          _PortTile('TProxy Port', config.tproxyPort, (v) => updateClashConfig(tproxyPort: v)),
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
              items: Mode.values.map((m) => DropdownMenuItem(
                value: m, child: Text(m.name))).toList(),
              onChanged: (m) { if (m != null) updateClashConfig(mode: m); },
            ),
          ),
          ListTile(
            title: const Text('日志等级'),
            trailing: DropdownButton<LogLevel>(
              value: config.logLevel ?? LogLevel.info,
              items: LogLevel.values.map((l) => DropdownMenuItem(
                value: l, child: Text(l.name))).toList(),
              onChanged: (l) { if (l != null) updateClashConfig(logLevel: l); },
            ),
          ),
          _Section('其他设置'),
          _UrlTile('MMDB Url', mmdbUrl.value, (v) => mmdbUrl.value = v),
          _UrlTile('延迟测试 Url', delayTestUrl.value, (v) => delayTestUrl.value = v),
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
      trailing: SizedBox(
        width: 100,
        child: TextFormField(
          initialValue: value?.toString() ?? '',
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onFieldSubmitted: (v) {
            final port = int.tryParse(v);
            if (port != null) onChanged(port);
          },
        ),
      ),
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
        final result = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(label),
            content: TextFormField(
              initialValue: value,
              onFieldSubmitted: (v) => Navigator.pop(context, v),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              TextButton(
                onPressed: () => Navigator.pop(context, value),
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
  int _state = 0; // 0=idle, 1=checking, 2=up-to-date, -1=error

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('检查更新'),
      trailing: _trailing(),
      onTap: _state == 1 ? null : _check,
    );
  }

  Widget _trailing() {
    return switch (_state) {
      1 => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      2 => const Icon(Icons.check, color: Colors.green),
      -1 => const Icon(Icons.error, color: Colors.red),
      _ => const Icon(Icons.refresh),
    };
  }

  Future<void> _check() async {
    setState(() => _state = 1);
    try {
      await api.checkLatestVersion();
      if (mounted) setState(() => _state = 2);
    } catch (_) {
      if (mounted) setState(() => _state = -1);
    }
  }
}

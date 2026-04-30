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

const _modeLabels = {
  Mode.rule: '规则',
  Mode.global: '全局',
  Mode.direct: '直连',
};

const _logLevelLabels = {
  LogLevel.debug: '调试',
  LogLevel.info: '信息',
  LogLevel.warning: '警告',
  LogLevel.error: '错误',
};

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: '设置'),
      body: Watch((context) {
        final config = clashConfig.value;
        return ListView(children: [
          const _Section('Clash 代理端口'),
          _PortTile(
            label: 'Mixed Port',
            value: config.mixedPort,
            onChanged: (v) => updateClashConfig(mixedPort: v),
          ),
          const _Section('Clash 设置'),
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
          if (Constants.isDesktop)
            _ChoiceTile<Mode>(
              title: '代理模式',
              value: config.mode ?? Mode.rule,
              items: Mode.values,
              labelBuilder: (m) => _modeLabels[m] ?? m.name,
              onChanged: (m) => changeMode(m),
            ),
          _ChoiceTile<LogLevel>(
            title: '日志等级',
            value: config.logLevel ?? LogLevel.info,
            items: LogLevel.values,
            labelBuilder: (l) => _logLevelLabels[l] ?? l.name,
            onChanged: (l) => updateClashConfig(logLevel: l),
          ),
          const _Section('其他设置'),
          const _UaTile(),
          _UrlTile(
            label: '延迟测试 Url',
            value: delayTestUrl.value,
            onChanged: (v) => delayTestUrl.value = v,
          ),
          _UrlTile(
            label: 'Rule-Set 代理',
            value: ruleSetProxy.value,
            onChanged: (v) => ruleSetProxy.value = v,
          ),
          const _Section('关于'),
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
          const _CheckUpdateTile(),
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _PortTile extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int> onChanged;
  const _PortTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(value?.toString() ?? '未设置'),
      onTap: () async {
        final result = await _showEditDialog(
          context: context,
          title: label,
          initialValue: value?.toString() ?? '',
          keyboardType: TextInputType.number,
          validator: (v) {
            final port = int.tryParse(v ?? '');
            if (port == null || port < 1 || port > 65535) {
              return '请输入 1-65535 之间的端口号';
            }
            return null;
          },
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
  const _UrlTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () async {
        final result = await _showEditDialog(
          context: context,
          title: label,
          initialValue: value,
        );
        if (result != null && result.isNotEmpty) onChanged(result);
      },
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

class _UaTile extends StatelessWidget {
  const _UaTile();

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final ua = subUA.value;
      return ListTile(
        title: const Text('订阅 User-Agent'),
        subtitle: Text(
          ua == Defaults.subUA ? '默认' : ua,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
              onSubmitted: (v) {
                final trimmed = v.trim();
                if (trimmed.isNotEmpty) {
                  subUA.value = trimmed;
                }
                Navigator.pop(ctx);
              },
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
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

class _ChoiceTile<T> extends StatelessWidget {
  final String title;
  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onChanged;
  const _ChoiceTile({
    required this.title,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(labelBuilder(value)),
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(title),
            children: items.map((item) => ListTile(
                  title: Text(labelBuilder(item)),
                  selected: item == value,
                  onTap: () {
                    Navigator.pop(ctx);
                    if (item != value) onChanged(item);
                  },
                )).toList(),
          ),
        );
      },
    );
  }
}

Future<String?> _showEditDialog({
  required BuildContext context,
  required String title,
  required String initialValue,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
}) {
  final controller = TextEditingController(text: initialValue);
  final errorText = signal<String?>(null);

  return showDialog<String>(
    context: context,
    builder: (ctx) => Watch((context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: null,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            errorText: errorText.value,
          ),
          onSubmitted: (v) {
            if (validator != null) {
              final err = validator(v);
              if (err != null) {
                errorText.value = err;
                return;
              }
            }
            Navigator.pop(ctx, v);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text;
              if (validator != null) {
                final err = validator(v);
                if (err != null) {
                  errorText.value = err;
                  return;
                }
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('确定'),
          ),
        ],
      );
    }),
  );
}

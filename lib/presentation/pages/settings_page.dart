import 'package:singcast/core/lib_core.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/utils/constants.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';

const _modeLabels = {
  'rule': '规则',
  'global': '全局',
  'direct': '直连',
};

const _logLevelLabels = {
  LogLevel.debug: '调试',
  LogLevel.info: '信息',
  LogLevel.warning: '警告',
  LogLevel.error: '错误',
};

const _themeModeLabels = {
  ThemeMode.system: '跟随系统',
  ThemeMode.light: '浅色',
  ThemeMode.dark: '深色',
};

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: '设置'),
      body: SignalBuilder(builder: (context) {
        final config = clashConfig.value;
        return ListView(children: [
          const _Section('内核'),
          SwitchListTile(
            title: const Text('代理服务'),
            subtitle: const Text('开启后提供 HTTP/SOCKS5 混合代理端口'),
            value: config.userPortEnabled || config.systemProxyEnabled,
            onChanged: config.systemProxyEnabled
                ? null
                : (v) => updateClashConfig(portEnabled: v),
          ),
          _AnimatedExpand(
            expanded: config.userPortEnabled || config.systemProxyEnabled,
            children: [
              SwitchListTile(
                title: const Text('允许局域网'),
                subtitle: const Text('允许局域网内其他设备通过代理上网'),
                value: config.allowLan ?? false,
                onChanged: (v) => updateClashConfig(allowLan: v),
              ),
            ],
          ),
          _PortTile(
            label: '端口号',
            value: config.mixedPort,
            description: '代理服务监听的本地端口号',
            onChanged: (v) => updateClashConfig(mixedPort: v),
          ),
          SwitchListTile(
            title: const Text('IPv6'),
            subtitle: const Text('代理连接支持 IPv6 网络协议'),
            value: config.ipv6 ?? false,
            onChanged: (v) => updateClashConfig(ipv6: v),
          ),
          if (Constants.isDesktop)
            SignalBuilder(builder: (context) {
              final modes = LibCore.instance.availableModesSignal.value;
              final current = LibCore.instance.modeSignal.value;
              final ready = LibCore.instance.stateSignal.value == LibCore.kStateRunning;
              return _ChoiceTile<String>(
                title: '出站模式',
                description: '控制流量路由策略',
                value: modes.contains(current) ? current : (modes.isNotEmpty ? modes.first : 'rule'),
                items: modes,
                labelBuilder: (m) => _modeLabels[m] ?? m,
                onChanged: ready ? (m) => changeModeStr(m) : null,
              );
            }),
          SwitchListTile(
            title: const Text('Clash API'),
            subtitle: const Text('对外提供代理状态查询和控制接口'),
            value: config.apiEnabled,
            onChanged: (v) => updateClashConfig(externalController: v),
          ),
          _AnimatedExpand(
            expanded: config.apiEnabled,
            children: [
              ListTile(
                title: const Text('API 地址'),
                subtitle: Text(config.apiAddr, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () async {
                  final result = await _showEditDialog(
                    context: context,
                    title: 'API 地址',
                    initialValue: config.apiAddr,
                  );
                  if (result != null && result.isNotEmpty) {
                    updateClashConfig(externalControllerAddr: result);
                  }
                },
              ),
            ],
          ),
          _ChoiceTile<LogLevel>(
            title: '日志等级',
            description: '等级越低记录越详细，调试时可选调试',
            value: config.logLevel ?? LogLevel.info,
            items: LogLevel.values,
            labelBuilder: (l) => _logLevelLabels[l] ?? l.name,
            onChanged: (l) => updateClashConfig(logLevel: l),
          ),
          const _Section('普通'),
          const _UaTile(),
          _UrlTile(
            label: '延迟测试 Url',
            description: '测速时请求的目标地址',
            value: delayTestUrl.value,
            onChanged: (v) => delayTestUrl.value = v,
          ),
          _UrlTile(
            label: 'Rule-Set 代理',
            description: '下载 Rule-Set 规则集时使用的代理地址',
            value: ruleSetProxy.value,
            onChanged: (v) => ruleSetProxy.value = v,
          ),
          SignalBuilder(builder: (context) {
            return SwitchListTile(
              title: const Text('启动检查更新'),
              subtitle: const Text('应用启动时自动检查新版本'),
              value: autoCheckUpdate.value,
              onChanged: (v) => autoCheckUpdate.value = v,
            );
          }),
          const _Section('外观'),
          SignalBuilder(builder: (context) => _ChoiceTile<ThemeMode>(
                title: '主题',
                description: '切换应用外观风格',
                value: themeMode.value ?? ThemeMode.system,
                items: ThemeMode.values,
                labelBuilder: (m) => _themeModeLabels[m] ?? m.name,
                onChanged: (m) => themeMode.value = m,
              )),
          const _Section('其他'),
          ListTile(
            title: const Text('关于'),
            subtitle: const Text('版本信息与相关链接'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/about'),
          ),
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
  final String? description;
  final ValueChanged<int>? onChanged;
  const _PortTile({
    required this.label,
    required this.value,
    this.description,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return ListTile(
      title: Text(label),
      subtitle: Text(value?.toString() ?? '未设置'),
      enabled: enabled,
      onTap: enabled ? () async {
        final result = await _showEditDialog(
          context: context,
          title: label,
          description: description,
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
          if (port != null && onChanged != null) onChanged!(port);
        }
      } : null,
    );
  }
}

class _UrlTile extends StatelessWidget {
  final String label;
  final String? description;
  final String value;
  final ValueChanged<String> onChanged;
  const _UrlTile({
    required this.label,
    this.description,
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
          description: description,
          initialValue: value,
        );
        if (result != null && result.isNotEmpty) onChanged(result);
      },
    );
  }
}

class _UaTile extends StatelessWidget {
  const _UaTile();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(builder: (context) {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text('更新订阅时使用的 User-Agent 标识', style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              ),
            ),
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
  final String? description;
  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T>? onChanged;
  const _ChoiceTile({
    required this.title,
    this.description,
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
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () {
        showDialog(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(title),
            children: [
              if (description != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(description!, style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ),
              ...items.map((item) => Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      title: Text(labelBuilder(item)),
                      selected: item == value,
                      onTap: () {
                        Navigator.pop(ctx);
                        if (item != value) onChanged?.call(item);
                      },
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }
}

Future<String?> _showEditDialog({
  required BuildContext context,
  required String title,
  String? description,
  required String initialValue,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
}) {
  final controller = TextEditingController(text: initialValue);
  final errorText = signal<String?>(null);

  return showDialog<String>(
    context: context,
    builder: (ctx) => SignalBuilder(builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (description != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(description, style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ),
              ),
            TextField(
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
          ],
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

class _AnimatedExpand extends StatelessWidget {
  final bool expanded;
  final List<Widget> children;
  const _AnimatedExpand({required this.expanded, required this.children});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubicEmphasized,
        alignment: Alignment.topCenter,
        child: expanded
            ? Column(children: children)
            : const SizedBox.shrink(),
      ),
    );
  }
}

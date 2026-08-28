import 'package:singcast/domain/enums.dart';
import 'package:singcast/i18n/strings.g.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/services/startup_service.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';

String _logLevelLabel(LogLevel l) => switch (l) {
  LogLevel.debug => t.settings.logDebug,
  LogLevel.info => t.settings.logInfo,
  LogLevel.warning => t.settings.logWarning,
  LogLevel.error => t.settings.logError,
};

String _tunStackLabel(TunStack s) => switch (s) {
  TunStack.gvisor => t.settings.tunStackGvisor,
  TunStack.mixed => t.settings.tunStackMixed,
  TunStack.system => t.settings.tunStackSystem,
};

String _themeModeLabel(ThemeMode m) => switch (m) {
  ThemeMode.system => t.settings.themeSystem,
  ThemeMode.light => t.settings.themeLight,
  ThemeMode.dark => t.settings.themeDark,
};

String _localeLabel(String? v) => switch (v) {
  'zh' => '中文',
  'en' => 'English',
  _ => t.settings.languageSystem,
};

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(title: t.settings.title),
      body: l10nBuilder((context) {
        final config = coreConfig.value;
        return ListView(
          children: [
            _Section(t.settings.sectionCore),
            SwitchListTile(
              title: Text(t.settings.proxyService),
              subtitle: Text(t.settings.proxyServiceDesc),
              value: config.userPortEnabled || config.systemProxyEnabled,
              onChanged: config.systemProxyEnabled
                  ? null
                  : (v) => updateCoreConfig(portEnabled: v),
            ),
            _AnimatedExpand(
              expanded: config.userPortEnabled || config.systemProxyEnabled,
              children: [
                SwitchListTile(
                  title: Text(t.settings.allowLan),
                  subtitle: Text(t.settings.allowLanDesc),
                  value: config.allowLan ?? false,
                  onChanged: (v) => updateCoreConfig(allowLan: v),
                ),
              ],
            ),
            _PortTile(
              label: t.settings.port,
              value: config.mixedPort,
              description: t.settings.portDesc,
              onChanged: (v) => updateCoreConfig(mixedPort: v),
            ),
            SwitchListTile(
              title: Text(t.settings.ipv6),
              subtitle: Text(t.settings.ipv6Desc),
              value: config.ipv6 ?? false,
              onChanged: (v) => updateCoreConfig(ipv6: v),
            ),
            if (Constants.isDesktop)
              l10nBuilder((context) {
                return _ChoiceTile<TunStack>(
                  title: t.settings.tunStack,
                  description: t.settings.tunStackDesc,
                  value: tunStack.value,
                  items: TunStack.values,
                  labelBuilder: _tunStackLabel,
                  onChanged: (s) => tunStack.value = s,
                );
              }),
            SwitchListTile(
              title: Text(t.settings.clashApi),
              subtitle: Text(t.settings.clashApiDesc),
              value: config.apiEnabled,
              onChanged: (v) => updateCoreConfig(externalController: v),
            ),
            _AnimatedExpand(
              expanded: config.apiEnabled,
              children: [
                ListTile(
                  title: Text(t.settings.apiAddress),
                  subtitle: Text(
                    config.apiAddr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () async {
                    final result = await _showEditDialog(
                      context: context,
                      title: t.settings.apiAddress,
                      initialValue: config.apiAddr,
                    );
                    if (result != null && result.isNotEmpty) {
                      updateCoreConfig(externalControllerAddr: result);
                    }
                  },
                ),
              ],
            ),
            _ChoiceTile<LogLevel>(
              title: t.settings.logLevel,
              description: t.settings.logLevelDesc,
              value: config.logLevel ?? LogLevel.info,
              items: LogLevel.values,
              labelBuilder: _logLevelLabel,
              onChanged: (l) => updateCoreConfig(logLevel: l),
            ),
            _Section(t.settings.sectionGeneral),
            if (Constants.isDesktop)
              l10nBuilder((context) {
                return SwitchListTile(
                  title: Text(t.settings.autoStart),
                  subtitle: Text(t.settings.autoStartDesc),
                  value: autoStart.value,
                  onChanged: (v) async {
                    try {
                      await setAutoStart(v);
                      autoStart.value = v;
                    } catch (e) {
                      // 注册失败，signal 不更新，开关回弹
                      LogFileWriter.instance?.log(
                        'setAutoStart($v) failed: $e',
                        level: LogLevel.warning,
                        name: 'settings',
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                );
              }),
            const _UaTile(),
            _UrlTile(
              label: t.settings.delayTestUrl,
              description: t.settings.delayTestUrlDesc,
              value: delayTestUrl.value,
              onChanged: (v) => delayTestUrl.value = v,
            ),
            _UrlTile(
              label: t.settings.ruleSetProxy,
              description: t.settings.ruleSetProxyDesc,
              value: ruleSetProxy.value,
              allowEmpty: true,
              onChanged: (v) => ruleSetProxy.value = v,
            ),
            l10nBuilder((context) {
              return SwitchListTile(
                title: Text(t.settings.autoCheckUpdate),
                subtitle: Text(t.settings.autoCheckUpdateDesc),
                value: autoCheckUpdate.value,
                onChanged: (v) => autoCheckUpdate.value = v,
              );
            }),
            _Section(t.settings.sectionAppearance),
            l10nBuilder(
              (context) => _ChoiceTile<ThemeMode>(
                title: t.settings.theme,
                description: t.settings.themeDesc,
                value: themeMode.value ?? ThemeMode.system,
                items: ThemeMode.values,
                labelBuilder: _themeModeLabel,
                onChanged: (m) => themeMode.value = m,
              ),
            ),
            l10nBuilder((context) {
              final current = appLocale.value;
              return _ChoiceTile<String>(
                title: t.settings.language,
                description: t.settings.languageDesc,
                value: current ?? 'system',
                items: const ['system', 'zh', 'en'],
                labelBuilder: _localeLabel,
                onChanged: (v) {
                  // 先更新 LocaleSettings，再设置 appLocale。
                  // 这样 effects 运行时 t.xxx 已是新语言的值。
                  if (v == 'system') {
                    LocaleSettings.useDeviceLocale();
                  } else {
                    LocaleSettings.setLocaleRaw(v);
                  }
                  appLocale.value = v == 'system' ? null : v;
                },
              );
            }),
            _Section(t.settings.sectionOther),
            ListTile(
              title: Text(t.settings.about),
              subtitle: Text(t.settings.aboutDesc),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/about'),
            ),
          ],
        );
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
      subtitle: Text(value?.toString() ?? t.settings.notSet),
      enabled: enabled,
      onTap: enabled
          ? () async {
              final result = await _showEditDialog(
                context: context,
                title: label,
                description: description,
                initialValue: value?.toString() ?? '',
                keyboardType: TextInputType.number,
                validator: (v) {
                  final port = int.tryParse(v ?? '');
                  if (port == null || port < 1 || port > 65535) {
                    return t.settings.portValidationError;
                  }
                  return null;
                },
              );
              if (result != null) {
                final port = int.tryParse(result);
                if (port != null && onChanged != null) onChanged!(port);
              }
            }
          : null,
    );
  }
}

class _UrlTile extends StatelessWidget {
  final String label;
  final String? description;
  final String value;
  final ValueChanged<String> onChanged;

  /// 是否允许清空为空白，空值语义由调用方定义（如 ruleSetProxy 空 = 直连）。
  final bool allowEmpty;
  const _UrlTile({
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
    this.allowEmpty = false,
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
        if (result != null && (result.isNotEmpty || allowEmpty)) {
          onChanged(result);
        }
      },
    );
  }
}

class _UaTile extends StatelessWidget {
  const _UaTile();

  @override
  Widget build(BuildContext context) {
    return l10nBuilder((context) {
      final ua = subUA.value;
      return ListTile(
        title: Text(t.settings.subUserAgent),
        subtitle: Text(
          ua == Defaults.subUA ? t.settings.defaultValue : ua,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _showUaPicker(context),
      );
    });
  }

  void _showUaPicker(BuildContext context) {
    final controller = TextEditingController(text: subUA.value);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.settings.subUaDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  t.settings.subUaDialogDesc,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            TextField(
              controller: controller,
              maxLines: null,
              decoration: InputDecoration(
                hintText: t.settings.inputUa,
                border: const OutlineInputBorder(),
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
                  label: Text(
                    t.settings.defaultValue,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => controller.text = Defaults.subUA,
                ),
                ...Defaults.uaPresets
                    .skip(1)
                    .map(
                      (ua) => ActionChip(
                        label: Text(ua, style: const TextStyle(fontSize: 12)),
                        onPressed: () => controller.text = ua,
                      ),
                    ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.dialogs.cancel),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) subUA.value = v;
              Navigator.pop(ctx);
            },
            child: Text(t.dialogs.confirm),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
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
      onTap: onChanged == null
          ? null
          : () {
              showDialog(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text(title),
                  children: [
                    if (description != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                        child: Text(
                          description!,
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ...items.map(
                      (item) => Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          title: Text(labelBuilder(item)),
                          selected: item == value,
                          onTap: () {
                            Navigator.pop(ctx);
                            if (item != value) onChanged?.call(item);
                          },
                        ),
                      ),
                    ),
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

  final result = showDialog<String>(
    context: context,
    builder: (ctx) => l10nBuilder((context) {
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
                  child: Text(
                    description,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
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
            child: Text(t.dialogs.cancel),
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
            child: Text(t.dialogs.confirm),
          ),
        ],
      );
    }),
  );
  result.whenComplete(controller.dispose);
  return result;
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
        child: expanded ? Column(children: children) : const SizedBox.shrink(),
      ),
    );
  }
}

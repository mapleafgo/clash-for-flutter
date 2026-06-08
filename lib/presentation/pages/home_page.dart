import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/i18n/strings.g.dart';
import 'package:singcast/presentation/widgets/animated_fab.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/dialog.dart';
import 'package:singcast/utils/format.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _hasInitError = false;
  final List<VoidCallback> _effectDisposers = [];

  @override
  void initState() {
    super.initState();
    _effectDisposers.add(effect(() {
      final err = initError.value;
      if (err != null && !_hasInitError) {
        setState(() => _hasInitError = true);
      }
    }));
    _effectDisposers.add(effect(() {
      final err = profileError.value;
      if (err != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            showErrorDialog(context, err);
            profileError.value = null;
          }
        });
      }
    }));
  }

  @override
  void dispose() {
    for (final disposer in _effectDisposers) {
      disposer();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: 'Singcast'),
      floatingActionButton: const _ToggleFab(),
      body: Column(
        children: [
          if (_hasInitError) const _InitErrorCard(),
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) {
                final cols = constraints.maxWidth > 600 ? 3 : (constraints.maxWidth > 350 ? 2 : 1);
                final cards = <Widget>[
                  const _SpeedCard(),
                  const _TrafficTotalCard(),
                  const _ModeCard(),
                  if (Constants.isDesktop) const _ProxyModeCard(),
                  const _ConnectionsCard(),
                  const _RuntimeCard(),
                ];
                return MasonryGridView.count(
                  crossAxisCount: cols,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  padding: const EdgeInsets.all(16),
                  itemCount: cards.length,
                  itemBuilder: (_, index) => cards[index],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

}

// --- Card Shell ---

const _smallH = 124.0;
const _mediumH = 260.0;

class _CardShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final double height;
  final Widget child;

  const _CardShell({required this.icon, required this.title, required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Stat Badge ---

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _StatBadge({required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// --- Stat Row (narrow layout) ---

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _StatRow({required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Speed Card ---

class _SpeedCard extends StatelessWidget {
  const _SpeedCard();

  @override
  Widget build(BuildContext context) {
    return l10nBuilder((context) {
      final stats = LibCore.instance.statsSignal.value;
      final up = stats?.up ?? 0;
      final down = stats?.down ?? 0;
      return LayoutBuilder(
        builder: (_, constraints) {
          final narrow = constraints.maxWidth < 200;
          return _CardShell(
            icon: Icons.speed,
            title: t.home.speed,
            height: _smallH,
            child: narrow
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StatRow(icon: Icons.arrow_upward, value: '${formatBytes(up)}/s', color: Colors.deepOrange),
                      const SizedBox(height: 6),
                      _StatRow(icon: Icons.arrow_downward, value: '${formatBytes(down)}/s', color: Colors.blue),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _StatBadge(
                          icon: Icons.arrow_upward,
                          value: '${formatBytes(up)}/s',
                          color: Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatBadge(
                          icon: Icons.arrow_downward,
                          value: '${formatBytes(down)}/s',
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
          );
        },
      );
    });
  }
}

// --- Connections Card ---

class _ConnectionsCard extends StatelessWidget {
  const _ConnectionsCard();

  @override
  Widget build(BuildContext context) {
    return l10nBuilder((context) {
      final count = LibCore.instance.activeConnectionsSignal.value;
      final theme = Theme.of(context);
      return _CardShell(
        icon: Icons.link,
        title: t.home.connections,
        height: _smallH,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(t.home.connectionCount, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      );
    });
  }
}

// --- Runtime Card (Memory) ---

class _RuntimeCard extends StatelessWidget {
  const _RuntimeCard();

  @override
  Widget build(BuildContext context) {
    return l10nBuilder((context) {
      final stats = LibCore.instance.statsSignal.value;
      final memory = stats?.memory ?? 0;
      final theme = Theme.of(context);
      return _CardShell(
        icon: Icons.memory,
        title: t.home.memory,
        height: _smallH,
        child: Center(
          child: Text(
            formatBytes(memory),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.purple,
            ),
          ),
        ),
      );
    });
  }
}

// --- Toggle FAB ---

class _ToggleFab extends StatelessWidget {
  const _ToggleFab();

  @override
  Widget build(BuildContext context) {
    return l10nBuilder((context) {
      final isTun = tunIf.value ?? false;
      final on = isTun ? clashConfig.value.tunEnabled : clashConfig.value.systemProxyEnabled;
      final hasProfile = selectedFile.value != null;
      final stats = LibCore.instance.statsSignal.value;
      final cs = Theme.of(context).colorScheme;
      final noProfile = !hasProfile;
      final booting = !LibCore.instance.kernelBooted.value;
      final disabled = noProfile || booting;

      return SafeArea(
        child: AnimatedScale(
          scale: disabled ? 0.95 : (on ? 1.04 : 1.0),
          curve: Curves.elasticOut,
          duration: const Duration(milliseconds: 1200),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: on ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            builder: (context, val, _) {
              final fgColor = disabled
                  ? cs.outline
                  : Color.lerp(cs.onPrimaryContainer, Colors.white, val)!;
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: val > 0.01 && !disabled
                      ? [
                          BoxShadow(
                            color: Colors.green.withValues(alpha: 0.3 * val),
                            blurRadius: 20 * val,
                            spreadRadius: 3 * val,
                          ),
                        ]
                      : [],
                ),
                child: Material(
                  color: disabled
                      ? cs.surfaceContainerHighest
                      : Color.lerp(cs.primaryContainer, Colors.green.shade700, val)!,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: disabled ? null : () => _toggle(context, isTun, on),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.elasticOut,
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconTheme(
                              data: IconThemeData(color: fgColor),
                              child: AnimatedIconSwitcher(value: on),
                            ),
                            const SizedBox(width: 8),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Text(
                                !hasProfile
                                    ? t.home.pleaseAddProfile
                                    : on
                                        ? formatDuration(stats?.startedAt ?? 0)
                                        : t.home.enable,
                                key: ValueKey(!hasProfile
                                    ? 'none'
                                    : on
                                        ? 'on-${stats?.startedAt ?? 0}'
                                        : 'off'),
                                style: TextStyle(color: fgColor, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    });
  }

  Future<void> _toggle(BuildContext context, bool isTun, bool on) async {
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 120));
    HapticFeedback.lightImpact();
    try {
      if (isTun) {
        await toggleTun(!on);
      } else {
        await toggleSystemProxy(!on);
      }
    } catch (e) {
      if (context.mounted) showErrorDialog(context, e.toString());
    }
  }
}

// --- Traffic Total Card ---

class _TrafficTotalCard extends StatelessWidget {
  const _TrafficTotalCard();

  @override
  Widget build(BuildContext context) {
    return l10nBuilder((context) {
      final stats = LibCore.instance.statsSignal.value;
      final upTotal = stats?.upTotal ?? 0;
      final downTotal = stats?.downTotal ?? 0;
      return LayoutBuilder(
        builder: (_, constraints) {
          final narrow = constraints.maxWidth < 200;
          return _CardShell(
            icon: Icons.data_usage,
            title: t.home.trafficTotal,
            height: _smallH,
            child: narrow
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StatRow(icon: Icons.arrow_upward, value: formatBytes(upTotal), color: Colors.deepOrange),
                      const SizedBox(height: 6),
                      _StatRow(icon: Icons.arrow_downward, value: formatBytes(downTotal), color: Colors.blue),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _StatBadge(
                          icon: Icons.arrow_upward,
                          value: formatBytes(upTotal),
                          color: Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatBadge(
                          icon: Icons.arrow_downward,
                          value: formatBytes(downTotal),
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
          );
        },
      );
    });
  }
}

// --- Mode Card ---

String _modeLabel(String m) => switch (m) {
  'rule' => t.mode.rule,
  'global' => t.mode.global,
  'direct' => t.mode.direct,
  _ => m,
};

const _modeIcons = {
  'rule': Icons.rule,
  'global': Icons.public,
  'direct': Icons.phonelink,
};

class _ModeCard extends StatelessWidget {
  const _ModeCard();

  @override
  Widget build(BuildContext context) {
    return l10nBuilder((context) {
      final state = LibCore.instance.stateSignal.value;
      final modes = LibCore.instance.availableModesSignal.value;
      final current = LibCore.instance.modeSignal.value;
      return _CardShell(
        icon: Icons.alt_route,
        title: t.home.outboundMode,
        height: _mediumH,
        child: modes.isEmpty
            ? Center(
                child: Text(t.home.waitingCore,
                    style: TextStyle(color: Theme.of(context).disabledColor, fontSize: 13)),
              )
            : Column(
                children: [
                  for (int i = 0; i < modes.length; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: i == modes.length - 1 ? 0 : 8),
                        child: _ModeOption(
                          icon: _modeIcons[modes[i]] ?? Icons.alt_route,
                          label: _modeLabel(modes[i]),
                          selected: modes[i] == current,
                          onTap: state != LibCore.kStateRunning ? null : () => changeModeStr(modes[i]),
                        ),
                      ),
                    ),
                ],
              ),
      );
    });
  }
}

class _ModeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ModeOption({required this.icon, required this.label, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? cs.primaryContainer.withValues(alpha: 0.5) : Colors.transparent,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: selected ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: selected ? cs.primary : cs.onSurface,
              fontWeight: selected ? FontWeight.w600 : null,
            ),
          ),
          const Spacer(),
          if (selected) Icon(Icons.check_rounded, size: 20, color: cs.primary),
        ],
      ),
    );
  }
}

// --- Proxy Mode Card ---

class _ProxyModeCard extends StatelessWidget {
  const _ProxyModeCard();

  @override
  Widget build(BuildContext context) {
    return l10nBuilder((context) {
      final isTun = tunIf.value ?? false;
      return _CardShell(
        icon: Icons.swap_horiz,
        title: t.home.proxyMode,
        height: _smallH,
        child: Row(
          children: [
            Expanded(
              child: _ProxyModeOption(
                icon: Icons.vpn_lock,
                label: 'TUN',
                selected: isTun,
                onTap: () => tunIf.value = true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ProxyModeOption(
                icon: Icons.computer,
                label: t.home.systemProxy,
                selected: !isTun,
                onTap: () => tunIf.value = false,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _ProxyModeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ProxyModeOption({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? cs.primaryContainer.withValues(alpha: 0.5) : Colors.transparent,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: selected ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: selected ? cs.primary : cs.onSurface,
              fontWeight: selected ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Init Error Card ---

class _InitErrorCard extends StatelessWidget {
  const _InitErrorCard();

  @override
  Widget build(BuildContext context) {
    return l10nBuilder((context) {
      final err = initError.value;
      if (err == null) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      return Material(
        color: cs.errorContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: cs.error),
              const SizedBox(width: 12),
              Expanded(
                child: SelectableText(err, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer)),
              ),
              IconButton(
                icon: Icon(Icons.copy, size: 18, color: cs.onErrorContainer),
                tooltip: t.home.copy,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: err));
                },
              ),
              IconButton(
                icon: Icon(Icons.close, size: 18, color: cs.onErrorContainer),
                onPressed: () {
                  initError.value = null;
                },
              ),
            ],
          ),
        ),
      );
    });
  }
}

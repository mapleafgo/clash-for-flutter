import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/utils/dialog.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/format.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _hasInitError = false;

  @override
  void initState() {
    super.initState();
    effect(() {
      final err = initError.value;
      if (err != null && !_hasInitError) {
        setState(() => _hasInitError = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: 'Singcast'),
      floatingActionButton: const _ToggleFab(),
      body: LayoutBuilder(
        builder: (_, constraints) {
          final cols = constraints.maxWidth > 600
              ? 3
              : (constraints.maxWidth > 350 ? 2 : 1);
          return MasonryGridView.count(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            padding: const EdgeInsets.all(16),
            itemCount: (Constants.isDesktop ? 5 : 4) + (_hasInitError ? 1 : 0),
            itemBuilder: (_, index) {
              if (_hasInitError && index == 0) return const _InitErrorCard();
              final offset = _hasInitError ? 1 : 0;
              return switch (index - offset) {
                0 => const _SpeedCard(),
                1 => const _TrafficTotalCard(),
                2 => const _ConnectionsCard(),
                3 => const _ModeCard(),
                4 when Constants.isDesktop => const _ProxyModeCard(),
                _ => const SizedBox.shrink(),
              };
            },
          );
        },
      ),
    );
  }
}

// --- Card Shell ---

const _smallH = 124.0; // (260 - 12) / 2，确保两个小卡片 + 间距 = 中卡片高度
const _mediumH = 260.0;

class _CardShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final double height;
  final Widget child;

  const _CardShell({
    required this.icon,
    required this.title,
    required this.height,
    required this.child,
  });

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
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
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

  const _StatBadge({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
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

  const _StatRow({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
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
    return Watch((context) {
      final traffic = LibCore.instance.trafficSignal.value;
      final up = traffic?.up ?? 0;
      final down = traffic?.down ?? 0;
      return LayoutBuilder(
        builder: (_, constraints) {
          final narrow = constraints.maxWidth < 200;
          return _CardShell(
            icon: Icons.speed,
            title: '网速',
            height: narrow ? _mediumH : _smallH,
            child: narrow
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StatRow(
                        icon: Icons.arrow_upward,
                        value: '${formatBytes(up)}/s',
                        color: Colors.deepOrange,
                      ),
                      const SizedBox(height: 16),
                      _StatRow(
                        icon: Icons.arrow_downward,
                        value: '${formatBytes(down)}/s',
                        color: Colors.blue,
                      ),
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
    return Watch((context) {
      final count = LibCore.instance.activeConnectionsSignal.value;
      final theme = Theme.of(context);
      return _CardShell(
        icon: Icons.link,
        title: '活动连接',
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
              Text('个连接', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      );
    });
  }
}

// --- Toggle FAB ---

class _ToggleFab extends StatefulWidget {
  const _ToggleFab();

  @override
  State<_ToggleFab> createState() => _ToggleFabState();
}

class _ToggleFabState extends State<_ToggleFab> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final isTun = tunIf.value ?? false;
      final on = isTun ? clashConfig.value.tunEnabled : systemProxy.value;
      final cs = Theme.of(context).colorScheme;
      return FloatingActionButton.extended(
        onPressed: _loading ? null : _toggle,
        backgroundColor: on ? Colors.green.shade700 : cs.primaryContainer,
        foregroundColor: on ? Colors.white : cs.onPrimaryContainer,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
        icon: _loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: on ? Colors.white : cs.onPrimaryContainer,
                ),
              )
            : Icon(on ? Icons.flight_land : Icons.flight_takeoff),
        label: Text(_loading ? '切换中...' : (on ? '关闭' : '开启')),
      );
    });
  }

  Future<void> _toggle() async {
    setState(() => _loading = true);
    try {
      final isTun = tunIf.value ?? false;
      if (isTun) {
        await toggleTun(!clashConfig.value.tunEnabled);
      } else {
        await (systemProxy.value ? closeProxy() : openProxy());
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// --- Traffic Total Card ---

class _TrafficTotalCard extends StatelessWidget {
  const _TrafficTotalCard();

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final traffic = LibCore.instance.trafficSignal.value;
      final upTotal = traffic?.upTotal ?? 0;
      final downTotal = traffic?.downTotal ?? 0;
      return LayoutBuilder(
        builder: (_, constraints) {
          final narrow = constraints.maxWidth < 200;
          return _CardShell(
            icon: Icons.data_usage,
            title: '累计流量',
            height: narrow ? _mediumH : _smallH,
            child: narrow
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StatRow(
                        icon: Icons.arrow_upward,
                        value: formatBytes(upTotal),
                        color: Colors.deepOrange,
                      ),
                      const SizedBox(height: 16),
                      _StatRow(
                        icon: Icons.arrow_downward,
                        value: formatBytes(downTotal),
                        color: Colors.blue,
                      ),
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

const _modeLabels = {Mode.rule: '规则', Mode.global: '全局', Mode.direct: '直连'};

const _modeIcons = {
  Mode.rule: Icons.rule,
  Mode.global: Icons.public,
  Mode.direct: Icons.phonelink,
};

class _ModeCard extends StatelessWidget {
  const _ModeCard();

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final current = clashConfig.value.mode ?? Mode.rule;
      return _CardShell(
        icon: Icons.alt_route,
        title: '出站模式',
        height: _mediumH,
        child: Column(
          children: [
            for (final mode in Mode.values)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: mode == Mode.values.last ? 0 : 8,
                  ),
                  child: _ModeOption(
                    icon: _modeIcons[mode]!,
                    label: _modeLabels[mode]!,
                    selected: mode == current,
                    onTap: () => updateClashConfig(mode: mode),
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
  final VoidCallback onTap;

  const _ModeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 24,
            color: selected ? cs.primary : cs.onSurfaceVariant,
          ),
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
    return Watch((context) {
      final isTun = tunIf.value ?? false;
      return _CardShell(
        icon: Icons.swap_horiz,
        title: '代理模式',
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
                label: '系统代理',
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

  const _ProxyModeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 28,
            color: selected ? cs.primary : cs.onSurfaceVariant,
          ),
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
    return Watch((context) {
      final err = initError.value;
      if (err == null) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      return Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: cs.errorContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: cs.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  err,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onErrorContainer,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 18, color: cs.onErrorContainer),
                onPressed: () => initError.value = null,
              ),
            ],
          ),
        ),
      );
    });
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/utils/dialog.dart';
import 'package:singcast/utils/log_file.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/proxy_group.dart';
import 'package:singcast/presentation/widgets/animated_fab.dart';
import 'package:singcast/presentation/widgets/empty_state.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

final _sortType = signal(SortType.defaults);

const _delayColorGood = Color(0xFF2E7D32);
const _delayColorGoodDark = Color(0xFF66BB6A);
const _delayColorMedium = Color(0xFFF9A825);
const _delayColorMediumDark = Color(0xFFFFEE58);
const _delayColorBad = Color(0xFFC62828);
const _delayColorBadDark = Color(0xFFEF5350);

class ProxiesPage extends StatefulWidget {
  const ProxiesPage({super.key});

  @override
  State<ProxiesPage> createState() => _ProxiesPageState();
}

class _ProxiesPageState extends State<ProxiesPage> with SignalsMixin {
  static final _testingTags = signal<Set<String>>({});
  static final _groupTesting = signal(false);
  final _fabVisible = ValueNotifier<bool>(true);
  TabController? _tabController;
  List<String> _cachedTags = [];

  @override
  void initState() {
    super.initState();
    _syncTags();

    createEffect(() {
      final newTags = LibCore.instance.proxiesSignal.value
          .where((g) => !isUsedProxy(g.tag))
          .map((g) => g.tag)
          .toList();
      if (!listEquals(_cachedTags, newTags)) {
        _cachedTags = newTags;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    });
  }

  void _syncTags() {
    _cachedTags = LibCore.instance.proxiesSignal
        .peek()
        .where((g) => !isUsedProxy(g.tag))
        .map((g) => g.tag)
        .toList();
  }

  @override
  void dispose() {
    _fabVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: '代理'),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _fabVisible,
        builder: (_, visible, _) => AnimatedFab(
          visible: visible,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'sort',
                onPressed: () => _showSort(context),
                tooltip: '排序',
                child: const Icon(Icons.sort),
              ),
              const SizedBox(width: 8),
              Watch((context) {
                final busy = _groupTesting.value;
                final hasNodes = _tabController != null && _cachedTags.isNotEmpty;
                final disabled = busy || !hasNodes;
                final cs = Theme.of(context).colorScheme;
                return FloatingActionButton(
                  heroTag: 'speed',
                  onPressed: disabled ? null : _testAllDelay,
                  tooltip: '测速',
                  backgroundColor: disabled ? cs.surfaceContainerHighest : null,
                  foregroundColor: disabled ? cs.outline : null,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2),
                        )
                      : const Icon(Icons.speed),
                );
              }),
            ],
          ),
        ),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification) {
            final delta = notification.scrollDelta ?? 0;
            if (delta > 5 && _fabVisible.value) {
              _fabVisible.value = false;
            } else if (delta < -5 && !_fabVisible.value) {
              _fabVisible.value = true;
            }
          }
          return false;
        },
        child: _cachedTags.isEmpty
            ? const EmptyState(
                icon: Icons.swap_horiz_rounded,
                title: '暂无代理',
                hint: '添加订阅后，节点将出现在这里',
              )
            : _ProxiesTabView(
                tags: _cachedTags,
                onControllerChanged: (c) => _tabController = c,
                onExpand: () => _showGroupsDialog(context),
              ),
      ),
    );
  }

  Future<void> _testAllDelay() async {
    final tabController = _tabController;
    if (tabController == null) return;

    final index = tabController.index;
    final allGroups = LibCore.instance.proxiesSignal.value;
    final groups = allGroups.where((g) => !isUsedProxy(g.tag)).toList();
    if (index >= groups.length) return;
    final group = groups[index];

    final tags = group.items
        .where((item) => !isUsedProxy(item.tag))
        .map((item) => item.tag)
        .toSet();
    if (tags.isEmpty) return;

    _groupTesting.value = true;
    final cleared =
        Map<String, int>.from(LibCore.instance.proxyDelaysSignal.peek());
    for (final tag in tags) {
      cleared.remove(tag);
    }
    LibCore.instance.proxyDelaysSignal.value = cleared;

    try {
      final delays = await LibCore.instance.testGroupDelay(group.tag);
      if (delays.isNotEmpty) {
        LibCore.instance.updateProxyDelays(delays);
      }
    } catch (_) {
    } finally {
      _groupTesting.value = false;
    }
  }

  void _showSort(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('排序方式'),
        children: SortType.values
            .map((type) => ListTile(
                  title: Text(switch (type) {
                    SortType.defaults => '默认',
                    SortType.name => '按名称',
                    SortType.delay => '按延迟',
                  }),
                  selected: _sortType.value == type,
                  onTap: () {
                    _sortType.value = type;
                    Navigator.pop(ctx);
                  },
                ))
            .toList(),
      ),
    );
  }

  void _showGroupsDialog(BuildContext context) {
    final controller = _tabController;
    if (controller == null) return;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择分组'),
        children: _cachedTags.asMap().entries.map((entry) {
          final index = entry.key;
          final tag = entry.value;
          return ListTile(
            title: Text(tag),
            selected: index == controller.index,
            onTap: () {
              Navigator.pop(ctx);
              controller.animateTo(index);
            },
          );
        }).toList(),
      ),
    );
  }
}

// --- Tab Structure ---

class _ProxiesTabView extends StatefulWidget {
  final List<String> tags;
  final ValueChanged<TabController>? onControllerChanged;
  final VoidCallback? onExpand;
  const _ProxiesTabView({
    required this.tags,
    this.onControllerChanged,
    this.onExpand,
  });

  @override
  State<_ProxiesTabView> createState() => _ProxiesTabViewState();
}

class _ProxiesTabViewState extends State<_ProxiesTabView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.tags.length,
      vsync: this,
    );
    widget.onControllerChanged?.call(_tabController);
  }

  @override
  void didUpdateWidget(_ProxiesTabView old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.tags, widget.tags)) {
      final previousIndex = _tabController.index;
      _tabController.dispose();
      _tabController = TabController(
        length: widget.tags.length,
        vsync: this,
        initialIndex: previousIndex < widget.tags.length ? previousIndex : 0,
      );
      widget.onControllerChanged?.call(_tabController);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(
        children: [
          Expanded(
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.only(left: 12),
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              indicatorSize: TabBarIndicatorSize.label,
              tabs: widget.tags.map((tag) => Tab(text: tag)).toList(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.unfold_more, size: 20),
            tooltip: '展开分组',
            onPressed: widget.onExpand,
          ),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabController,
          children: widget.tags
              .map((tag) => _ProxyList(groupTag: tag))
              .toList(),
        ),
      ),
    ]);
  }
}

// --- Proxy List ---

class _ProxyList extends StatelessWidget {
  final String groupTag;
  const _ProxyList({required this.groupTag});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final group = LibCore.instance.proxiesSignal.value
          .where((g) => g.tag == groupTag)
          .firstOrNull;
      final selected = LibCore.instance.selectedProxySignal.value[groupTag] ?? '';
      final testing = _ProxiesPageState._testingTags.value;
      final items = _sortedItems(group?.items ?? []);

      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) => _ProxyTile(
          item: items[i],
          selected: items[i].tag == selected,
          groupName: groupTag,
          testing: testing.contains(items[i].tag),
        ),
      );
    });
  }

  List<ProxyGroupItem> _sortedItems(List<ProxyGroupItem> items) {
    items = items.where((item) => !isUsedProxy(item.tag)).toList();
    final delays = LibCore.instance.proxyDelaysSignal.peek();
    switch (_sortType.value) {
      case SortType.name:
        items.sort((a, b) => a.tag.compareTo(b.tag));
      case SortType.delay:
        items.sort((a, b) =>
            (delays[a.tag] ?? 99999).compareTo(delays[b.tag] ?? 99999));
      case SortType.defaults:
        break;
    }
    return items;
  }
}

// --- Proxy Tile ---

class _ProxyTile extends StatelessWidget {
  final ProxyGroupItem item;
  final bool selected;
  final bool testing;
  final String groupName;
  const _ProxyTile({
    required this.item,
    required this.selected,
    required this.testing,
    required this.groupName,
  });

  @override
  Widget build(BuildContext context) {
    String? urlTestSelected;
    if (item.type == 'urltest') {
      final group = LibCore.instance.proxiesSignal.value
          .where((g) => g.tag == item.tag)
          .firstOrNull;
      if (group != null && group.selected.isNotEmpty) {
        urlTestSelected = group.selected;
      }
    }

    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: selected ? cs.primaryContainer.withValues(alpha: 0.5) : null,
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text(item.tag,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : null,
                  color: selected ? cs.primary : null,
                )),
            subtitle:
                Text(urlTestSelected ?? item.type, style: const TextStyle(fontSize: 12)),
            trailing: Watch((context) {
              final delay = LibCore.instance.proxyDelaysSignal.value[item.tag] ?? 0;
              return _delayWidget(delay, testing, item.tag);
            }),
            onTap: () async {
              try {
                await LibCore.instance.selectProxy(groupName, item.tag);
              } catch (e) {
                if (context.mounted) {
                  showErrorDialog(context, '切换代理失败: $e');
                }
              }
            },
          ),
        ),
      ),
    );
  }
}

Widget _delayWidget(int delay, bool testing, String tag) {
  if (testing) {
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
  return GestureDetector(
    onTap: () => _testSingleDelay(tag),
    child: Builder(builder: (context) {
      if (delay <= 0) {
        return Text('...',
            style: TextStyle(
                fontSize: 13, color: Theme.of(context).disabledColor));
      }
      return _delayText(delay, context);
    }),
  );
}

Future<void> _testSingleDelay(String tag) async {
  final testing = _ProxiesPageState._testingTags;
  if (!testing.value.contains(tag)) {
    testing.value = Set<String>.from(testing.value)..add(tag);
  }
  try {
    final delay = await LibCore.instance.testDelay(tag);
    if (delay > 0) {
      LibCore.instance.updateProxyDelay(tag, delay);
    }
  } catch (e) {
    LogFileWriter.instance?.log('testDelay($tag) error: $e',
        level: LogLevel.warning, name: 'delay');
  } finally {
    testing.value = Set<String>.from(testing.value)..remove(tag);
  }
}

Widget _delayText(int delay, BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final color = delay <= 500
      ? isDark ? _delayColorGoodDark : _delayColorGood
      : delay <= 1000
          ? isDark ? _delayColorMediumDark : _delayColorMedium
          : isDark ? _delayColorBadDark : _delayColorBad;
  return Text('${delay}ms', style: TextStyle(color: color, fontSize: 13));
}

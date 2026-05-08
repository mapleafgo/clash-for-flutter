import 'dart:async';

import 'package:singcast/core/lib_core.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/proxy_group.dart';
import 'package:singcast/presentation/widgets/animated_fab.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

final _sortType = signal(SortType.defaults);

bool _tagsEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final _testingTags = signal<Set<String>>({});
final _testingTimers = <String, Timer>{};
final _initialDelays = <String, int>{};
String? _testingGroupTag;

class ProxiesPage extends StatefulWidget {
  const ProxiesPage({super.key});

  @override
  State<ProxiesPage> createState() => _ProxiesPageState();
}

class _ProxiesPageState extends State<ProxiesPage> with SignalsMixin {
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
      if (!_tagsEquals(_cachedTags, newTags)) {
        _cachedTags = newTags;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    });

    createEffect(() {
      final testing = _testingTags.peek();
      if (testing.isEmpty) return;
      final groupTag = _testingGroupTag;
      if (groupTag == null) return;

      final group = LibCore.instance.proxiesSignal.value
          .where((g) => g.tag == groupTag)
          .firstOrNull;
      if (group == null) return;

      final completed = <String>[];
      for (final tag in testing) {
        final initial = _initialDelays[tag];
        if (initial == null) {
          completed.add(tag);
          continue;
        }
        final item = group.items.where((i) => i.tag == tag).firstOrNull;
        if (item != null && item.delay > 0 && item.delay != initial) {
          completed.add(tag);
        }
      }

      if (completed.isNotEmpty) {
        for (final tag in completed) {
          _initialDelays.remove(tag);
          _testingTimers[tag]?.cancel();
          _testingTimers.remove(tag);
        }
        final remaining =
            Set<String>.from(_testingTags.value)..removeAll(completed);
        _testingTags.value = remaining;
        if (remaining.isEmpty) _testingGroupTag = null;
      }
    });
  }

  void _syncTags() {
    _cachedTags = LibCore.instance.proxiesSignal.peek()
        .where((g) => !isUsedProxy(g.tag))
        .map((g) => g.tag)
        .toList();
  }

  @override
  void dispose() {
    _fabVisible.dispose();
    for (final timer in _testingTimers.values) {
      timer.cancel();
    }
    _testingTimers.clear();
    _testingTags.value = {};
    _initialDelays.clear();
    _testingGroupTag = null;
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
                if (_testingTags.value.isNotEmpty) {
                  return const SizedBox.shrink();
                }
                return FloatingActionButton(
                  heroTag: 'speed',
                  onPressed: _testAllDelay,
                  tooltip: '测速',
                  child: const Icon(Icons.speed),
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
            ? const Center(child: Text('暂无代理'))
            : _ProxiesTabView(
                tags: _cachedTags,
                onControllerChanged: (c) => _tabController = c,
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

    _testingGroupTag = group.tag;

    final tags = <String>{};
    for (final item in group.items) {
      if (!isUsedProxy(item.tag) && !_testingTags.value.contains(item.tag)) {
        tags.add(item.tag);
        _initialDelays[item.tag] = item.delay;
        LibCore.instance.testDelay(item.tag).catchError((_) {});
      }
    }
    if (tags.isEmpty) return;

    _testingTags.value = Set<String>.from(_testingTags.value)..addAll(tags);

    for (final tag in tags) {
      _testingTimers[tag]?.cancel();
      _testingTimers[tag] = Timer(const Duration(seconds: 5), () {
        _testingTimers.remove(tag);
        _initialDelays.remove(tag);
        final remaining = Set<String>.from(_testingTags.value)..remove(tag);
        _testingTags.value = remaining;
        if (remaining.isEmpty) _testingGroupTag = null;
      });
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
}

// --- Tab Structure ---

class _ProxiesTabView extends StatefulWidget {
  final List<String> tags;
  final ValueChanged<TabController>? onControllerChanged;
  const _ProxiesTabView({required this.tags, this.onControllerChanged});

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
    if (!_tagsEquals(old.tags, widget.tags)) {
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
      TabBar(
        controller: _tabController,
        isScrollable: true,
        tabs: widget.tags.map((tag) => Tab(text: tag)).toList(),
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
      final testing = _testingTags.value;
      final items = _sortedItems(group?.items ?? []);

      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) => _ProxyTile(
          item: items[i],
          selected: items[i].tag == (group?.selected ?? ''),
          groupName: groupTag,
          testing: testing.contains(items[i].tag),
        ),
      );
    });
  }

  List<ProxyGroupItem> _sortedItems(List<ProxyGroupItem> items) {
    items = items.where((item) => !isUsedProxy(item.tag)).toList();
    switch (_sortType.value) {
      case SortType.name:
        items.sort((a, b) => a.tag.compareTo(b.tag));
      case SortType.delay:
        items.sort((a, b) => a.delay.compareTo(b.delay));
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
    return ListTile(
      selected: selected,
      dense: true,
      selectedTileColor: cs.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(item.tag,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : null,
            color: selected ? cs.primary : null,
          )),
      subtitle:
          Text(urlTestSelected ?? item.type, style: const TextStyle(fontSize: 12)),
      trailing: _delayWidget(item.delay, testing, context),
      onTap: () async {
        await LibCore.instance.selectProxy(groupName, item.tag);
      },
    );
  }
}

Widget _delayWidget(int delay, bool testing, BuildContext context) {
  if (testing) {
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
  if (delay <= 0) return const SizedBox.shrink();
  return _delayText(delay, context);
}

Widget _delayText(int delay, BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final color = delay <= 500
      ? isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32)
      : delay <= 1000
          ? isDark ? const Color(0xFFFFEE58) : const Color(0xFFF9A825)
          : isDark ? const Color(0xFFEF5350) : const Color(0xFFC62828);
  return Text('${delay}ms', style: TextStyle(color: color, fontSize: 13));
}

import 'package:singcast/core/lib_core.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/proxy_group.dart';
import 'package:singcast/presentation/widgets/animated_fab.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

final _sortType = signal(SortType.defaults);
final _loading = signal(false);
final _currentTab = signal(0);

class ProxiesPage extends StatefulWidget {
  const ProxiesPage({super.key});

  @override
  State<ProxiesPage> createState() => _ProxiesPageState();
}

class _ProxiesPageState extends State<ProxiesPage> {
  final _fabVisible = ValueNotifier<bool>(true);

  @override
  void dispose() {
    _fabVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(title: '代理'),
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
              Watch((context) => FloatingActionButton(
                    onPressed: _loading.value ? null : _testAllDelay,
                    tooltip: '测速',
                    child: _loading.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.speed),
                  )),
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
        child: Watch((context) {
          final allGroups = LibCore.instance.proxiesSignal.value;
          final groups = allGroups
              .where((g) => !_isUsedProxy(g.tag))
              .toList();

          if (groups.isEmpty) return const Center(child: Text('暂无代理'));
          return DefaultTabController(
            length: groups.length,
            child: Column(children: [
              TabBar(
                isScrollable: true,
                tabs: groups.map((g) => Tab(text: g.tag)).toList(),
                onTap: (i) => _currentTab.value = i,
              ),
              Expanded(
                child: TabBarView(
                  children: groups.map((g) => _ProxyList(
                        group: g,
                      )).toList(),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }

  Future<void> _testAllDelay() async {
    _loading.value = true;
    try {
      final index = _currentTab.value;
      final allGroups = LibCore.instance.proxiesSignal.value;
      final groups = allGroups.where((g) => !_isUsedProxy(g.tag)).toList();
      if (index >= groups.length) return;
      final group = groups[index];
      for (final item in group.items) {
        if (!_isUsedProxy(item.tag)) {
          LibCore.instance.testDelay(item.tag).catchError((_) {});
        }
      }
      await Future.delayed(const Duration(seconds: 5));
    } finally {
      _loading.value = false;
    }
  }

  void _showSort(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('排序方式'),
        children: SortType.values.map((type) => ListTile(
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
            )).toList(),
      ),
    );
  }
}

bool _isUsedProxy(String name) =>
    const {'DIRECT', 'REJECT', 'GLOBAL'}.contains(name);

class _ProxyList extends StatelessWidget {
  final ProxyGroup group;
  const _ProxyList({required this.group});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final items = _sortedItems();
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) => _ProxyTile(
          item: items[i],
          selected: items[i].tag == group.selected,
          groupName: group.tag,
        ),
      );
    });
  }

  List<ProxyGroupItem> _sortedItems() {
    final items = group.items
        .where((item) => !_isUsedProxy(item.tag))
        .toList();

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

class _ProxyTile extends StatelessWidget {
  final ProxyGroupItem item;
  final bool selected;
  final String groupName;
  const _ProxyTile({
    required this.item,
    required this.selected,
    required this.groupName,
  });

  @override
  Widget build(BuildContext context) {
    // 查找 urltest 类型的代理组，显示其选中的节点
    String? urlTestSelected;
    if (item.type == 'urltest') {
      final allGroups = LibCore.instance.proxiesSignal.value;
      final group = allGroups.where((g) => g.tag == item.tag).firstOrNull;
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
      title: Text(item.tag, style: TextStyle(
        fontSize: 14,
        fontWeight: selected ? FontWeight.w600 : null,
        color: selected ? cs.primary : null,
      )),
      subtitle: Text(urlTestSelected ?? item.type, style: const TextStyle(fontSize: 12)),
      trailing: _delayWidget(item.delay),
      onTap: () async {
        await LibCore.instance.selectProxy(groupName, item.tag);
      },
    );
  }
}

Widget _delayWidget(int delay) {
  if (delay == 0) return const Text('...');
  if (delay < 0) return const SizedBox.shrink();
  return Text('${delay}ms');
}

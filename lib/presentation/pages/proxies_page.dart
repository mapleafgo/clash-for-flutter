import 'package:clash_for_flutter/data/api/clash_api.dart';
import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/domain/proxy.dart';
import 'package:clash_for_flutter/domain/proxy_group.dart';
import 'package:clash_for_flutter/presentation/widgets/sys_app_bar.dart';
import 'package:clash_for_flutter/services/app_config.dart';
import 'package:clash_for_flutter/services/core_config.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

final _groups = signal<List<ProxyGroup>>([]);
final _proxies = signal<Map<String, dynamic>>({});
final _sortType = signal(SortType.defaults);
final _loading = signal(false);

class ProxiesPage extends StatefulWidget {
  const ProxiesPage({super.key});
  @override
  State<ProxiesPage> createState() => _ProxiesPageState();
}

class _ProxiesPageState extends State<ProxiesPage> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await api.getProxies();
    final groupList = <ProxyGroup>[];
    final allProxies = <String, dynamic>{};

    data.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        allProxies[key] = value;
        if (isGroupType(value['type'] as String? ?? '') &&
            !isUsedProxy(key)) {
          groupList.add(ProxyGroup.fromJson(value));
        }
      }
    });

    if (clashConfig.value.mode == Mode.global) {
      final? global = allProxies['GLOBAL'];
      if (global is Map<String, dynamic>) {
        groupList.insert(0, ProxyGroup.fromJson(global));
      }
    }

    _groups.value = groupList;
    _proxies.value = allProxies;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(title: '代理'),
      floatingActionButton: Watch((context) {
        if (_loading.value) return const CircularProgressIndicator();
        return FloatingActionButton(
          child: const Icon(Icons.speed),
          onPressed: _loading.value ? null : _testAllDelay,
        );
      }),
      body: Watch((context) {
        final groups = _groups.value;
        if (groups.isEmpty) return const Center(child: Text('暂无代理'));
        return DefaultTabController(
          length: groups.length,
          child: Column(children: [
            TabBar(
              isScrollable: true,
              tabs: groups.map((g) => Tab(text: g.name)).toList(),
            ),
            Expanded(
              child: TabBarView(
                children: groups.map((g) => _ProxyList(
                      group: g,
                      onRefresh: _load,
                    )).toList(),
              ),
            ),
          ]),
        );
      }),
    );
  }

  Future<void> _testAllDelay() async {
    _loading.value = true;
    try {
      final group = _groups.value.isNotEmpty ? _groups.value[0] : null;
      if (group == null) return;
      await Future.wait(group.all.map((name) async {
        try {
          await api.getProxyDelay(name, delayTestUrl.value);
        } catch (_) {}
      }));
      await _load();
    } finally {
      _loading.value = false;
    }
  }
}

class _ProxyList extends StatelessWidget {
  final ProxyGroup group;
  final VoidCallback onRefresh;
  const _ProxyList({required this.group, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final sorted = _sortedItems();
      return ListView.builder(
        itemCount: sorted.length,
        itemBuilder: (_, i) => _ProxyTile(
          item: sorted[i],
          selected: sorted[i].name == group.now,
          onRefresh: onRefresh,
        ),
      );
    });
  }

  List<_ProxyItem> _sortedItems() {
    final items = group.all
        .where((name) => !isUsedProxy(name))
        .map((name) {
      final data = _proxies.value[name];
      final type = data is Map ? data['type'] as String? : null;
      int delay = -1;
      if (data is Map<String, dynamic>) {
        final history = data['history'] as List?;
        if (history != null && history.isNotEmpty) {
          delay = (history.last['delay'] as int?) ?? -1;
        }
      }
      return _ProxyItem(name: name, type: type ?? '', delay: delay);
    }).toList();

    switch (_sortType.value) {
      case SortType.name:
        items.sort((a, b) => a.name.compareTo(b.name));
      case SortType.delay:
        items.sort((a, b) => a.delay.compareTo(b.delay));
      case SortType.defaults:
        break;
    }
    return items;
  }
}

class _ProxyTile extends StatelessWidget {
  final _ProxyItem item;
  final bool selected;
  final VoidCallback onRefresh;
  const _ProxyTile({
    required this.item,
    required this.selected,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      dense: true,
      title: Text(item.name, style: const TextStyle(fontSize: 14)),
      subtitle: Text(item.type, style: const TextStyle(fontSize: 12)),
      trailing: _delayWidget(item.delay),
      onTap: () async {
        final group = _groups.value.firstWhere(
          (g) => g.all.contains(item.name),
        );
        await api.changeProxy(name: group.name, select: item.name);
        onRefresh();
      },
    );
  }
}

Widget _delayWidget(int delay) {
  if (delay < 0) return const SizedBox.shrink();
  if (delay == 0) return const Text('...');
  return Text('${delay}ms');
}

class _ProxyItem {
  final String name;
  final String type;
  final int delay;
  _ProxyItem({required this.name, required this.type, required this.delay});
}

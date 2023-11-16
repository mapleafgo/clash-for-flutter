import 'package:asuka/asuka.dart';
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

enum MenuType { Sort }

/// 代理配置页
class ProxysPage extends StatefulWidget {
  const ProxysPage({super.key});

  @override
  State<ProxysPage> createState() => _ProxysPageState();
}

class _ProxysPageState extends State<ProxysPage> {
  final ScrollController _scrollController = ScrollController();
  final ProxysController _controller = Modular.get<ProxysController>();
  bool _showFab = true;

  @override
  void initState() {
    super.initState();
    _controller.initState();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.userScrollDirection == ScrollDirection.reverse && _showFab) {
      setState(() => _showFab = false);
    }
    if (_scrollController.position.userScrollDirection == ScrollDirection.forward && !_showFab) {
      setState(() => _showFab = true);
    }
  }

  void testDelay(TabController tabController) async {
    var overlay = Loading.builder();
    Asuka.addOverlay(overlay);
    await _controller.delayGroup(
      _controller.model.groups[tabController.index],
    );
    overlay.remove();
  }

  moreMenu(MenuType type) {
    switch (type) {
      // 排序
      case MenuType.Sort:
        sortAction();
        break;
    }
  }

  sortAction() {
    change(sortType, BuildContext context) {
      _controller.sort(sortType);
      Navigator.of(context).pop();
    }

    Asuka.showModalBottomSheet(
      backgroundColor: Colors.transparent,
      builder: (cxt) => Material(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        elevation: 7,
        child: SizedBox(
          height: SortType.values.length * 50,
          child: ListView.builder(
            itemCount: SortType.values.length,
            itemBuilder: (_, i) {
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                onTap: () => change(SortType.values[i], cxt),
                title: Text(SortType.values[i].showName),
                trailing: Radio<SortType>(
                  value: SortType.values[i],
                  groupValue: _controller.model.sortType,
                  onChanged: (v) => change(v, cxt),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (c) {
      var groups = _controller.model.groups;
      return DefaultTabController(
        length: groups.length,
        child: Scaffold(
          appBar: SysAppBar(
            title: groups.isNotEmpty
                ? TabBar(
                    labelColor: Theme.of(context).textTheme.titleLarge?.color,
                    tabs: groups.map((e) => Tab(text: e.name)).toList(),
                    isScrollable: true,
                  )
                : const Text("代理"),
            actions: [
              IconButton(
                tooltip: "排序",
                icon: const Icon(Icons.sort_outlined),
                onPressed: sortAction,
              ),
            ],
          ),
          body: groups.isNotEmpty
              ? TabBarView(
                  children: groups.map((group) {
                    var groupName = group.name;
                    var groupNow = group.now;
                    var list = _controller.getShowList(group);
                    return ListView.separated(
                      controller: _scrollController,
                      itemBuilder: (_, i) {
                        var show = list[i];
                        var name = show.name;
                        var delay = show.delay < 0 ? null : Text(show.delay == 0 ? "..." : show.delay.toString());
                        return ListTile(
                          visualDensity: const VisualDensity(
                            vertical: VisualDensity.minimumDensity,
                          ),
                          selected: groupNow == name,
                          title: Text(
                            name,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            show.subTitle,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: delay,
                          onTap: () => _controller.select(
                            name: groupName,
                            select: name,
                          ),
                        );
                      },
                      separatorBuilder: (_, __) => const Divider(height: 5),
                      itemCount: list.length,
                    );
                  }).toList(),
                )
              : const Center(child: Text("暂无可选代理节点")),
          floatingActionButton: _showFab
              ? Builder(
                  builder: (cxt) {
                    var tabController = DefaultTabController.of(cxt);
                    return FloatingActionButton(
                      tooltip: "测延迟",
                      onPressed: () {
                        if (groups.isNotEmpty) {
                          testDelay(tabController);
                        }
                      },
                      child: const Icon(Icons.flash_on),
                    );
                  },
                )
              : null,
        ),
      );
    });
  }
}

import 'package:asuka/asuka.dart';
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

enum MenuType { Sort }

/// 代理配置页
class ProxysPage extends StatefulWidget {
  const ProxysPage({super.key});

  @override
  ModularState<ProxysPage, ProxysController> createState() => _ProxysPageState();
}

class _ProxysPageState extends ModularState<ProxysPage, ProxysController> {
  @override
  void initState() {
    super.initState();
    controller.initState();
  }

  void testDelay(TabController tabController) async {
    var overlay = Loading.builder();
    Asuka.addOverlay(overlay);
    await controller.delayGroup(
      controller.model.groups[tabController.index],
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
      controller.sortProxies(type: sortType);
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
                  groupValue: controller.model.sortType,
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
      var groups = controller.model.groups;
      var proxiesMap = controller.model.proxiesMap;
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
/*
              PopupMenuButton(
                onSelected: (MenuType type) => moreMenu(type),
                itemBuilder: (_) => <PopupMenuEntry<MenuType>>[
                  PopupMenuItem(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    value: MenuType.Sort,
                    child: SizedBox(
                      width: 100,
                      child: Row(children: [
                        Icon(
                          Icons.sort_outlined,
                          color: DefaultTextStyle.of(context).style.color,
                        ),
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(left: 10),
                            child: const Text("排序"),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
*/
            ],
          ),
          body: groups.isNotEmpty
              ? TabBarView(
                  children: groups.map((group) {
                    var groupName = group.name;
                    var groupNow = group.now;
                    var proxies = proxiesMap[groupName] ?? [];
                    return ListView.separated(
                      separatorBuilder: (_, __) => const Divider(height: 5),
                      itemCount: proxies.length,
                      itemBuilder: (_, i) {
                        var proxie = proxies[i];
                        var proxieName = proxie.name;
                        var delay = proxie.delay < 0
                            ? null
                            : Text(
                                proxie.delay == 0 ? "..." : proxie.delay.toString(),
                              );
                        var subTitle = StringBuffer();
                        if (proxie.type != null) {
                          subTitle.write(proxie.type);
                        }
                        if (proxie.now != null) {
                          subTitle.write(" [${proxie.now}]");
                        }
                        return ListTile(
                          visualDensity: const VisualDensity(
                            vertical: VisualDensity.minimumDensity,
                          ),
                          selected: groupNow == proxieName,
                          title: Text(
                            proxieName,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            subTitle.toString(),
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: () => controller.select(
                            name: groupName,
                            select: proxieName,
                          ),
                          trailing: delay,
                        );
                      },
                    );
                  }).toList(),
                )
              : const Center(child: Text("暂无可选代理节点")),
          floatingActionButton: Builder(
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
          ),
        ),
      );
    });
  }
}

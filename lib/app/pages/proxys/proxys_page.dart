import 'package:asuka/asuka.dart' as asuka;
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_emoji/flutter_emoji.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

enum MenuType { Sort }

/// 代理配置页
class ProxysPage extends StatefulWidget {
  @override
  _ProxysPageState createState() => _ProxysPageState();
}

class _ProxysPageState extends ModularState<ProxysPage, ProxysController> {
  final _emojiParser = EmojiParser();

  @override
  void initState() {
    super.initState();
    controller.initState();
  }

  void testDelay(TabController _tabController) async {
    var overlay = Loading.builder();
    asuka.addOverlay(overlay);
    await controller.delayGroup(
      controller.model.groups[_tabController.index],
    );
    overlay.remove();
  }

  void moreMenu(
    BuildContext context,
    MenuType type,
  ) {
    switch (type) {
      // 排序
      case MenuType.Sort:
        change(sortType) {
          controller.sortProxies(type: sortType);
          Navigator.of(context).pop();
        }
        showMaterialModalBottomSheet(
          context: context,
          builder: (_) => Container(
            height: 150,
            child: ListView.builder(
              itemBuilder: (_, i) {
                return ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: 20),
                  onTap: () => change(SortType.values[i]),
                  title: Text(SortType.values[i].showName),
                  trailing: Radio<SortType>(
                    value: SortType.values[i],
                    groupValue: controller.model.sortType,
                    onChanged: change,
                  ),
                );
              },
              itemCount: SortType.values.length,
            ),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      var groups = controller.model.groups;
      var proxiesMap = controller.model.proxiesMap;
      return DefaultTabController(
        length: groups.length,
        child: Scaffold(
          appBar: AppBar(
            title: groups.isNotEmpty
                ? TabBar(
                    tabs: groups
                        .map((e) => Tab(text: _emojiParser.emojify(e.name)))
                        .toList(),
                    isScrollable: true,
                  )
                : Text("代理"),
            actions: [
              PopupMenuButton(
                onSelected: (MenuType type) => moreMenu(
                  context,
                  type,
                ),
                itemBuilder: (_) => <PopupMenuEntry<MenuType>>[
                  PopupMenuItem(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: 100,
                      child: Row(children: [
                        Icon(
                          Icons.sort,
                          color: DefaultTextStyle.of(context).style.color,
                        ),
                        Expanded(
                          child: Container(
                            child: Text("排序"),
                            margin: EdgeInsets.only(left: 10),
                          ),
                        ),
                      ]),
                    ),
                    value: MenuType.Sort,
                  ),
                ],
              ),
            ],
          ),
          body: groups.length > 0
              ? TabBarView(
                  children: groups.map((group) {
                    var groupName = group.name;
                    var groupNow = group.now;
                    var proxies = proxiesMap[groupName] ?? [];
                    return ListView.separated(
                      separatorBuilder: (_, __) => Divider(height: 5),
                      itemCount: proxies.length,
                      itemBuilder: (_, i) {
                        var proxie = proxies[i];
                        var proxieName = proxie.name;
                        var delay = proxie.delay < 0
                            ? null
                            : Text(
                                proxie.delay == 0
                                    ? "timeout"
                                    : proxie.delay.toString(),
                              );
                        var subTitle = StringBuffer();
                        if (proxie.type != null) {
                          subTitle.write(proxie.type);
                        }
                        if (proxie.now != null) {
                          subTitle.write(" [${proxie.now}]");
                        }
                        return ListTile(
                          visualDensity: VisualDensity(
                            vertical: VisualDensity.minimumDensity,
                          ),
                          selected: groupNow == proxieName,
                          title: Text(
                            _emojiParser.emojify(proxieName),
                            style: TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            _emojiParser.emojify(subTitle.toString()),
                            style: TextStyle(fontSize: 12),
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
              : Center(
                  child: Text("暂无可选代理节点，或暂未开启代理"),
                ),
          floatingActionButton: Builder(
            builder: (cxt) {
              var _tabController = DefaultTabController.of(cxt);
              return FloatingActionButton(
                tooltip: "测延迟",
                onPressed: () {
                  if (groups.length > 0) {
                    testDelay(_tabController!);
                  }
                },
                child: Icon(Icons.flash_on),
              );
            },
          ),
        ),
      );
    });
  }
}

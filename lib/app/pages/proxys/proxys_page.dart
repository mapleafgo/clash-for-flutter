import 'package:asuka/asuka.dart' as asuka;
import 'package:clash_for_flutter/app/bean/group_bean.dart';
import 'package:clash_for_flutter/app/bean/history_bean.dart';
import 'package:clash_for_flutter/app/bean/proxy_bean.dart';
import 'package:clash_for_flutter/app/component/drawer_component.dart';
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:responsive_scaffold/templates/layout/scaffold.dart';

/// 代理配置页
class ProxysPage extends StatefulWidget {
  @override
  _ProxysPageState createState() => _ProxysPageState();
}

class _ProxysPageState extends ModularState<ProxysPage, ProxysController> {
  @override
  void initState() {
    controller.init();
    super.initState();
  }

  void testDelay(TabController _tabController) async {
    var overlay = Loading.builder();
    asuka.addOverlay(overlay);
    await controller.delayGroup(
      controller.model.groups[_tabController.index],
    );
    overlay.remove();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      var groups = controller.model.groups;
      var providers = controller.model.providers;
      return DefaultTabController(
        length: groups.length,
        child: ResponsiveScaffold(
          kDesktopBreakpoint: 860,
          title: groups.length > 1
              ? TabBar(
                  tabs: groups.map((e) => Tab(text: e.name)).toList(),
                  isScrollable: true,
                )
              : Text("代理"),
          drawer: AppDrawer(),
          body: groups.length > 0
              ? TabBarView(
                  children: groups.map((group) {
                    var groupName = group.name;
                    var groupNow = group.now;
                    var proxies = providers[groupName]?.proxies ?? [];
                    return ListView.separated(
                      separatorBuilder: (_, i) => Divider(height: 5),
                      itemCount: proxies.length,
                      itemBuilder: (_, i) {
                        var proxie = proxies[i];
                        var proxieName = proxie.name;
                        var historys = proxie.history as List<History>;
                        var delay = historys.isNotEmpty
                            ? Text(
                                historys.last.delay > 0
                                    ? historys.last.delay.toString()
                                    : "timeout",
                              )
                            : null;
                        var subText = proxie is Proxy
                            ? proxie.type.value
                            : "${(proxie as Group).type.value} [${proxie.now}]";
                        return ListTile(
                          visualDensity: VisualDensity(
                              vertical: VisualDensity.minimumDensity),
                          selected: groupNow == proxieName,
                          title: Text(
                            proxieName,
                            style: TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            subText,
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
            builder: (con) {
              var _tabController = DefaultTabController.of(con);
              return FloatingActionButton(
                tooltip: "测延迟",
                onPressed: () => testDelay(_tabController!),
                child: Icon(Icons.flash_on),
              );
            },
          ),
        ),
      );
    });
  }
}

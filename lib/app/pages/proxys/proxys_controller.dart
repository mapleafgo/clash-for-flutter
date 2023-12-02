import 'dart:async';

import 'package:clash_for_flutter/app/bean/group_bean.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/pages/proxys/model/proxie_show_bean.dart';
import 'package:clash_for_flutter/app/pages/proxys/model/proxys_model.dart';
import 'package:clash_for_flutter/app/source/core_config.dart';
import 'package:clash_for_flutter/app/source/app_config.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:flutter_modular/flutter_modular.dart';

class ProxysController {
  final _request = Modular.get<Request>();
  final _config = Modular.get<AppConfig>();
  final _core = Modular.get<CoreConfig>();
  final model = Modular.get<ProxysModel>();

  Future<void> initState() async {
    await getProxies();
  }

  Future<void> getProxies() async {
    var proxies = await _request.getProxies();
    var global = proxies?.proxies[UsedProxy.GLOBAL.value] as Group;

    var list = global.all
        .where((name) => !UsedProxyValue.valueList.contains(name))
        .map((key) => proxies?.proxies[key])
        .toList();

    List<Group> groupList = [];
    Map<String, dynamic> proxiesMap = {};
    for (var item in list) {
      proxiesMap[item.name] = item;
      if (item is Group && item.type == GroupType.Selector) { // 可选的分组
        groupList.add(item);
      }
    }

    // 全局代理时
    if (_core.clash.mode == Mode.Global) {
      groupList = [global, ...groupList];
    }

    model.setState(groups: groupList, proxiesMap: proxiesMap, global: global);
  }

  Future<void> select({
    required String name,
    required String select,
  }) async {
    await _request.changeProxy(name: name, select: select);
    await getProxies();
  }

  Future<void> delayGroup(Group group) {
    final delayTestUrl = _config.clashForMe.delayTestUrl;
    return Future.wait(
      group.all.map((name) => _request.getProxyDelay(name, delayTestUrl).catchError((_) => 0)),
    ).then((_) => getProxies());
  }

  void sort(SortType type) {
    model.setState(sortType: type);
  }

  List<ProxieShow> getShowList(Group group) {
    var list = group.all.map((e) => _proxieShow(e)).toList();
    switch (model.sortType) {
      case SortType.Delay:
        if (list.any((element) => element.delay > 0)) {
          list.sort((a, b) {
            if (a.delay < 1 || b.delay < 1) {
              return b.delay.compareTo(a.delay);
            }
            return a.delay.compareTo(b.delay);
          });
        }
        break;
      case SortType.Name:
        list.sort((a, b) => a.name.compareTo(b.name));
        break;
      case SortType.Default:
        break;
    }
    return list;
  }

  ProxieShow _proxieShow(String name) {
    var proxie = model.proxiesMap[name];
    if (proxie == null) {
      return ProxieShow(name: name, subTitle: "", delay: -1);
    }
    var historys = proxie.history ?? [];
    if (proxie is Group) {
      var subTitle = StringBuffer();
      subTitle.write(proxie.type.value);
      subTitle.write(" [${proxie.now}]");
      return ProxieShow(
        name: proxie.name,
        subTitle: subTitle.toString(),
        delay: historys.isNotEmpty ? historys.last.delay : -1,
      );
    } else {
      return ProxieShow(
        name: proxie.name,
        subTitle: proxie.type,
        delay: historys.isNotEmpty ? historys.last.delay : -1,
      );
    }
  }
}

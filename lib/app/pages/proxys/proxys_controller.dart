import 'dart:async';

import 'package:clash_for_flutter/app/bean/group_bean.dart';
import 'package:clash_for_flutter/app/bean/provider_bean.dart';
import 'package:clash_for_flutter/app/bean/proxie_show_bean.dart';
import 'package:clash_for_flutter/app/bean/proxy_bean.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/pages/proxys/model/proxys_model.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:flutter_modular/flutter_modular.dart';

class ProxysController {
  final _request = Modular.get<Request>();
  final _config = Modular.get<GlobalConfig>();
  final model = Modular.get<ProxysModel>();

  Future<void> initState() async {
    if (_config.systemProxy) {
      await getProviders();
      await getProxies();
    }
  }

  Future<void> getProxies() async {
    var proxies = await _request.getProxies();
    var global = proxies?.proxies[UsedProxy.GLOBAL.value] as Group?;

    var list = global?.all
        .where((name) => !UsedProxyValue.valueList.contains(name))
        .map((key) => proxies?.proxies[key])
        .toList();

    List<Group> groupList = [];
    Set<Proxy> proxieList = new Set();
    list?.forEach((item) {
      if (item is Group) {
        groupList.add(item);
      } else if (item is Proxy) {
        proxieList.add(item);
      }
    });

    model.setState(
        groups: groupList, proxies: proxieList.toList(), global: global);
  }

  Future<void> getProviders() async {
    var providers = await _request.getProxyProviders();
    model.setState(providers: providers?.providers);
    sortProxies(
      type: model.sortType,
      startMap: _buildProxieShowList(providers: providers?.providers),
    );
  }

  Future<void> select({
    required String name,
    required String select,
  }) async {
    await _request.changeProxy(name: name, select: select);
    _config.proxySelect(name: name, select: select);
    await getProxies();
  }

  Future<void> delayGroup(Group group) {
    return Future.wait(
      group.all.map(
        (name) => _request.getProxyDelay(name).catchError((_) => 0),
      ),
    ).then((value) async => await getProviders());
  }

  Map<String, List<ProxieShow>> _buildProxieShowList({
    Map<String, Provider>? providers,
    String? groupName,
  }) {
    var proxiesMap = <String, List<ProxieShow>>{};
    providers?.forEach((key, value) {
      if (groupName != null && key != groupName) {
        return;
      }
      proxiesMap[key] = value.proxies.map((e) {
        var historys = e.history ?? [];
        return e is Group
            ? ProxieShow(
                name: e.name,
                type: e.type.value,
                delay: historys.isNotEmpty ? historys.last.delay : -1,
                now: e.now,
              )
            : ProxieShow(
                name: e.name,
                type: e.type,
                delay: historys.isNotEmpty ? historys.last.delay : -1,
              );
      }).toList();
    });
    return proxiesMap;
  }

  void sortProxies({
    required SortType type,
    Map<String, List<ProxieShow>>? startMap,
  }) {
    if (type == SortType.Default) {
      model.setState(
        sortType: type,
        proxiesMap: _buildProxieShowList(providers: model.providers),
      );
      return;
    }

    var proxiesMap = <String, List<ProxieShow>>{};
    proxiesMap.addAll(startMap ?? model.proxiesMap);
    var lastMap = proxiesMap.map((key, value) {
      switch (type) {
        case SortType.Delay:
          if (value.any((element) => element.delay > 0)) {
            value.sort((a, b) {
              if (a.delay < 1 || b.delay < 1) {
                return b.delay.compareTo(a.delay);
              }
              return a.delay.compareTo(b.delay);
            });
          }
          break;
        case SortType.Name:
          value.sort((a, b) => a.name.compareTo(b.name));
          break;
        default:
          value = _buildProxieShowList(
                providers: model.providers,
                groupName: key,
              )[key] ??
              [];
      }
      return MapEntry(key, value);
    });
    model.setState(proxiesMap: lastMap, sortType: type);
  }
}

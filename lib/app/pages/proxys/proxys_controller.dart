import 'dart:async';

import 'package:clash_for_flutter/app/pages/index/index_controller.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/bean/group_bean.dart';
import 'package:clash_for_flutter/app/bean/proxy_bean.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/pages/proxys/model/proxys_model.dart';
import 'package:clash_for_flutter/app/source/request.dart';

class ProxysController extends Disposable {
  final _indexCtl = Modular.get<IndexController>();
  final _request = Modular.get<Request>();
  final _config = Modular.get<GlobalConfig>();
  final model = Modular.get<ProxysModel>();

  void _linter(value) {
    if (value == 1) {
      init();
    }
  }

  ProxysController() {
    _indexCtl.addNotifiler(_linter);
  }

  Future<void> init() async {
    await getProviders();
    await getProxies();
  }

  @override
  void dispose() {
    _indexCtl.removeNotifiler(_linter);
  }

  Future<void> getProxies() async {
    var proxies = await _request.getProxies();
    var global = proxies.proxies[UsedProxy.GLOBAL.value] as Group;

    var list = global.all
        .where((name) => !UsedProxyValue.valueList.contains(name))
        .map((key) => proxies.proxies[key])
        .toList();

    List<Group> groupList = [];
    List<Proxy> proxieList = [];
    list.forEach((item) {
      if (item is Group) {
        groupList.add(item);
      } else if (item is Proxy) {
        proxieList.add(item);
      }
    });

    model.setState(groups: groupList, proxies: proxieList, global: global);
  }

  Future<void> getProviders() async {
    var providers = await _request.getProxyProviders();
    model.setState(providers: providers.providers);
  }

  Future<void> select({String name, String select}) async {
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
}

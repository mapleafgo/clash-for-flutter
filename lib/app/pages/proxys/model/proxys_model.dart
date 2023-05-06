import 'package:clash_for_flutter/app/bean/group_bean.dart';
import 'package:clash_for_flutter/app/bean/provider_bean.dart';
import 'package:clash_for_flutter/app/bean/proxy_bean.dart';
import 'package:clash_for_flutter/app/bean/proxie_show_bean.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:mobx/mobx.dart';

part 'proxys_model.g.dart';

class ProxysModel = ProxysModelBase with _$ProxysModel;

/// 代理列表
abstract class ProxysModelBase with Store {
  /// 分组列表
  @observable
  var groups = <Group>[];
  @observable
  Group? global;
  @observable
  SortType sortType = SortType.Default;

  @observable
  List<dynamic> all = [];

  /// 代理列表
  @observable
  var proxies = <Proxy>[];
  @observable
  var providers = <String, Provider>{};
  @observable
  var proxiesMap = <String, List<ProxieShow>>{};

  @action
  setState({
    Group? global,
    SortType? sortType,
    List<dynamic>? all,
    List<Group>? groups,
    List<Proxy>? proxies,
    Map<String, Provider>? providers,
    Map<String, List<ProxieShow>>? proxiesMap,
  }) {
    if (global != null) this.global = global;
    if (sortType != null) this.sortType = sortType;
    if (all != null) this.all = all;
    if (groups != null) this.groups = groups;
    if (proxies != null) this.proxies = proxies;
    if (providers != null) this.providers = providers;
    if (proxiesMap != null) this.proxiesMap = proxiesMap;
  }
}

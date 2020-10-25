import 'package:clash_for_flutter/app/bean/group_bean.dart';
import 'package:clash_for_flutter/app/bean/provider_bean.dart';
import 'package:clash_for_flutter/app/bean/proxy_bean.dart';
import 'package:mobx/mobx.dart';

part 'proxys_model.g.dart';

class ProxysModel = _ProxysModel with _$ProxysModel;

/// 代理列表
abstract class _ProxysModel with Store {
  /// 分组列表
  @observable
  var groups = <Group>[];
  @observable
  Group global;

  /// 代理列表
  @observable
  var proxies = <Proxy>[];
  @observable
  var providers = <String, Provider>{};

  @action
  setState({
    Group global,
    List<Group> groups,
    List<Proxy> proxies,
    Map<String, Provider> providers,
  }) {
    if (global != null) this.global = global;
    if (groups != null) this.groups = groups;
    if (proxies != null) this.proxies = proxies;
    if (providers != null) this.providers = providers;
  }
}

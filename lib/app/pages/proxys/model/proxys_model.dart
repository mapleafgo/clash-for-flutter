import 'package:clash_for_flutter/app/bean/group_bean.dart';
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

  /// 代理列表
  @observable
  Map<String, dynamic> proxiesMap = {};

  @action
  setState({
    Group? global,
    SortType? sortType,
    List<Group>? groups,
    Map<String, dynamic>? proxiesMap,
  }) {
    if (global != null) this.global = global;
    if (sortType != null) this.sortType = sortType;
    if (groups != null) this.groups = groups;
    if (proxiesMap != null) this.proxiesMap = proxiesMap;
  }
}

import 'package:clash_for_flutter/app/enum/type_enum.dart';

import 'group_bean.dart';
import 'proxy_bean.dart';

class Proxies {
  Map<String, dynamic> proxies;

  Proxies({this.proxies});

  static Proxies fromJson(Map<String, dynamic> json) {
    var _proxies = json["proxies"] as Map<String, dynamic>;
    return Proxies(proxies: _proxies.map((key, value) {
      return MapEntry(
          key,
          GroupTypeMap.values.contains(value["type"])
              ? Group.fromJson(value)
              : Proxy.fromJson(value));
    }));
  }

  Map<String, dynamic> toJson() =>
      proxies.map((key, value) => MapEntry(key, value.toJson()));
}

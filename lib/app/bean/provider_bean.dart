import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:json_annotation/json_annotation.dart';

import 'group_bean.dart';
import 'proxy_bean.dart';

part 'provider_bean.g.dart';

@JsonSerializable()
class Provider {
  String name;
  @JsonKey(fromJson: _proxiesFromJson, toJson: _proxiesToJson)
  List<dynamic> proxies;
  String type;
  VehicleType vehicleType;
  String updatedAt;

  Provider({
    this.name,
    this.proxies,
    this.type,
    this.vehicleType,
    this.updatedAt,
  });

  factory Provider.fromJson(Map<String, dynamic> json) =>
      _$ProviderFromJson(json);
  Map<String, dynamic> toJson() => _$ProviderToJson(this);
}

List<dynamic> _proxiesFromJson(List<dynamic> list) {
  return list
      .map((e) => GroupTypeMap.values.contains(e["type"])
          ? Group.fromJson(e)
          : Proxy.fromJson(e))
      .toList();
}

List<dynamic> _proxiesToJson(List<dynamic> list) {
  return list.map((e) => e.toJson()).toList();
}

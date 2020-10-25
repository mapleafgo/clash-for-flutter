import 'package:clash_for_flutter/app/bean/history_bean.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:json_annotation/json_annotation.dart';

part 'proxy_bean.g.dart';

@JsonSerializable()
class Proxy {
  String name;
  ProxieType type;
  List<History> history;

  Proxy({this.name, this.type});

  factory Proxy.fromJson(Map<String, dynamic> json) => _$ProxyFromJson(json);
  Map<String, dynamic> toJson() => _$ProxyToJson(this);
}

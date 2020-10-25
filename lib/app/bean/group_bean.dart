import 'package:clash_for_flutter/app/bean/history_bean.dart';
import 'package:json_annotation/json_annotation.dart';

import '../enum/type_enum.dart';

part 'group_bean.g.dart';

/// 代理项
@JsonSerializable()
class Group {
  String name;
  GroupType type;
  List<String> all;
  String now;
  List<History> history;

  Group({this.name, this.type, this.all, this.now});

  factory Group.fromJson(Map<String, dynamic> json) => _$GroupFromJson(json);
  Map<String, dynamic> toJson() => _$GroupToJson(this);
}

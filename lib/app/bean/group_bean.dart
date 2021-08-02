import 'package:clash_for_flutter/app/bean/history_bean.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import '../enum/type_enum.dart';

/// 分组代理项
@JsonSerializable()
class Group {
  String name;
  GroupType type;
  List<String> all;
  String now;
  List<History>? history;

  Group({
    required this.name,
    required this.type,
    required this.all,
    required this.now,
  });
}

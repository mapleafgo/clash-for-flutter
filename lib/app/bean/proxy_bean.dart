import 'package:dart_json_mapper/dart_json_mapper.dart';

import 'history_bean.dart';

/// 代理项
@JsonSerializable()
class Proxy {
  String name;
  String? type;
  List<History>? history;

  Proxy({required this.name, this.type});
}

import 'package:dart_json_mapper/dart_json_mapper.dart';

import 'history_bean.dart';
import '../enum/type_enum.dart';

@JsonSerializable()
class Proxy {
  String name;
  ProxieType type;
  List<History> history;

  Proxy({this.name, this.type});
}

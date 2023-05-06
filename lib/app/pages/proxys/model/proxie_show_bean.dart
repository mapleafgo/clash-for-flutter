import 'package:dart_json_mapper/dart_json_mapper.dart';

/// 仅用于显示的代理项
@JsonSerializable()
class ProxieShow {
  String name;
  String subTitle;
  int delay;

  ProxieShow({
    required this.name,
    required this.delay,
    required this.subTitle,
  });
}

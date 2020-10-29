import 'package:dart_json_mapper/dart_json_mapper.dart';

/// 配置文件
@JsonSerializable()
class Profile {
  /// 链接地址
  String url;

  /// 保存的文件名
  String file;

  /// 名称
  String name;

  /// 更新间隔(h)
  int interval = 0;

  /// 当前各分组的选择
  Map<String, String> selected = {};

  Profile({this.url, this.file, this.name, this.interval, this.selected});
}

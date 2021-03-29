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

  /// 更新的时间
  DateTime time;

  /// 更新间隔(h)
  int interval;

  /// 当前各分组的选择
  Map<String, String> selected;

  Profile({
    required this.url,
    required this.file,
    required this.name,
    required this.time,
    required this.interval,
    required this.selected,
  });

  factory Profile.defaultBean({
    required String url,
    required String file,
    required String name,
    required DateTime time,
  }) =>
      Profile(
        url: url,
        file: file,
        name: name,
        time: time,
        interval: 0,
        selected: {},
      );

  factory Profile.emptyBean() => Profile(
        url: "",
        file: "",
        name: "",
        time: DateTime.now(),
        interval: 0,
        selected: {},
      );
}

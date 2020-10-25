import 'package:json_annotation/json_annotation.dart';

part 'profile_bean.g.dart';

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
  var selected = <String, String>{};

  Profile({this.url, this.file, this.name, this.interval, this.selected});

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);

  Map<String, dynamic> toJson() => _$ProfileToJson(this);
}

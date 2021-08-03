import 'package:clash_for_flutter/app/bean/profile_file_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_url_bean.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';

/// 配置基本参数
@JsonSerializable()
@Json(discriminatorProperty: 'type')
abstract class ProfileBase {
  /// 保存的文件名
  String file;

  /// 名称
  String name;

  /// 配置类型
  ProfileType type;

  /// 更新的时间
  DateTime time;

  /// 当前各分组的选择
  Map<String, String> selected;

  ProfileBase({
    required this.name,
    required this.file,
    required this.type,
    required this.time,
    required this.selected,
  });

  factory ProfileBase.createProfile(ProfileBase bean) {
    if (bean is ProfileFile) {
      return bean.clone();
    }
    return (bean as ProfileURL).clone();
  }
}

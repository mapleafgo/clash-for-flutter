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

  ProfileBase({
    required this.name,
    required this.file,
    required this.type,
    required this.time,
  });
}

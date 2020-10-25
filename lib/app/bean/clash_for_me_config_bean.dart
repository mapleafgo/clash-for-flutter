import 'package:clash_for_flutter/app/bean/profile_bean.dart';
import 'package:json_annotation/json_annotation.dart';

part 'clash_for_me_config_bean.g.dart';

/// 软件配置
@JsonSerializable()
class ClashForMeConfig {
  /// 选择的配置文件
  @JsonKey(name: "selected-file")
  String selectedFile;

  /// 源配置
  List<Profile> profiles;

  ClashForMeConfig({this.selectedFile, this.profiles});

  factory ClashForMeConfig.defaultConfig() =>
      ClashForMeConfig(selectedFile: "", profiles: []);

  factory ClashForMeConfig.fromJson(Map<String, dynamic> json) =>
      _$ClashForMeConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ClashForMeConfigToJson(this);
}

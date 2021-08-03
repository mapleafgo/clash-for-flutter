import 'package:clash_for_flutter/app/bean/profile_base_bean.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';

/// 软件配置
@JsonSerializable()
class ClashForMeConfig {
  /// 选择的配置文件
  @JsonProperty(name: "selected-file")
  String? selectedFile;

  /// 源配置
  List<ProfileBase> profiles;

  ClashForMeConfig({this.selectedFile, required this.profiles});

  factory ClashForMeConfig.defaultConfig() =>
      ClashForMeConfig(selectedFile: null, profiles: []);
}

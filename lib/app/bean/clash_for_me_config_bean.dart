import 'package:clash_for_flutter/app/bean/profile_bean.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';

/// 软件配置
@JsonSerializable()
class ClashForMeConfig {
  /// 选择的配置文件
  @JsonProperty(name: "selected-file")
  String selectedFile;

  /// 源配置
  List<Profile> profiles;

  ClashForMeConfig({this.selectedFile, this.profiles});

  factory ClashForMeConfig.defaultConfig() =>
      ClashForMeConfig(selectedFile: "", profiles: []);
}

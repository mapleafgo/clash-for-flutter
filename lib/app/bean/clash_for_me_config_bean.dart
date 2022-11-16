import 'dart:convert';
import 'dart:io';

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

  ClashForMeConfig copyWith({
    String? selectedFile,
    List<ProfileBase>? profiles,
  }) {
    var config = ClashForMeConfig(
      selectedFile: selectedFile ?? this.selectedFile,
      profiles: profiles ?? this.profiles,
    );
    if (config.profiles.isEmpty) {
      config.selectedFile = null;
    } else if (config.profiles.length == 1) {
      config.selectedFile = config.profiles.first.file;
    }
    return config;
  }

  Future<void> saveFile(String path) {
    return File(path)
        .create(recursive: true)
        .then((file) => file.writeAsString(JsonMapper.serialize(this)));
  }

  factory ClashForMeConfig.defaultConfig() => ClashForMeConfig(profiles: []);

  factory ClashForMeConfig.formYamlFile(String path) {
    var clashForMeFile = File(path);
    if (clashForMeFile.existsSync()) {
      Map<String, dynamic> cfm = json.decode(clashForMeFile.readAsStringSync());
      return JsonMapper.fromMap<ClashForMeConfig>(cfm)!;
    }
    return ClashForMeConfig.defaultConfig();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:clash_for_flutter/app/bean/profile_base_bean.dart';
import 'package:clash_for_flutter/app/utils/constants.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';

/// 软件配置
@JsonSerializable()
class ClashForMeConfig {
  /// 选择的配置文件
  @JsonProperty(name: "selected-file")
  String? selectedFile;

  /// 源配置
  List<ProfileBase> profiles;

  /// mmdb 下载地址
  @JsonProperty(name: "mmdb-url")
  String mmdbUrl;

  /// 延迟测试地址
  @JsonProperty(name: "delay-test-url")
  String delayTestUrl;

  ClashForMeConfig({
    this.selectedFile,
    required this.profiles,
    required this.mmdbUrl,
    required this.delayTestUrl,
  });

  ClashForMeConfig copyWith({
    String? selectedFile,
    List<ProfileBase>? profiles,
    String? mmdbUrl,
    String? delayTestUrl,
  }) {
    var config = ClashForMeConfig(
      selectedFile: selectedFile ?? this.selectedFile,
      profiles: profiles ?? this.profiles,
      mmdbUrl: mmdbUrl ?? this.mmdbUrl,
      delayTestUrl: delayTestUrl ?? this.delayTestUrl,
    );
    // 对当前选择的订阅进行优化
    var selectElements = config.profiles.where((e) => e.file == config.selectedFile);
    if (selectElements.isEmpty) {
      if (config.profiles.isEmpty) {
        config.selectedFile = null;
      } else {
        config.selectedFile = config.profiles.first.file;
      }
    }
    return config;
  }

  Future<void> saveFile(String path) {
    return File(path).create(recursive: true).then((file) => file.writeAsString(JsonMapper.serialize(this)));
  }

  factory ClashForMeConfig.defaultConfig() => ClashForMeConfig(
        profiles: [],
        mmdbUrl: DefaultConfigValue.mmdbUrl,
        delayTestUrl: DefaultConfigValue.delayTestUrl,
      );

  factory ClashForMeConfig.formYamlFile(String path) {
    var clashForMeFile = File(path);
    if (clashForMeFile.existsSync()) {
      Map<String, dynamic> cfm = json.decode(clashForMeFile.readAsStringSync());

      // 对必填项赋予默认值
      cfm.putIfAbsent("mmdb-url", () => DefaultConfigValue.mmdbUrl);
      cfm.putIfAbsent("delay-test-url", () => DefaultConfigValue.delayTestUrl);

      return JsonMapper.fromMap<ClashForMeConfig>(cfm)!;
    }
    return ClashForMeConfig.defaultConfig();
  }
}

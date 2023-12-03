import 'dart:io';

import 'package:clash_for_flutter/app/bean/tun_bean.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/utils/constants.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:settings_yaml/settings_yaml.dart';

@JsonSerializable()
class Config {
  static final String _path = "${Constants.homeDir.path}${Constants.clashConfig}";

  @JsonProperty(name: "mixed-port")
  int? mixedPort;
  @JsonProperty(name: "redir-port")
  int? redirPort;
  @JsonProperty(name: "tproxy-port")
  int? tproxyPort;
  @JsonProperty(name: "allow-lan")
  bool? allowLan;
  @JsonProperty(name: "mode")
  Mode? mode;
  @JsonProperty(name: "log-level")
  LogLevel? logLevel;
  @JsonProperty(name: "ipv6")
  bool? ipv6;
  @JsonProperty(name: "tun")
  Tun? tun;

  get tunEnable => tun?.enable;

  Config({
    this.mixedPort,
    this.redirPort,
    this.tproxyPort,
    this.allowLan,
    this.mode,
    this.logLevel,
    this.ipv6,
    this.tun,
  });

  Future<void> saveFile() {
    var yaml = SettingsYaml.load(pathToSettings: _path);
    if (redirPort != null) (yaml["redir-port"] = redirPort);
    if (tproxyPort != null) (yaml["tproxy-port"] = tproxyPort);
    if (mixedPort != null) (yaml["mixed-port"] = mixedPort);
    if (allowLan != null) (yaml["allow-lan"] = allowLan);
    if (mode != null) (yaml["mode"] = mode?.value);
    if (logLevel != null) (yaml["log-level"] = logLevel?.value);
    if (ipv6 != null) (yaml["ipv6"] = ipv6);
    return yaml.save();
  }

  Config copyWith({
    int? redirPort,
    int? tproxyPort,
    int? mixedPort,
    bool? allowLan,
    Mode? mode,
    LogLevel? logLevel,
    bool? ipv6,
  }) {
    return Config(
      redirPort: redirPort ?? this.redirPort,
      tproxyPort: tproxyPort ?? this.tproxyPort,
      mixedPort: mixedPort ?? this.mixedPort,
      allowLan: allowLan ?? this.allowLan,
      mode: mode ?? this.mode,
      logLevel: logLevel ?? this.logLevel,
      ipv6: ipv6 ?? this.ipv6,
    );
  }

  Config copy(Config? that) {
    that ??= this;
    return Config(
      redirPort: that.redirPort,
      tproxyPort: that.tproxyPort,
      mixedPort: that.mixedPort,
      allowLan: that.allowLan,
      mode: that.mode,
      logLevel: that.logLevel,
      ipv6: that.ipv6,
      tun: that.tun,
    );
  }

  static bool? fileExist() => File(_path).existsSync();

  factory Config.defaultConfig() => Config(mixedPort: 7890);
}

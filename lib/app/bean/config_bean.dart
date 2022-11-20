import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:settings_yaml/settings_yaml.dart';

@JsonSerializable()
class Config {
  @JsonProperty(name: "port")
  int? port;
  @JsonProperty(name: "socks-port")
  int? socksPort;
  @JsonProperty(name: "redir-port")
  int? redirPort;
  @JsonProperty(name: "tproxy-port")
  int? tproxyPort;
  @JsonProperty(name: "mixed-port")
  int? mixedPort;
  @JsonProperty(name: "allow-lan")
  bool? allowLan;
  @JsonProperty(name: "mode")
  Mode? mode;
  @JsonProperty(name: "log-level")
  LogLevel? logLevel;
  @JsonProperty(name: "ipv6")
  bool? ipv6;

  Config({
    this.port,
    this.socksPort,
    this.redirPort,
    this.tproxyPort,
    this.mixedPort,
    this.allowLan,
    this.mode,
    this.logLevel,
    this.ipv6,
  });

  Future<void> saveFile(String path) {
    var yaml = SettingsYaml.load(pathToSettings: path);
    if (port != null) (yaml["port"] = port);
    if (socksPort != null) (yaml["socks-port"] = socksPort);
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
    int? port,
    int? socksPort,
    int? redirPort,
    int? tproxyPort,
    int? mixedPort,
    bool? allowLan,
    Mode? mode,
    LogLevel? logLevel,
    bool? ipv6,
  }) {
    return Config(
      port: port ?? this.port,
      socksPort: socksPort ?? this.socksPort,
      redirPort: redirPort ?? this.redirPort,
      tproxyPort: tproxyPort ?? this.tproxyPort,
      mixedPort: mixedPort ?? this.mixedPort,
      allowLan: allowLan ?? this.allowLan,
      mode: mode ?? this.mode,
      logLevel: logLevel ?? this.logLevel,
      ipv6: ipv6 ?? this.ipv6,
    );
  }

  factory Config.defaultConfig() => Config(mixedPort: 7890);

  factory Config.formYamlFile(String path) {
    var yaml = SettingsYaml.load(pathToSettings: path);
    return Config(
      port: yaml["port"],
      socksPort: yaml["socks-port"],
      redirPort: yaml["redir-port"],
      tproxyPort: yaml["tproxy-port"],
      mixedPort: yaml["mixed-port"] ?? 7890,
      allowLan: yaml["allow-lan"],
      mode: Mode.values.singleWhere(
        (m) => m.value == yaml["mode"],
        orElse: () => Mode.Rule,
      ),
      logLevel: LogLevel.values.singleWhere(
        (m) => m.value == yaml["log-level"],
        orElse: () => LogLevel.info,
      ),
      ipv6: yaml["ipv6"],
    );
  }
}

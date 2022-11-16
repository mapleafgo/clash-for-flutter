import 'package:settings_yaml/settings_yaml.dart';

class Config {
  int? port;
  int? socksPort;
  int? redirPort;
  int? mixedPort;
  bool? allowLan;
  String? mode;
  String? logLevel;

  Config({
    this.port,
    this.socksPort,
    this.redirPort,
    this.mixedPort,
    this.allowLan,
    this.mode,
    this.logLevel,
  });

  Future<void> saveFile(String path) {
    var yaml = SettingsYaml.load(pathToSettings: path);
    if (port != null) (yaml["port"] = port);
    if (socksPort != null) (yaml["socks-port"] = socksPort);
    if (socksPort != null) (yaml["redir-port"] = socksPort);
    if (socksPort != null) (yaml["mixed-port"] = socksPort);
    if (allowLan != null) (yaml["allow-lan"] = allowLan);
    if (mode != null) (yaml["mode"] = mode);
    if (logLevel != null) (yaml["log-level"] = logLevel);
    return yaml.save();
  }

  Config copyWith({
    int? port,
    int? socksPort,
    int? redirPort,
    int? mixedPort,
    bool? allowLan,
    String? mode,
    String? logLevel,
  }) {
    return Config(
      port: port ?? this.port,
      socksPort: socksPort ?? this.socksPort,
      redirPort: redirPort ?? this.redirPort,
      mixedPort: mixedPort ?? this.mixedPort,
      allowLan: allowLan ?? this.allowLan,
      mode: mode ?? this.mode,
      logLevel: logLevel ?? this.logLevel,
    );
  }

  factory Config.defaultConfig() => Config(mixedPort: 7890);

  factory Config.formYamlFile(String path) {
    var yaml = SettingsYaml.load(pathToSettings: path);
    return Config(
      port: yaml["port"],
      socksPort: yaml["socks-port"],
      redirPort: yaml["redir-port"],
      mixedPort: yaml["mixed-port"],
      allowLan: yaml["allow-lan"],
      mode: yaml["mode"],
      logLevel: yaml["log-level"],
    );
  }
}

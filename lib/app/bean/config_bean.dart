import 'package:dart_json_mapper/dart_json_mapper.dart';

@JsonSerializable()
class Config {
  int port;
  @JsonProperty(name: "socks-port")
  int socksPort;
  @JsonProperty(name: "redir-port")
  int redirPort;
  @JsonProperty(name: "mixed-port")
  int mixedPort;
  @JsonProperty(name: "allow-lan")
  bool allowLan;
  String mode;
  @JsonProperty(name: "log-level")
  String logLevel;

  Config({
    required this.port,
    required this.socksPort,
    required this.redirPort,
    required this.mixedPort,
    required this.allowLan,
    required this.mode,
    required this.logLevel,
  });
}
